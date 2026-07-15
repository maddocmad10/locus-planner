import 'dart:async';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  final _timers = <int, Timer>{};
  int _idCounter = 0;
  Future<void> init() async { return; }
  Future<void> showNow({required String title, required String body}) async {
    print('[Locus] $title : $body');
  }
  Future<void> scheduleEventReminder({required String title, required DateTime scheduledTime, String body = 'Starting soon'}) async {
    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) return;
    final id = _idCounter++;
    _timers[id]?.cancel();
    _timers[id] = Timer(delay, () { showNow(title: title, body: body); _timers.remove(id); });
  }
  void cancelAll() { for (final t in _timers.values) { t.cancel(); } _timers.clear(); }
}
