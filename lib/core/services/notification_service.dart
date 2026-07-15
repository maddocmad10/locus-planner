import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  final _timers = <int, Timer>{};
  int _idCounter = 0;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const windows = WindowsInitializationSettings(
      appName: 'Locus Planner',
      appUserModelId: 'com.locus.planner',
      guid: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    );
    const settings = InitializationSettings(
      android: android,
      windows: windows,
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<void> showNow({required String title, required String body}) async {
    await init();
    final id = _idCounter++;
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        windows: WindowsNotificationDetails(),
        android: AndroidNotificationDetails(
          'locus_default',
          'Locus Notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
    if (kDebugMode) {
      // ignore: avoid_print
      print('[Locus] $title : $body');
    }
  }

  Future<void> scheduleEventReminder({
    required String title,
    required DateTime scheduledTime,
    String body = 'Starting soon',
  }) async {
    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) return;
    final id = _idCounter++;
    _timers[id]?.cancel();
    _timers[id] = Timer(delay, () {
      showNow(title: title, body: body);
      _timers.remove(id);
    });
  }

  void cancelAll() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }
}
