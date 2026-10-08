import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../data/focus_repository.dart';

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
    this.isRestoring = true,
  });

  final int selectedMinutes;
  final int remainingSeconds;
  final FocusTimerStatus status;
  final String? projectId;

  /// Incremented every time a session finishes and has been saved. The UI
  /// listens to this to show a "well done" message.
  final int completedCount;
  final int lastCompletedMinutes;
  final bool isRestoring;

  bool get isRunning => status == FocusTimerStatus.running;

  double get progress {
    final totalSeconds = selectedMinutes * 60;
    if (totalSeconds <= 0) return 0.0;
    return (remainingSeconds / totalSeconds).clamp(0.0, 1.0);
  }

  FocusTimerState copyWith({
    int? selectedMinutes,
    int? remainingSeconds,
    FocusTimerStatus? status,
    String? projectId,
    bool clearProject = false,
    int? completedCount,
    int? lastCompletedMinutes,
    bool? isRestoring,
  }) {
    return FocusTimerState(
      selectedMinutes: selectedMinutes ?? this.selectedMinutes,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      status: status ?? this.status,
      projectId: clearProject ? null : (projectId ?? this.projectId),
      completedCount: completedCount ?? this.completedCount,
      lastCompletedMinutes: lastCompletedMinutes ?? this.lastCompletedMinutes,
      isRestoring: isRestoring ?? this.isRestoring,
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
  String? _sessionId;
  bool _disposed = false;
  static const _persistedKey = AppDatabase.focusSessionSettingKey;
  static const _defaultState = FocusTimerState();
  final _uuid = const Uuid();
  late final Future<void> _restoreFuture;

  @override
  FocusTimerState build() {
    ref.onDispose(() {
      _disposed = true;
      _ticker?.cancel();
    });
    _restoreFuture = _restorePersistedState();
    unawaited(_restoreFuture);
    return _defaultState;
  }

  void start() {
    if (state.isRestoring) return;
    if (state.isRunning) return;
    final now = DateTime.now();
    _sessionStart ??= now;
    _sessionId ??= _uuid.v4();
    _endsAt = now.add(Duration(seconds: state.remainingSeconds));
    state = state.copyWith(status: FocusTimerStatus.running);

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    unawaited(_persistState());
  }

  void pause() {
    if (state.isRestoring) return;
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
    _endsAt = null;
    unawaited(_persistState());
  }

  void reset() {
    if (state.isRestoring) return;
    _ticker?.cancel();
    _endsAt = null;
    _sessionStart = null;
    _sessionId = null;
    state = state.copyWith(
      status: FocusTimerStatus.idle,
      remainingSeconds: state.selectedMinutes * 60,
    );
    unawaited(_clearPersistedState());
  }

  /// Changing the length discards any session in progress, so the UI only
  /// offers it while the timer is not running.
  void setDuration(int minutes) {
    if (state.isRestoring) return;
    if (state.isRunning) return;
    minutes = minutes.clamp(1, 240).toInt();
    _endsAt = null;
    _sessionStart = null;
    _sessionId = null;
    state = state.copyWith(
      selectedMinutes: minutes,
      remainingSeconds: minutes * 60,
      status: FocusTimerStatus.idle,
    );
    unawaited(_clearPersistedState());
  }

  void setProject(String? projectId) {
    if (state.isRestoring) return;
    state = projectId == null
        ? state.copyWith(clearProject: true)
        : state.copyWith(projectId: projectId);
    unawaited(_persistState());
  }

  Future<void> _persistState() async {
    if (_disposed) return;
    final db = ref.read(databaseProvider);
    final payload = <String, dynamic>{
      'selectedMinutes': state.selectedMinutes,
      'remainingSeconds': state.isRunning
          ? _remainingNow()
          : state.remainingSeconds,
      'status': state.status.name,
      'projectId': state.projectId,
      'sessionId': _sessionId,
      'sessionStart': _sessionStart?.toIso8601String(),
      'endsAt': _endsAt?.toIso8601String(),
    };
    await db.setSetting(_persistedKey, jsonEncode(payload));
  }

  Future<void> _persistPendingCompletion({
    required String sessionId,
    required int durationMinutes,
    required String? projectId,
    required DateTime startedAt,
  }) async {
    if (_disposed) return;
    final payload = <String, dynamic>{
      'pendingCompletion': <String, dynamic>{
        'sessionId': sessionId,
        'durationMinutes': durationMinutes,
        'projectId': projectId,
        'startedAt': startedAt.toIso8601String(),
      },
    };
    await ref.read(databaseProvider).setSetting(
      _persistedKey,
      jsonEncode(payload),
    );
  }

  Future<void> _clearPersistedState() async {
    if (_disposed) return;
    await ref.read(databaseProvider).deleteSetting(_persistedKey);
  }

  Future<void> _restorePersistedState() async {
    try {
      final raw = await ref.read(databaseProvider).getSetting(_persistedKey);
      if (raw == null || _disposed) return;
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return;

      final pending = data['pendingCompletion'];
      if (pending is Map<String, dynamic>) {
        final sessionId = pending['sessionId'] as String?;
        final durationMinutes = (pending['durationMinutes'] as num?)?.toInt();
        final projectId = pending['projectId'] as String?;
        final startedAt = DateTime.tryParse(
          pending['startedAt'] as String? ?? '',
        );
        if (sessionId != null &&
            sessionId.trim().isNotEmpty &&
            durationMinutes != null &&
            durationMinutes >= 1 &&
            durationMinutes <= 24 * 60 &&
            startedAt != null) {
          try {
            await ref.read(focusRepositoryProvider).completeSession(
              sessionId: sessionId,
              durationMinutes: durationMinutes,
              projectId: projectId,
              startedAt: startedAt,
              notify: false,
            );
            await _clearPersistedState();
            if (!_disposed) {
              state = state.copyWith(
                completedCount: state.completedCount + 1,
                lastCompletedMinutes: durationMinutes,
              );
            }
          } catch (e, st) {
            debugPrint('Failed to recover focus session: $e\n$st');
          }
        } else {
          await _clearPersistedState();
        }
        return;
      }

      final rawMinutes = (data['selectedMinutes'] as num?)?.toInt() ?? 25;
      final minutes = rawMinutes.clamp(1, 240).toInt();
      final rawRemaining =
          (data['remainingSeconds'] as num?)?.toInt() ?? minutes * 60;
      final remaining = rawRemaining.clamp(0, minutes * 60).toInt();
      final projectId = data['projectId'] as String?;
      final sessionId = data['sessionId'] as String?;
      final sessionStart = DateTime.tryParse(
        data['sessionStart'] as String? ?? '',
      );
      final endsAt = DateTime.tryParse(data['endsAt'] as String? ?? '');
      final statusName = data['status'] as String? ?? 'idle';
      final status = FocusTimerStatus.values.firstWhere(
        (value) => value.name == statusName,
        orElse: () => FocusTimerStatus.idle,
      );

      _sessionId = sessionId;
      _sessionStart = sessionStart;
      _endsAt = endsAt;
      if (minutes != rawMinutes || remaining != rawRemaining) {
        await _clearPersistedState();
      }

      state = FocusTimerState(
        selectedMinutes: minutes,
        remainingSeconds: remaining,
        status: status,
        projectId: projectId,
      );

      if (status == FocusTimerStatus.running) {
        final left = _remainingNow();
        if (left <= 0) {
          await _complete(showNotification: false);
        } else {
          state = state.copyWith(remainingSeconds: left);
          _ticker?.cancel();
          _ticker = Timer.periodic(
            const Duration(milliseconds: 250),
            (_) => _tick(),
          );
        }
      }
    } catch (e, st) {
      debugPrint('Failed to restore focus timer: $e\n$st');
      await _clearPersistedState();
    } finally {
      if (!_disposed) {
        state = state.copyWith(isRestoring: false);
      }
    }
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

  Future<void> _complete({bool showNotification = true}) async {
    _ticker?.cancel();
    final minutes = state.selectedMinutes;
    final projectId = state.projectId;
    final startedAt =
        _sessionStart ?? DateTime.now().subtract(Duration(minutes: minutes));
    final sessionId = _sessionId;
    _endsAt = null;
    _sessionStart = null;

    // Back to a ready-to-start state straight away so a slow database write
    // can't leave the UI showing a running timer.
    state = state.copyWith(
      status: FocusTimerStatus.idle,
      remainingSeconds: minutes * 60,
    );

    if (showNotification) {
      SystemSound.play(SystemSoundType.alert).catchError((Object _) {});
    }

    try {
      await ref
          .read(focusRepositoryProvider)
          .completeSession(
            sessionId: sessionId,
            durationMinutes: minutes,
            projectId: projectId,
            startedAt: startedAt,
            notify: showNotification,
          );
      if (_disposed) return;
      await _clearPersistedState();
      _sessionId = null;
      state = state.copyWith(
        completedCount: state.completedCount + 1,
        lastCompletedMinutes: minutes,
      );
    } catch (e, st) {
      debugPrint('Failed to save focus session: $e\n$st');
      if (sessionId != null) {
        try {
          await _persistPendingCompletion(
            sessionId: sessionId,
            durationMinutes: minutes,
            projectId: projectId,
            startedAt: startedAt,
          );
        } catch (persistError, persistStack) {
          debugPrint(
            'Failed to persist focus-session recovery state: '
            '$persistError\n$persistStack',
          );
        }
      }
      _sessionId = null;
    }

    // The repository also sends the completion notification.
  }

  /// Waits for persisted timer state to finish restoring. Test hook only.
  @visibleForTesting
  Future<void> debugWaitForRestore() => _restoreFuture;

  /// Finishes the current session immediately. Test hook only.
  @visibleForTesting
  Future<void> debugComplete() => _complete();
}

final focusTimerProvider =
    NotifierProvider<FocusTimerNotifier, FocusTimerState>(
      FocusTimerNotifier.new,
    );
