import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import 'reminder_planner.dart';
import 'reminder_platform.dart';

final reminderPlatformProvider = Provider<ReminderPlatform>(
  (ref) => MethodChannelReminderPlatform(),
);

final mobileReminderServiceProvider = Provider<MobileReminderService>((ref) {
  final service = MobileReminderService(
    ref.watch(databaseProvider),
    ref.watch(reminderPlatformProvider),
  );
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});

/// Keeps the phone's reminders in step with the events table.
///
/// Events can change under the app at any time: the user adds one, or a sync
/// brings rows from the desktop. So instead of hooking each write, this
/// watches the table and rebuilds the whole window of upcoming reminders
/// (see [ReminderPlanner]) whenever it changes. The work is best-effort: a
/// failure never reaches the user, and the next change or app start tries
/// again.
class MobileReminderService {
  MobileReminderService(this._db, this._platform);

  final AppDatabase _db;
  final ReminderPlatform _platform;
  StreamSubscription<List<Event>>? _subscription;
  Future<void>? _inFlight;
  bool _again = false;

  /// Starts following the events table. Safe to call more than once.
  void start() {
    _subscription ??= _db.watchAllEvents().listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {
        // A broken stream must not take the app down; reminders are optional.
      },
    );
  }

  Future<void> stop() async {
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  /// Whether the user wants reminders on this phone. On unless switched off.
  Future<bool> isEnabled() async =>
      await _db.getSetting(AppDatabase.eventRemindersSettingKey) != 'false';

  Future<void> setEnabled(bool enabled) async {
    await _db.setSetting(
      AppDatabase.eventRemindersSettingKey,
      enabled.toString(),
    );
    await refresh();
  }

  /// Rebuilds the reminders from the stored events now. Calls that arrive while
  /// a rebuild is running are folded into one more pass, so a burst of changes
  /// (a sync applying many rows) costs at most two rebuilds.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _drain();
    _inFlight = run;
    return run;
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        await _apply();
      } while (_again);
    } finally {
      // Cleared in the same step as the last check of [_again], so a call can
      // never be folded into a pass that has already finished.
      _inFlight = null;
    }
  }

  Future<void> _apply() async {
    try {
      if (!await isEnabled()) {
        await _platform.cancelAll();
        return;
      }
      final events = await _db.select(_db.events).get();
      await _platform.replaceAll(
        ReminderPlanner.plan(events, now: AppClock.now()),
      );
    } catch (_) {
      // Best-effort; see the class comment.
    }
  }
}
