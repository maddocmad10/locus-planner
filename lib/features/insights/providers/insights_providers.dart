import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/database_provider.dart';

final focusLast7DaysProvider = FutureProvider<List<int>>((ref) async {
  final db = ref.watch(databaseProvider);
  final sessions = await db.focusSessionsLastDays(7);
  final now = DateTime.now();
  final result = List.filled(7, 0);
  for (final s in sessions) {
    final dayIndex = now.difference(DateTime(s.startTime.year, s.startTime.month, s.startTime.day)).inDays;
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
  final logs = await db.select(db.habitLogs).get();
  final map = <DateTime, int>{};
  for (final log in logs) {
    if (!log.completed) continue;
    final d = DateTime(log.date.year, log.date.month, log.date.day);
    map[d] = (map[d] ?? 0) + 1;
  }
  return map;
});
