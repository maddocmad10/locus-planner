import 'dart:async';

import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  final Map<String, Timer> _scheduledReminders = {};

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

    final notification = LocalNotification(
      title: title,
      body: body,
    );
    await notification.show();
  }

  Future<void> scheduleEventReminder({
    required String eventId,
    required String title,
    required DateTime scheduledTime,
    String body = 'Starting soon',
  }) async {
    if (!_initialized) await init();
    if (!_eventRemindersEnabled) return;
    _scheduledReminders.remove(eventId)?.cancel();

    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) return;

    final timer = Timer(delay, () async {
      _scheduledReminders.remove(eventId);
      try {
        await showNow(title: title, body: body);
      } catch (_) {
        // Notification failures must not crash the application timer.
      }
    });
    _scheduledReminders[eventId] = timer;
  }

  void cancelEventReminder(String eventId) {
    _scheduledReminders.remove(eventId)?.cancel();
  }

  void cancelAllEventReminders() {
    for (final timer in _scheduledReminders.values) {
      timer.cancel();
    }
    _scheduledReminders.clear();
  }

  void dispose() {
    for (final timer in _scheduledReminders.values) {
      timer.cancel();
    }
    _scheduledReminders.clear();
  }
}
