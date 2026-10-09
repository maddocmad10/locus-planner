import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../projects/data/project_repository.dart';
import '../../../core/providers/clock_provider.dart';
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

final dashboardStatsProvider = StreamProvider.autoDispose<DashboardStats>((
  ref,
) {
  // Read every dependency now: a provider's ref shouldn't be used from the
  // async callbacks below, which can run after the provider was rebuilt.
  final db = ref.watch(databaseProvider);
  final eventRepository = ref.watch(eventRepositoryProvider);
  final diaryRepository = ref.watch(diaryRepositoryProvider);
  final clock = ref.watch(clockProvider);
  ref.watch(dayChangeProvider);

  return db.watchDashboardChanges().asyncMap((_) async {
    final events = await eventRepository.watchForDay(clock()).first;
    final habits = await db.watchHabits().first;
    final habitsDone = await db.completedHabitsToday();
    final focusMinutes = await db.focusMinutesToday();
    final diaryStreak = await diaryRepository.streak();

    return DashboardStats(
      eventsToday: events.length,
      habitsDone: habitsDone,
      habitsTotal: habits.length,
      focusMinutes: focusMinutes,
      diaryStreak: diaryStreak,
    );
  });
});

final todayEventsProvider = StreamProvider.autoDispose<List<EventOccurrence>>((
  ref,
) {
  final clock = ref.watch(clockProvider);
  ref.watch(dayChangeProvider);
  return ref.watch(eventRepositoryProvider).watchForDay(clock());
});

final activeProjectsProvider = StreamProvider((ref) {
  return ref.watch(projectRepositoryProvider).watchAll();
});

final projectProgressProvider = StreamProvider<Map<String, double>>((ref) {
  return ref.watch(databaseProvider).watchProjectProgress();
});
