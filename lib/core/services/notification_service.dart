import 'dart:async';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/app_database.dart';
import '../utils/app_clock.dart';

class _ScheduledReminder {
  _ScheduledReminder({
    required this.scheduledTime,
    required this.title,
    required this.body,
    this.onTriggered,
  });

  final DateTime scheduledTime;
  final String title;
  final String body;
  final Future<void> Function()? onTriggered;
  Timer? timer;
}

class NotificationService {
  NotificationService({AppDatabase? db, this._showOverride}) : _db = db;

  static const maxReminderLateness = Duration(minutes: 15);

  final AppDatabase? _db;
  final Future<void> Function({required String title, required String body})?
  _showOverride;
  bool _initialized = false;
  bool _available = true;
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  final Map<String, _ScheduledReminder> _scheduledReminders = {};
  Timer? _overdueCheckTimer;

  Future<void> init() async {
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
  bool get focusAlertsEnabled => _focusAlertsEnabled;

  Future<void> setEventRemindersEnabled(bool enabled) async {
    if (!_initialized) await init();
    await _writeBool(AppDatabase.eventRemindersSettingKey, enabled);
    _eventRemindersEnabled = enabled;
    if (!enabled) cancelAllEventReminders();
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
    _focusAlertsEnabled = await _readBool(
      AppDatabase.focusAlertsSettingKey,
      fallback: _focusAlertsEnabled,
    );
    if (!_eventRemindersEnabled) cancelAllEventReminders();
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

  Future<void> showNow({required String title, required String body}) async {
    if (!_initialized) await init();
    if (!_available) return;
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
    Future<void> Function()? onTriggered,
  }) async {
    if (!_initialized) await init();
    if (!_available || !_eventRemindersEnabled) return;
    _scheduledReminders.remove(eventId)?.timer?.cancel();

    final entry = _ScheduledReminder(
      scheduledTime: scheduledTime,
      title: title,
      body: body,
      onTriggered: onTriggered,
    );
    _scheduledReminders[eventId] = entry;
    final delay = scheduledTime.difference(AppClock.now());
    if (delay.isNegative || delay == Duration.zero) {
      unawaited(_fireReminder(eventId, entry));
      return;
    }
    entry.timer = Timer(delay, () => unawaited(_fireReminder(eventId, entry)));
  }

  Future<void> _fireOverdueReminders() async {
    if (!_eventRemindersEnabled) return;
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

    final lateness = AppClock.now().difference(entry.scheduledTime);
    if (lateness <= maxReminderLateness) {
      try {
        await showNow(title: entry.title, body: entry.body);
      } catch (_) {
        // A notification failure must not prevent the recurring reminder from
        // being re-armed below.
      }
    }

    try {
      if (entry.onTriggered != null) await entry.onTriggered!();
    } catch (_) {
      // Re-arming is best-effort and must never escape the timer callback.
    }
  }

  void cancelEventReminder(String eventId) {
    _scheduledReminders.remove(eventId)?.timer?.cancel();
  }

  void cancelAllEventReminders() {
    for (final entry in _scheduledReminders.values) {
      entry.timer?.cancel();
    }
    _scheduledReminders.clear();
  }

  void dispose() {
    _overdueCheckTimer?.cancel();
    _overdueCheckTimer = null;
    cancelAllEventReminders();
  }
}
