import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/day_math.dart';

class InsightsSummary {
  const InsightsSummary({
    required this.focusToday,
    required this.diaryStreak,
    required this.habits,
    required this.projects,
  });

  final int focusToday;
  final int diaryStreak;
  final List<Habit> habits;
  final List<Project> projects;
}

class HabitWeekStat {
  const HabitWeekStat({
    required this.name,
    required this.icon,
    required this.completed,
    required this.target,
  });

  final String name;
  final String icon;
  final int completed;
  final int target;
}

final insightsSummaryProvider = FutureProvider<InsightsSummary>((ref) async {
  final db = ref.watch(databaseProvider);
  final results = await Future.wait([
    db.focusMinutesToday(),
    db.diaryStreak(),
    db.watchHabits().first,
    db.watchProjects().first,
  ]);
  return InsightsSummary(
    focusToday: results[0] as int,
    diaryStreak: results[1] as int,
    habits: results[2] as List<Habit>,
    projects: results[3] as List<Project>,
  );
});

final focusLast14DaysProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(databaseProvider).watchFocusSessionsLastDays(14);
});

final diaryLast14DaysProvider = StreamProvider<List<DiaryEntry>>((ref) {
  final start = DayMath.addDays(DayMath.dateOnly(DateTime.now()), -13);
  final end = DayMath.addDays(DayMath.dateOnly(DateTime.now()), 1);
  return ref.watch(databaseProvider).watchDiaryEntriesForRange(start, end);
});

final habitWeekStatsProvider = FutureProvider<List<HabitWeekStat>>((ref) async {
  final db = ref.watch(databaseProvider);
  final habits = await db.watchHabits().first;
  if (habits.isEmpty) return const [];

  final start = DayMath.startOfWeek(DateTime.now());
  final end = DayMath.addDays(start, 7);
  final logs = await db.habitLogsForRange(start, end);
  final counts = <String, int>{};
  for (final log in logs) {
    if (log.completed) counts[log.habitId] = (counts[log.habitId] ?? 0) + 1;
  }

  return [
    for (final habit in habits)
      HabitWeekStat(
        name: habit.name,
        icon: habit.icon,
        completed: counts[habit.id] ?? 0,
        target: habit.targetPerWeek,
      ),
  ];
});
