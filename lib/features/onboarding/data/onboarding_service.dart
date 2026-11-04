import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../events/data/event_repository.dart';
import '../../habits/data/habit_repository.dart';
import '../../my_day/data/my_day_repository.dart';
import '../../tasks/data/task_repository.dart';

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService(
    ref.watch(databaseProvider),
    ref.watch(eventRepositoryProvider),
    ref.watch(taskRepositoryProvider),
    ref.watch(habitRepositoryProvider),
    ref.watch(myDayRepositoryProvider),
  );
});

/// Whether the local-first first-run card should be visible.
final shouldShowFirstRunProvider = FutureProvider.autoDispose<bool>((ref) {
  return ref.watch(onboardingServiceProvider).shouldShow();
});

/// Local-only first-run helpers. Nothing here performs network I/O.
class OnboardingService {
  OnboardingService(
    this._db,
    this._events,
    this._tasks,
    this._habits,
    this._myDay,
  );

  static const completedKey = 'onboarding.completed';

  final AppDatabase _db;
  final EventRepository _events;
  final TaskRepository _tasks;
  final HabitRepository _habits;
  final MyDayRepository _myDay;

  /// Show only when the marker is absent and no user data exists. Existing
  /// installations therefore never see the first-run card after upgrading.
  Future<bool> shouldShow() async {
    if (await _db.getSetting(completedKey) == 'true') return false;
    return _db.isUserDataEmpty();
  }

  Future<void> markComplete() => _db.setSetting(completedKey, 'true');

  /// Seeds a small, entirely synthetic data set that can be edited or deleted.
  Future<void> createSampleData() async {
    final now = AppClock.now();
    final today = DayMath.dateOnly(now);
    final tomorrow = DayMath.addDays(today, 1);
    final eventStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9);

    await _events.create(
      title: 'Plan the week',
      description: 'Sample event. Edit or delete it at any time.',
      startTime: eventStart,
      endTime: eventStart.add(const Duration(hours: 1)),
    );

    final firstTask = await _tasks.add(
      title: 'Review the quick-start guide',
      dueDate: today,
    );
    await _myDay.addTodo(day: today, todoId: firstTask, plannedMinutes: 15);
    await _tasks.add(title: 'Pick one task for tomorrow', dueDate: tomorrow);
    await _tasks.add(title: 'Try a focus session');

    await _habits.create(name: 'Drink water', targetPerWeek: 7);
    await markComplete();
  }
}
