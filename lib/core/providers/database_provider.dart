import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../utils/day_math.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});


/// Emits the current local calendar day and refreshes at the next local
/// midnight. Tray-resident apps can stay alive across midnight, so providers
/// that depend on "today" must watch this rather than capturing DateTime.now()
/// once.
final dayChangeProvider = StreamProvider<DateTime>((ref) {
  final controller = StreamController<DateTime>();
  Timer? timer;

  void scheduleNextMidnight() {
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    timer = Timer(nextMidnight.difference(now), () {
      controller.add(DayMath.dateOnly(DateTime.now()));
      scheduleNextMidnight();
    });
  }

  controller.add(DayMath.dateOnly(DateTime.now()));
  scheduleNextMidnight();
  ref.onDispose(() {
    timer?.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});
