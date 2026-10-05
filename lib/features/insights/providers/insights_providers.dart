import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/day_math.dart';

final focusLast7DaysProvider = FutureProvider<List<int>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sessions = await db.focusSessionsLastDays(7);
  final now = DateTime.now();
  final result = List.filled(7, 0);
  for (final s in sessions) {
    final dayIndex = DayMath.calendarDaysBetween(s.startTime, now);
    if (dayIndex >= 0 && dayIndex < 7) {
      result[6 - dayIndex] += s.durationMinutes;
    }
  }
  return result;
});

final categoryCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  return ref.watch(databaseProvider).eventCategoryCounts();
});

final habitHeatmapProvider = FutureProvider<Map<DateTime, int>>((ref) async {
  final db = ref.watch(databaseProvider);
  final cutoff = DayMath.addDays(DayMath.dateOnly(DateTime.now()), -364);
  final logs = await (db.select(
    db.habitLogs,
  )..where((t) => t.date.isBiggerOrEqualValue(cutoff))).get();
  final map = <DateTime, int>{};
  for (final log in logs) {
    if (!log.completed) continue;
    final d = DateTime(log.date.year, log.date.month, log.date.day);
    map[d] = (map[d] ?? 0) + 1;
  }
  return map;
});
