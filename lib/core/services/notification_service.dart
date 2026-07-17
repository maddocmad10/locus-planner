import 'package:local_notifier/local_notifier.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  bool _initialized = false;

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
    required String title,
    required DateTime scheduledTime,
    String body = 'Starting soon',
  }) async {
    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) return;

    // For Phase 1, we show immediately when time comes using a timer
    Future.delayed(delay, () async {
      await showNow(title: title, body: body);
    });
  }
}
