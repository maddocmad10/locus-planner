import 'dart:async';
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import '../models/reminder_kind.dart';
import '../utils/app_clock.dart';
import 'reminder_diagnostics.dart';

class _ScheduledReminder {
  _ScheduledReminder({
    required this.kind,
    required this.entityId,
    required this.scheduledTime,
    required this.title,
    required this.body,
    this.occurrenceKey,
    this.stableId,
    this.onTriggered,
    this.onSkippedLate,
    this.suppressKey,
  });

  /// `event` or `task`; independent of the timer key so canonical and legacy
  /// keys can be cancelled together.
  final String kind;
  final String entityId;
  final DateTime scheduledTime;
  final String title;
  final String body;
  final String? occurrenceKey;

  /// OS-visible id used for suppression and stable cancellation.
  final String? stableId;
  final Future<void> Function()? onTriggered;
  final Future<void> Function()? onSkippedLate;

  /// The OS-owned reminder id. Suppression is per reminder, so an unrelated
  /// immediate notification still appears.
  final String? suppressKey;
  Timer? timer;
}

class NotificationService {
  // Preserve the public `db:` constructor argument for callers and tests.
  // ignore: prefer_initializing_formals
  NotificationService({AppDatabase? db, this._showOverride}) : _db = db;

  static const maxReminderLateness = Duration(minutes: 15);
  static const _eventKeyPrefix = 'event:';
  static const _taskKeyPrefix = 'task:';

  /// Set while the Windows OS scheduler owns reminders. It is paired with
  /// [_osReminderKeys] so suppression applies only to reminders the OS really
  /// accepted; an unrelated immediate notification still works.
  static bool platformSchedulerActive = false;
  static final Set<String> _osReminderIds = <String>{};
  static final Set<String> _osEntityKeys = <String>{};

  static String reminderSuppressionKey(String kind, String entityId) =>
      '$kind:$entityId';

  /// Replaces the set of reminder IDs the OS has confirmed. Suppression is
  /// per occurrence ID, so unrelated notifications still appear. [entityKeys]
  /// covers an entity only when every planned occurrence was confirmed.
  static void setOsOwned({
    required Iterable<String> ids,
    required Iterable<String> entityKeys,
  }) {
    _osReminderIds
      ..clear()
      ..addAll(ids);
    _osEntityKeys
      ..clear()
      ..addAll(entityKeys);
  }

  static void clearOsScheduledIds() {
    platformSchedulerActive = false;
    _osReminderIds.clear();
    _osEntityKeys.clear();
  }

  static bool isOsOwnedId(String id) => _osReminderIds.contains(id);

  static void addOsOwnedId(String id) => _osReminderIds.add(id);

  static void removeOsOwnedId(String id) => _osReminderIds.remove(id);

  final AppDatabase? _db;
  final Future<void> Function({required String title, required String body})?
  _showOverride;
  bool _initialized = false;
  bool _available = true;
  bool _eventRemindersEnabled = true;
  bool _taskRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  final Map<String, _ScheduledReminder> _scheduledReminders = {};
  Timer? _overdueCheckTimer;
  Future<void>? _initFuture;

