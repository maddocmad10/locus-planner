import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';

enum FocusTimerStatus { idle, running, paused }

@immutable
class FocusTimerState {
  const FocusTimerState({
    this.selectedMinutes = 25,
    this.remainingSeconds = 25 * 60,
    this.status = FocusTimerStatus.idle,
    this.projectId,
    this.completedCount = 0,
    this.lastCompletedMinutes = 0,
  });

  final int selectedMinutes;
  final int remainingSeconds;
  final FocusTimerStatus status;
  final String? projectId;

  /// Incremented every time a session finishes and has been saved. The UI
  /// listens to this to show a "well done" message.
  final int completedCount;
  final int lastCompletedMinutes;

  bool get isRunning => status == FocusTimerStatus.running;

  double get progress =>
      (remainingSeconds / (selectedMinutes * 60)).clamp(0.0, 1.0);

  FocusTimerState copyWith({
    int? selectedMinutes,
    int? remainingSeconds,
    FocusTimerStatus? status,
    String? projectId,
    bool clearProject = false,
    int? completedCount,
    int? lastCompletedMinutes,
  }) {
    return FocusTimerState(
      selectedMinutes: selectedMinutes ?? this.selectedMinutes,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      status: status ?? this.status,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      completedCount: completedCount ?? this.completedCount,
      lastCompletedMinutes: lastCompletedMinutes ?? this.lastCompletedMinutes,
    );
  }
}

/// Owns the focus countdown. It lives in the provider scope (not in a widget),
/// so switching tabs, or the Focus page being rebuilt, no longer cancels the
/// timer or loses the session.
///
/// The countdown is derived from an end timestamp rather than by decrementing a
/// counter, so it stays accurate if ticks are delayed (minimised window,
/// machine sleep).
class FocusTimerNotifier extends Notifier<FocusTimerState> {
  Timer? _ticker;
  DateTime? _endsAt;
  DateTime? _sessionStart;
  bool _disposed = false;

  @override
  FocusTimerState build() {
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
    });
    return const FocusTimerState();
  }

  void start() {
    if (state.isRunning) return;
    final now = DateTime.now();
    _sessionStart ??= now;
    _endsAt = now.add(Duration(seconds: state.remainingSeconds));
    state = state.copyWith(status: FocusTimerStatus.running);

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    final remaining = _remainingNow();
    if (remaining <= 0) {
      unawaited(_complete());
      return;
    }
    state = state.copyWith(
      status: FocusTimerStatus.paused,
      remainingSeconds: remaining,
    );
  }

  void reset() {
    _ticker?.cancel();
    _endsAt = null;
    _sessionStart = null;
    state = state.copyWith(
      status: FocusTimerStatus.idle,
      remainingSeconds: state.selectedMinutes * 60,
    );
  }

  /// Changing the length discards any session in progress, so the UI only
  /// offers it while the timer is not running.
  void setDuration(int minutes) {
    if (state.isRunning) return;
    _endsAt = null;
    _sessionStart = null;
    state = state.copyWith(
      selectedMinutes: minutes,
      remainingSeconds: minutes * 60,
      status: FocusTimerStatus.idle,
    );
  }

  void setProject(String? projectId) {
    state = projectId == null
        ? state.copyWith(clearProject: true)
        : state.copyWith(projectId: projectId);
  }

  int _remainingNow() {
    final endsAt = _endsAt;
    if (endsAt == null) return state.remainingSeconds;
    final ms = endsAt.difference(DateTime.now()).inMilliseconds;
    return math.max(0, (ms / 1000).ceil());
  }

  void _tick() {
    final remaining = _remainingNow();
    if (remaining <= 0) {
      unawaited(_complete());
    } else if (remaining != state.remainingSeconds) {
      state = state.copyWith(remainingSeconds: remaining);
    }
  }

  Future<void> _complete() async {
    _ticker?.cancel();
    final minutes = state.selectedMinutes;
    final projectId = state.projectId;
    final startedAt =
        _sessionStart ?? DateTime.now().subtract(Duration(minutes: minutes));
    _endsAt = null;
    _sessionStart = null;

    // Back to a ready-to-start state straight away so a slow database write
    // can't leave the UI showing a running timer.
    state = state.copyWith(
      status: FocusTimerStatus.idle,
      remainingSeconds: minutes * 60,
    );

    SystemSound.play(SystemSoundType.alert).catchError((Object _) {});

    try {
      final db = ref.read(databaseProvider);
      // The project may have been deleted while the timer ran. Foreign keys are
      // enforced, so linking to a missing project would fail the insert and
      // lose the session; save it unlinked instead.
      final project = projectId == null
          ? null
          : await (db.select(db.projects)..where((t) => t.id.equals(projectId)))
              .getSingleOrNull();
      await db.into(db.focusSessions).insert(FocusSessionsCompanion(
            id: drift.Value(const Uuid().v4()),
            projectId: drift.Value(project?.id),
            startTime: drift.Value(startedAt),
            durationMinutes: drift.Value(minutes),
            note: const drift.Value('Completed focus session'),
          ));
      if (_disposed) return;
      state = state.copyWith(
        completedCount: state.completedCount + 1,
        lastCompletedMinutes: minutes,
      );
    } catch (e, st) {
      debugPrint('Failed to save focus session: $e\n$st');
    }

    // The timer keeps running while the user is on another tab, where the
    // Focus page's snackbar can't show, so also raise a system notification.
    try {
      await NotificationService.instance.showNow(
        title: 'Focus Complete',
        body: '$minutes min logged',
      );
    } catch (e) {
      debugPrint('Could not show focus notification: $e');
    }
  }

  /// Finishes the current session immediately. Test hook only.
  @visibleForTesting
  Future<void> debugComplete() => _complete();
}

final focusTimerProvider =
    NotifierProvider<FocusTimerNotifier, FocusTimerState>(FocusTimerNotifier.new);
