import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/data/project_repository.dart';
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

final dashboardStatsProvider = StreamProvider.autoDispose<DashboardStats>((ref) {
  final db = ref.watch(databaseProvider);
  ref.watch(dayChangeProvider);
  return db.watchDashboardChanges().asyncMap((_) async {
    final today = DateTime.now();
    final events = await ref.watch(eventRepositoryProvider).watchForDay(today).first;
    final habits = await db.watchHabits().first;
    final habitsDone = await db.completedHabitsToday();
    final focusMinutes = await db.focusMinutesToday();
    final diaryStreak = await ref.watch(diaryRepositoryProvider).streak();

    return DashboardStats(
      eventsToday: events.length,
      habitsDone: habitsDone,
      habitsTotal: habits.length,
      focusMinutes: focusMinutes,
      diaryStreak: diaryStreak,
    );
  });
});

final todayEventsProvider = StreamProvider.autoDispose<List<EventOccurrence>>((ref) {
  ref.watch(dayChangeProvider);
  return ref.watch(eventRepositoryProvider).watchForDay(DateTime.now());
});

final activeProjectsProvider = StreamProvider((ref) {
  return ref.watch(projectRepositoryProvider).watchAll();
});

final projectProgressProvider = StreamProvider<Map<String, double>>((ref) {
  return ref.watch(databaseProvider).watchProjectProgress();
});
