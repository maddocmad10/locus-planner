import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import 'clock_provider.dart';
import '../utils/day_math.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Emits the current local calendar day and again whenever it changes.
///
/// Tray-resident apps stay alive across midnight, so providers that depend on
/// "today" watch this instead of capturing the date once. It re-checks the
/// clock every [dayCheckIntervalProvider] rather than scheduling one timer for
/// midnight: a single long timer can fire hours late after the PC sleeps, while
/// a short periodic check is at most one interval late after waking.
final dayChangeProvider = StreamProvider<DateTime>((ref) {
  final clock = ref.read(clockProvider);
  final controller = StreamController<DateTime>();
  var current = DayMath.dateOnly(clock());
  controller.add(current);

  final timer = Timer.periodic(ref.read(dayCheckIntervalProvider), (_) {
    final today = DayMath.dateOnly(clock());
    if (today != current) {
      current = today;
      controller.add(today);
    }
  });

  ref.onDispose(() {
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});
