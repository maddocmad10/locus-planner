import 'dart:async';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  final Map<String, _ScheduledReminder> _scheduledReminders = {};
  Timer? _overdueCheckTimer;

  Future<void> init() async {
    if (_initialized) return;
    await localNotifier.setup(
      appName: 'Locus Planner',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    final prefs = await SharedPreferences.getInstance();
    _eventRemindersEnabled = prefs.getBool('notifications.event_reminders') ?? true;
    _focusAlertsEnabled = prefs.getBool('notifications.focus_alerts') ?? true;
    _initialized = true;
    _overdueCheckTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_fireOverdueReminders());
    });
  }

  bool get eventRemindersEnabled => _eventRemindersEnabled;
  bool get focusAlertsEnabled => _focusAlertsEnabled;

  Future<void> setEventRemindersEnabled(bool enabled) async {
    if (!_initialized) await init();
    _eventRemindersEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications.event_reminders', enabled);
    if (!enabled) cancelAllEventReminders();
  }

  Future<void> setFocusAlertsEnabled(bool enabled) async {
    if (!_initialized) await init();
    _focusAlertsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications.focus_alerts', enabled);
  }

  Future<void> showFocusComplete({required int minutes}) async {
    if (!_initialized) await init();
    if (!_focusAlertsEnabled) return;
    await showNow(title: 'Focus Complete', body: '$minutes min logged');
  }

  Future<void> showNow({required String title, required String body}) async {
    if (!_initialized) await init();
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
    if (!_eventRemindersEnabled) return;
    _scheduledReminders.remove(eventId)?.timer?.cancel();

    final entry = _ScheduledReminder(
      scheduledTime: scheduledTime,
      title: title,
      body: body,
      onTriggered: onTriggered,
    );
    _scheduledReminders[eventId] = entry;
    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative || delay == Duration.zero) {
      unawaited(_fireReminder(eventId, entry));
      return;
    }
    entry.timer = Timer(delay, () => unawaited(_fireReminder(eventId, entry)));
  }

  Future<void> _fireOverdueReminders() async {
    if (!_eventRemindersEnabled) return;
    final now = DateTime.now();
    for (final entry in List<MapEntry<String, _ScheduledReminder>>.from(_scheduledReminders.entries)) {
      if (!entry.value.scheduledTime.isAfter(now)) {
        await _fireReminder(entry.key, entry.value);
      }
    }
  }

  Future<void> _fireReminder(String eventId, _ScheduledReminder entry) async {
    if (!identical(_scheduledReminders[eventId], entry)) return;
    _scheduledReminders.remove(eventId)?.timer?.cancel();
    try {
      await showNow(title: entry.title, body: entry.body);
      if (entry.onTriggered != null) await entry.onTriggered!();
    } catch (_) {
      // Notification failures must not crash the application timer.
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
