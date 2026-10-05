import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../diary/data/diary_repository.dart';
import '../../events/data/event_repository.dart';

class DashboardStats {
  const DashboardStats({
    required this.eventsToday,
    required this.habitsDone,
    required this.habitsTotal,
    required this.focusMinutes,
    required this.diaryStreak,
  });

  final int eventsToday;
  final int habitsDone;
  final int habitsTotal;
  final int focusMinutes;
  final int diaryStreak;
}

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final db = ref.watch(databaseProvider);
  final today = DateTime.now();
  final events = await db.watchEventsForDay(today).first;
  final habits = await db.watchHabits().first;
  final habitsDone = await db.completedHabitsToday();
  final focusMin = await db.focusMinutesToday();
  final streak = await ref.read(diaryRepositoryProvider).streak();
  return DashboardStats(
    eventsToday: events.length,
    habitsDone: habitsDone,
    habitsTotal: habits.length,
    focusMinutes: focusMin,
    diaryStreak: streak,
  );
});

final todayEventsProvider = StreamProvider<List<Event>>((ref) {
  final today = DateTime.now();
  return ref.watch(eventRepositoryProvider).watchForDay(today);
});

final activeProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(databaseProvider).watchProjects();
});

final projectProgressProvider =
    FutureProvider.family<double, String>((ref, projectId) async {
  return ref.watch(databaseProvider).projectProgressPercent(projectId);
});
