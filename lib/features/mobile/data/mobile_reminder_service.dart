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

/// Keeps the phone's reminders in step with the events and to-do tables.
///
/// Events and tasks can change under the app at any time: the user edits one,
/// or a sync brings rows from the desktop. Watch both tables and rebuild the
/// whole window of upcoming reminders (see [ReminderPlanner]) whenever either
/// changes.
class MobileReminderService {
  MobileReminderService(this._db, this._platform);

  final AppDatabase _db;
  final ReminderPlatform _platform;
  StreamSubscription<List<Event>>? _eventSubscription;
  StreamSubscription<List<TodoItem>>? _taskSubscription;
  Future<void>? _inFlight;
  bool _again = false;

  /// Starts following events and tasks. Safe to call more than once.
  void start() {
    _eventSubscription ??= _db.watchAllEvents().listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {
        // A broken stream must not take the app down; reminders are optional.
      },
    );
    _taskSubscription ??= _db.watchAllTodoItems().listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {},
    );
  }

  Future<void> stop() async {
    final events = _eventSubscription;
    final tasks = _taskSubscription;
    _eventSubscription = null;
    _taskSubscription = null;
    await events?.cancel();
    await tasks?.cancel();
  }

  /// Whether the user wants event reminders on this phone.
  Future<bool> isEnabled() async =>
      await _db.getSetting(AppDatabase.eventRemindersSettingKey) != 'false';

  Future<void> setEnabled(bool enabled) async {
    await _db.setSetting(
      AppDatabase.eventRemindersSettingKey,
      enabled.toString(),
    );
    await refresh();
  }

  /// Whether the user wants task reminders on this phone.
  Future<bool> tasksEnabled() async =>
      await _db.getSetting(AppDatabase.taskRemindersSettingKey) != 'false';

  Future<void> setTasksEnabled(bool enabled) async {
    await _db.setSetting(
      AppDatabase.taskRemindersSettingKey,
      enabled.toString(),
    );
    await refresh();
  }

  /// Rebuilds the reminders from the stored rows now. Calls that arrive while
  /// a rebuild is running are folded into one more pass.
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
      _inFlight = null;
    }
  }

  Future<void> _apply() async {
    try {
      final events = await isEnabled();
      final tasks = await tasksEnabled();
      if (!events && !tasks) {
        await _platform.cancelAll();
        return;
      }
      final now = AppClock.now();
      final sources = <PlannedSource>[
        if (events)
          ...ReminderPlanner.sourcesForEvents(
            await _db.select(_db.events).get(),
            now: now,
          ),
        if (tasks)
          ...ReminderPlanner.sourcesForTasks(
            await _db.select(_db.todoItems).get(),
            now: now,
          ),
      ];
      final plan = ReminderPlanner.plan(sources, now: now);
      await _platform.replaceAll(plan);
    } catch (_) {
      // Best-effort; see the class comment.
    }
  }
}
