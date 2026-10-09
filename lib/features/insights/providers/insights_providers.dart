import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/project_model.dart';
import '../../projects/data/project_repository.dart';
import '../../../core/providers/clock_provider.dart';
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
  final List<ProjectModel> projects;
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

final insightsSummaryProvider = StreamProvider.autoDispose<InsightsSummary>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final projectRepository = ref.watch(projectRepositoryProvider);
  ref.watch(dayChangeProvider);
  return db.watchInsightsChanges().asyncMap((_) async {
    final results = await Future.wait([
      db.focusMinutesToday(),
      db.diaryStreak(),
      db.watchHabits().first,
      projectRepository.watchAll().first,
    ]);
    return InsightsSummary(
      focusToday: results[0] as int,
      diaryStreak: results[1] as int,
      habits: results[2] as List<Habit>,
      projects: results[3] as List<ProjectModel>,
    );
  });
});

final focusLast14DaysProvider = StreamProvider.autoDispose<List<FocusSession>>((
  ref,
) {
  ref.watch(dayChangeProvider);
  return ref.watch(databaseProvider).watchFocusSessionsLastDays(14);
});

final diaryLast14DaysProvider = StreamProvider.autoDispose<List<DiaryEntry>>((
  ref,
) {
  ref.watch(dayChangeProvider);
  final today = DayMath.dateOnly(ref.watch(clockProvider)());
  final start = DayMath.addDays(today, -13);
  final end = DayMath.addDays(today, 1);
  return ref.watch(databaseProvider).watchDiaryEntriesForRange(start, end);
});

final habitWeekStatsProvider = StreamProvider.autoDispose<List<HabitWeekStat>>((
  ref,
) {
  final db = ref.watch(databaseProvider);
  final clock = ref.watch(clockProvider);
  ref.watch(dayChangeProvider);
  return db.watchInsightsChanges().asyncMap((_) async {
    final habits = await db.watchHabits().first;
    if (habits.isEmpty) return const <HabitWeekStat>[];

    final start = DayMath.startOfWeek(clock());
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
});