  /// Initializes the native notifier and loads preferences once. The inbox and
  /// the startup sequence can both call this before the first frame, so they
  /// must share one run instead of setting up `local_notifier` twice.
  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    if (_initialized) return;
    if (_showOverride == null) {
      try {
        await localNotifier.setup(
          appName: 'Locus Planner',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
      } catch (_) {
        // Notifications are optional. Keep the planner usable when the native
        // notifier cannot be initialized.
        _available = false;
      }
    }
    if (_showOverride != null) {
      _initialized = true;
      return;
    }
    try {
      _eventRemindersEnabled = await _readBool(
        AppDatabase.eventRemindersSettingKey,
        fallback: true,
      );
      _taskRemindersEnabled = await _readBool(
        AppDatabase.taskRemindersSettingKey,
        fallback: true,
      );
      _focusAlertsEnabled = await _readBool(
        AppDatabase.focusAlertsSettingKey,
        fallback: true,
      );
    } catch (_) {
      // Preference loading is also optional for the notification integration.
    }
    _initialized = true;
    if (_available) {
      _overdueCheckTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        unawaited(_fireOverdueReminders());
      });
    }
  }

  bool get eventRemindersEnabled => _eventRemindersEnabled;
  bool get taskRemindersEnabled => _taskRemindersEnabled;
  bool get focusAlertsEnabled => _focusAlertsEnabled;

  Future<void> setEventRemindersEnabled(bool enabled) async {
    if (!_initialized) await init();
    await _writeBool(AppDatabase.eventRemindersSettingKey, enabled);
    _eventRemindersEnabled = enabled;
    if (!enabled) cancelAllEventReminders();
  }

  Future<void> setTaskRemindersEnabled(bool enabled) async {
    if (!_initialized) await init();
    await _writeBool(AppDatabase.taskRemindersSettingKey, enabled);
    _taskRemindersEnabled = enabled;
    if (!enabled) cancelAllTaskReminders();
  }

  Future<void> setFocusAlertsEnabled(bool enabled) async {
    if (!_initialized) await init();
    await _writeBool(AppDatabase.focusAlertsSettingKey, enabled);
    _focusAlertsEnabled = enabled;
  }

  /// Re-reads preferences after an import replaces [AppDatabase.appSettings].
  Future<void> reloadPreferences() async {
    if (!_initialized) await init();
    _eventRemindersEnabled = await _readBool(
      AppDatabase.eventRemindersSettingKey,
      fallback: _eventRemindersEnabled,
    );
    _taskRemindersEnabled = await _readBool(
      AppDatabase.taskRemindersSettingKey,
      fallback: _taskRemindersEnabled,
    );
    _focusAlertsEnabled = await _readBool(
      AppDatabase.focusAlertsSettingKey,
      fallback: _focusAlertsEnabled,
    );
    if (!_eventRemindersEnabled) cancelAllEventReminders();
    if (!_taskRemindersEnabled) cancelAllTaskReminders();
  }

  Future<bool> _readBool(String key, {required bool fallback}) async {
    final db = _db;
    if (db != null) {
      final stored = await db.getSetting(key);
      if (stored != null) return stored == 'true';
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey(key)) {
          final value = prefs.getBool(key) ?? fallback;
          await db.setSetting(key, value.toString());
          return value;
        }
      } catch (_) {
        // Legacy preferences are a migration source, not a requirement.
      }
      return fallback;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _writeBool(String key, bool value) async {
    final db = _db;
    if (db != null) {
      await db.setSetting(key, value.toString());
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> showFocusComplete({required int minutes}) async {
    if (!_initialized) await init();
    if (!_focusAlertsEnabled) return;
    await showNow(title: 'Focus Complete', body: '$minutes min logged');
  }

  Future<void> showNow({
    required String title,
    required String body,
    String? suppressKey,
  }) async {
    if (!_initialized) await init();
    if (!_available) return;
    if (Platform.isWindows &&
        platformSchedulerActive &&
        suppressKey != null &&
        (_osReminderIds.contains(suppressKey) ||
            _osEntityKeys.contains(suppressKey))) {
      return;
    }
    if (_showOverride != null) {
      await _showOverride(title: title, body: body);
      return;
    }
    final notification = LocalNotification(title: title, body: body);
    await notification.show();
  }

  Future<void> scheduleEventReminder({
    required String eventId,
    required String title,
    required DateTime scheduledTime,
    String body = 'Starting soon',
    String? reminderId,
    String? stableId,
    Future<void> Function()? onTriggered,
    Future<void> Function()? onSkippedLate,
  }) async {
    if (!_initialized) await init();
    if (!_available || !_eventRemindersEnabled) return;
    final key = reminderId ?? '$_eventKeyPrefix$eventId';
    _scheduledReminders.remove(key)?.timer?.cancel();

    final entry = _ScheduledReminder(
      kind: ReminderKind.event.name,
      entityId: eventId,
      scheduledTime: scheduledTime,
      title: title,
      body: body,
      occurrenceKey: reminderId,
      stableId: stableId,
      onTriggered: onTriggered,
      onSkippedLate: onSkippedLate,
      suppressKey:
          stableId ?? reminderId ?? reminderSuppressionKey('event', eventId),
    );
    _scheduledReminders[key] = entry;
    ReminderDiagnostics.scheduled(kind: 'event');
    final delay = scheduledTime.difference(AppClock.now());
    if (delay.isNegative || delay == Duration.zero) {
      unawaited(_fireReminder(key, entry));
      return;
    }
    entry.timer = Timer(delay, () => unawaited(_fireReminder(key, entry)));
  }

  /// Arms a one-shot reminder for a to-do. Task reminders live in the same
  /// timer map as event reminders but are keyed with a distinct prefix so the
  /// two kinds can be cancelled independently.
  Future<void> scheduleTaskReminder({
    required String taskId,
    required String title,
    required DateTime scheduledTime,
    String body = 'Task reminder',
    String? reminderId,
    String? stableId,
    Future<void> Function()? onTriggered,
    Future<void> Function()? onSkippedLate,
  }) async {
    if (!_initialized) await init();
    if (!_available || !_taskRemindersEnabled) return;
    final key = reminderId ?? '$_taskKeyPrefix$taskId';
    _scheduledReminders.remove(key)?.timer?.cancel();

    final entry = _ScheduledReminder(
      kind: ReminderKind.task.name,
      entityId: taskId,
      scheduledTime: scheduledTime,
      title: title,
      body: body,
      occurrenceKey: reminderId,
      stableId: stableId,
      onTriggered: onTriggered,
      onSkippedLate: onSkippedLate,
      suppressKey:
          stableId ?? reminderId ?? reminderSuppressionKey('task', taskId),
    );
    _scheduledReminders[key] = entry;
    ReminderDiagnostics.scheduled(kind: 'task');
    final delay = scheduledTime.difference(AppClock.now());
    if (delay.isNegative || delay == Duration.zero) {
      unawaited(_fireReminder(key, entry));
      return;
    }
    entry.timer = Timer(delay, () => unawaited(_fireReminder(key, entry)));
  }

  void cancelTaskReminder(String taskId) {
    _scheduledReminders.remove('$_taskKeyPrefix$taskId')?.timer?.cancel();
  }

  /// Cancels one occurrence by its canonical reminder key or OS stable id.
  void cancelReminderId(String id) {
    for (final entry in _scheduledReminders.entries.toList()) {
      final reminder = entry.value;
      if (entry.key == id ||
          reminder.occurrenceKey == id ||
          reminder.stableId == id) {
        _scheduledReminders.remove(entry.key)?.timer?.cancel();
      }
    }
  }

  /// Cancels every in-process key for one entity/occurrence: the legacy
  /// `kind:entityId` timer, canonical occurrence keys, hashed fallbacks and
  /// stable ids. Callers use this for edit/delete/complete.
  void cancelOccurrence(
    ReminderKind kind,
    String entityId, {
    Iterable<String> keys = const [],
    Iterable<String> stableIds = const [],
    bool forgetOsOwned = true,
  }) {
    final prefix = '${kind.name}:$entityId@';
    final legacy = '${kind.name}:$entityId';
    final explicitKeys = keys.toSet();
    final explicitIds = stableIds.toSet();
    for (final entry in _scheduledReminders.entries.toList()) {
      final reminder = entry.value;
      final matches =
          entry.key == legacy ||
          explicitKeys.contains(entry.key) ||
          explicitIds.contains(entry.key) ||
          explicitIds.contains(reminder.stableId) ||
          (reminder.occurrenceKey?.startsWith(prefix) ?? false) ||
          (reminder.kind == kind.name && reminder.entityId == entityId);
      if (matches) {
        _scheduledReminders.remove(entry.key)?.timer?.cancel();
      }
    }
    if (forgetOsOwned) {
      _osReminderIds.removeAll(explicitIds);
      _osEntityKeys.remove('${kind.name}:$entityId');
    }
  }

  /// Cancels fallbacks whose moment passed while the machine slept. The
  /// persisted platform row still surfaces the occurrence in the inbox.
  void cancelPassedReminders(DateTime now) {
    for (final entry in _scheduledReminders.entries.toList()) {
      if (!entry.value.scheduledTime.isAfter(now)) {
        _scheduledReminders.remove(entry.key)?.timer?.cancel();
      }
    }
  }

  /// Keys currently armed in-process. Exposed for diagnostics and tests.
  Set<String> get scheduledReminderKeys =>
      Set<String>.unmodifiable(_scheduledReminders.keys);

  void cancelAllTaskReminders() {
    for (final entry in _scheduledReminders.entries.toList()) {
      final reminder = entry.value;
      if (reminder.kind == ReminderKind.task.name ||
          entry.key.startsWith(_taskKeyPrefix)) {
        _scheduledReminders.remove(entry.key)?.timer?.cancel();
      }
    }
  }

  Future<void> _fireOverdueReminders() async {
    if (!_eventRemindersEnabled && !_taskRemindersEnabled) return;
    final now = AppClock.now();
    for (final entry in List<MapEntry<String, _ScheduledReminder>>.from(
      _scheduledReminders.entries,
    )) {
      if (!entry.value.scheduledTime.isAfter(now)) {
        await _fireReminder(entry.key, entry.value);
      }
    }
  }

  Future<void> _fireReminder(String eventId, _ScheduledReminder entry) async {
    if (!identical(_scheduledReminders[eventId], entry)) return;
    _scheduledReminders.remove(eventId)?.timer?.cancel();

    final kind = entry.kind;
    // A preference turned off between arming and firing must never pop up.
    if (kind == ReminderKind.task.name && !_taskRemindersEnabled) return;
    if (kind == ReminderKind.event.name && !_eventRemindersEnabled) return;

    final lateness = AppClock.now().difference(entry.scheduledTime);
    final minutesLate = lateness.inMinutes < 0 ? 0 : lateness.inMinutes;
    if (lateness <= maxReminderLateness) {
      try {
        await showNow(
          title: entry.title,
          body: entry.body,
          suppressKey: entry.suppressKey,
        );
        ReminderDiagnostics.fired(kind: kind, minutesLate: minutesLate);
      } catch (_) {
        // A notification failure must not prevent the recurring reminder from
        // being re-armed below.
      }
    } else {
      // A popup that old would be noise, but the reminder must not disappear.
      // The missed-reminder inbox keeps it available for review and snooze.
      try {
        ReminderDiagnostics.skippedLate(kind: kind, minutesLate: minutesLate);
        if (entry.onSkippedLate != null) await entry.onSkippedLate!();
      } catch (_) {
        // The inbox is best-effort; re-arming below still matters more.
      }
    }

    try {
      if (entry.onTriggered != null) await entry.onTriggered!();
    } catch (_) {
      // Re-arming is best-effort and must never escape the timer callback.
    }
  }

  void cancelEventReminder(String eventId) {
    _scheduledReminders.remove('$_eventKeyPrefix$eventId')?.timer?.cancel();
  }

  void cancelAllEventReminders() {
    for (final entry in _scheduledReminders.entries.toList()) {
      final reminder = entry.value;
      if (reminder.kind == ReminderKind.event.name ||
          entry.key.startsWith(_eventKeyPrefix)) {
        _scheduledReminders.remove(entry.key)?.timer?.cancel();
      }
    }
  }

  void dispose() {
    _overdueCheckTimer?.cancel();
    _overdueCheckTimer = null;
    cancelAllEventReminders();
    cancelAllTaskReminders();
  }
}
