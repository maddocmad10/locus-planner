import 'dart:async';

import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;
  final Map<String, Timer> _scheduledReminders = {};

  Future<void> init() async {
    if (_initialized) return;
    await localNotifier.setup(
      appName: 'Locus Planner',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
    _initialized = true;
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

  void dispose() {
    for (final timer in _scheduledReminders.values) {
      timer.cancel();
    }
    _scheduledReminders.clear();
  }
}
