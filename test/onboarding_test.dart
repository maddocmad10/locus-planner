import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/notification_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/events/data/event_repository.dart';
import 'package:locus_planner/features/habits/data/habit_repository.dart';
import 'package:locus_planner/features/my_day/data/my_day_repository.dart';
import 'package:locus_planner/features/onboarding/data/onboarding_service.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late OnboardingService service;

  setUp(() async {
    AppClock.now = () => DateTime(2026, 11, 4, 10);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    final undo = UndoService();
    final events = EventRepository(db, NotificationService(), undo);
    final tasks = TaskRepository(db, undo);
    final habits = HabitRepository(db, undo, clock: AppClock.now);
    final projects = ProjectRepository(db, undo);
    final myDay = MyDayRepository(db, tasks, projects);
    service = OnboardingService(db, events, tasks, habits, myDay);
  });

  tearDown(() async {
    await db.close();
    AppClock.now = DateTime.now;
  });

  test(
    'shows only on an empty database without the completion marker',
    () async {
      expect(await service.shouldShow(), isTrue);

      await service.markComplete();
      expect(await service.shouldShow(), isFalse);
    },
  );

  test('existing data suppresses the first-run card', () async {
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'e1',
            title: 'Existing event',
            startTime: DateTime(2026, 11, 5, 9),
          ),
        );

    expect(await service.shouldShow(), isFalse);
  });

  test('sample data is local, sparse and populates My Day', () async {
    await service.createSampleData();

    final events = await db.select(db.events).get();
    final tasks = await db.select(db.todoItems).get();
    final habits = await db.select(db.habits).get();
    final planItems = await db.select(db.dailyPlanItems).get();

    expect(events, hasLength(1));
    expect(events.single.title, 'Plan the week');
    expect(events.single.startTime, DateTime(2026, 11, 5, 9));

    expect(tasks, hasLength(3));
    expect(
      tasks.map((task) => task.title),
      contains('Review the quick-start guide'),
    );
    expect(habits, hasLength(1));
    expect(habits.single.name, 'Drink water');

    // The first task is planned on today's My Day.
    expect(planItems, hasLength(1));
    expect(planItems.single.todoItemId, isNotNull);

    expect(await service.shouldShow(), isFalse);
    expect(await db.getSetting(OnboardingService.completedKey), 'true');
  });
}
