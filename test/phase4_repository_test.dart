import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/planning/capacity_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/day_math.dart';
import 'package:locus_planner/core/utils/sync_ids.dart';
import 'package:locus_planner/features/calendar/data/planning_preferences_repository.dart';
import 'package:locus_planner/features/my_day/data/my_day_models.dart';
import 'package:locus_planner/features/planning_intelligence/data/planning_repository.dart';
import 'package:locus_planner/features/planning_intelligence/data/planning_snapshot_repository.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_engine.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_models.dart';

void main() {
  late AppDatabase db;
  late UndoService undo;
  late PlanningPreferencesRepository preferences;
  late PlanningSnapshotRepository snapshots;
  late PlanningRepository planning;

  final today = DateTime(2026, 5, 20);
  final tomorrow = DateTime(2026, 5, 21);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    undo = UndoService();
    preferences = PlanningPreferencesRepository(db);
    snapshots = PlanningSnapshotRepository(db, preferences);
    planning = PlanningRepository(db, undo, preferences);
    await preferences.replaceWorkingHours([
      for (var weekday = 1; weekday <= 7; weekday++)
        WorkingWindowDraft(
          id: 'hours-$weekday',
          weekday: weekday,
          startMinute: 9 * 60,
          endMinute: 12 * 60,
        ),
    ]);
    await preferences.savePreferences(
      defaultSlotMinutes: 30,
      dayStartMinute: 9 * 60,
      dayEndMinute: 17 * 60,
      bufferMinutes: 0,
      urgencyWindowDays: 3,
    );
  });

  tearDown(() async {
    undo.dispose();
    await db.close();
  });

  Future<String> addTodo(String title) => db.addTodoItem(title, null);

  Future<void> addBlock(String todoId, DateTime start, DateTime end) async {
    await db
        .into(db.taskScheduleBlocks)
        .insert(
          TaskScheduleBlocksCompanion.insert(
            id: const Uuid().v4(),
            todoItemId: Value(todoId),
            startAt: start,
            endAt: end,
            createdAt: DateTime(2026, 5, 19),
            updatedAt: DateTime(2026, 5, 19),
          ),
        );
  }

  test(
    'overcommitted suggestion moves a block transactionally and undoes',
    () async {
      final a = await addTodo('A');
      final b = await addTodo('B');
      await (db.update(db.todoItems)..where((t) => t.id.equals(a))).write(
        const TodoItemsCompanion(priority: Value(3)),
      );
      await addBlock(a, DateTime(2026, 5, 20, 9), DateTime(2026, 5, 20, 12));
      await addBlock(b, DateTime(2026, 5, 20, 9), DateTime(2026, 5, 20, 10));

      final snapshot = await snapshots.load(now: today);
      final result = PlanningEngine.build(snapshot);
      final suggestion = result.suggestions.firstWhere(
        (suggestion) =>
            suggestion.type == PlanningSuggestionType.overcommittedDay,
      );
      expect(
        suggestion.operations.whereType<MoveBlockOperation>(),
        hasLength(1),
      );

      final before = await db.select(db.taskScheduleBlocks).get();
      await planning.applySuggestion(suggestion);
      final after = await db.select(db.taskScheduleBlocks).get();
      expect(after, hasLength(2));
      final moved = after.firstWhere((block) => block.todoItemId == b);
      expect(moved.startAt, DateTime(2026, 5, 21, 9));
      expect(moved.endAt, DateTime(2026, 5, 21, 10));

      expect(await undo.undo(), isTrue);
      final restored = await db.select(db.taskScheduleBlocks).get();
      expect(
        restored.firstWhere((block) => block.todoItemId == b).startAt,
        before.firstWhere((block) => block.todoItemId == b).startAt,
      );
    },
  );

  test(
    'focus/unscheduled suggestion creates a block and undo removes it',
    () async {
      final id = await addTodo('Focus');
      await (db.update(db.todoItems)..where((t) => t.id.equals(id))).write(
        const TodoItemsCompanion(
          priority: Value(3),
          estimatedMinutes: Value(45),
        ),
      );

      final snapshot = await snapshots.load(now: today);
      final result = PlanningEngine.build(snapshot);
      final suggestion = result.suggestions.firstWhere(
        (suggestion) =>
            suggestion.type == PlanningSuggestionType.unscheduledPriority ||
            suggestion.type == PlanningSuggestionType.focusWindow,
      );
      await planning.applySuggestion(suggestion);
      final blocks = await db.select(db.taskScheduleBlocks).get();
      expect(blocks, hasLength(1));
      expect(blocks.single.todoItemId, id);
      expect(blocks.single.startAt, DateTime(2026, 5, 20, 9));

      expect(await undo.undo(), isTrue);
      expect(await db.select(db.taskScheduleBlocks).get(), isEmpty);
    },
  );

  test(
    'carry-forward can move to another date without duplicating rows',
    () async {
      final todoId = await addTodo('Carry me');
      final yesterday = DayMath.addDays(today, -1);
      final yesterdayPlanId = SyncIds.dailyPlanId(yesterday);
      await db
          .into(db.dailyPlans)
          .insert(
            DailyPlansCompanion.insert(
              id: yesterdayPlanId,
              dayKey: myDayKey(yesterday),
              createdAt: DateTime(2026, 5, 19),
              updatedAt: DateTime(2026, 5, 19),
            ),
          );
      await db
          .into(db.dailyPlanItems)
          .insert(
            DailyPlanItemsCompanion.insert(
              id: 'item-1',
              planId: yesterdayPlanId,
              todoItemId: Value(todoId),
              createdAt: DateTime(2026, 5, 19),
              updatedAt: DateTime(2026, 5, 19),
            ),
          );

      final snapshot = await snapshots.load(now: today);
      final result = PlanningEngine.build(snapshot);
      final suggestion = result.suggestions.firstWhere(
        (suggestion) => suggestion.type == PlanningSuggestionType.carryForward,
      );
      await planning.applySuggestion(suggestion, targetDay: tomorrow);
      final items = await db.select(db.dailyPlanItems).get();
      expect(items, hasLength(1));
      final targetPlan = await (db.select(
        db.dailyPlans,
      )..where((plan) => plan.id.equals(items.single.planId))).getSingle();
      expect(targetPlan.dayKey, myDayKey(tomorrow));

      expect(await undo.undo(), isTrue);
      final restored = await db.select(db.dailyPlanItems).getSingle();
      expect(restored.planId, yesterdayPlanId);

      // Re-load and remove the carry-forward item explicitly.
      final fresh = await snapshots.load(now: today);
      final freshSuggestion = PlanningEngine.build(fresh).suggestions
          .firstWhere(
            (suggestion) =>
                suggestion.type == PlanningSuggestionType.carryForward,
          );
      await planning.removeCarryForward(freshSuggestion);
      expect(await db.select(db.dailyPlanItems).get(), isEmpty);
      expect(await undo.undo(), isTrue);
      expect(await db.select(db.dailyPlanItems).get(), hasLength(1));
    },
  );

  test('importance, urgency override and window are user-controlled', () async {
    final id = await addTodo('Matrix task');
    final key = PlanningTaskKey(PlanningTaskSource.todo, id);

    await planning.setImportance(key, true);
    await planning.setUrgencyOverride(key, true);
    var task = await db.getTodoItem(id);
    expect(task!.isImportant, isTrue);
    expect(task.urgencyOverride, isTrue);

    await planning.setUrgencyOverride(key, null);
    task = await db.getTodoItem(id);
    expect(task!.urgencyOverride, isNull);

    await planning.saveUrgencyWindow(7);
    final profile = await preferences.loadProfile();
    expect(profile.urgencyWindowDays, 7);

    final snapshot = await snapshots.load(now: today);
    expect(snapshot.urgencyWindowDays, 7);
    expect(
      snapshot.tasks.firstWhere((task) => task.key == key).isImportant,
      isTrue,
    );
  });

  test(
    'weekly metrics reconcile with source rows and the selected range',
    () async {
      final completed = await addTodo('Completed');
      await db
          .into(db.todoCompletions)
          .insert(
            TodoCompletionsCompanion.insert(
              id: 'completion-1',
              todoId: completed,
              completedAt: DateTime(2026, 5, 19, 10),
            ),
          );
      final carried = await addTodo('Carried');
      final overdue = await addTodo('Overdue');
      await (db.update(db.todoItems)..where((task) => task.id.equals(overdue)))
          .write(TodoItemsCompanion(dueDate: Value(DateTime(2026, 5, 18))));
      final yesterday = DayMath.addDays(today, -1);
      final planId = SyncIds.dailyPlanId(yesterday);
      await db
          .into(db.dailyPlans)
          .insert(
            DailyPlansCompanion.insert(
              id: planId,
              dayKey: myDayKey(yesterday),
              createdAt: DateTime(2026, 5, 19),
              updatedAt: DateTime(2026, 5, 19),
            ),
          );
      await db
          .into(db.dailyPlanItems)
          .insert(
            DailyPlanItemsCompanion.insert(
              id: 'carry-item',
              planId: planId,
              todoItemId: Value(carried),
              createdAt: DateTime(2026, 5, 19),
              updatedAt: DateTime(2026, 5, 19),
            ),
          );

      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: 'f1',
              startTime: DateTime(2026, 5, 19, 9),
              durationMinutes: 60,
            ),
          );
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: 'f2',
              startTime: DateTime(2026, 5, 20, 9),
              durationMinutes: 30,
            ),
          );

      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              name: 'Read',
              createdAt: DateTime(2026, 5, 1),
            ),
          );
      for (final day in [DateTime(2026, 5, 18), DateTime(2026, 5, 19)]) {
        await db
            .into(db.habitLogs)
            .insert(
              HabitLogsCompanion.insert(
                id: 'log-${day.day}',
                habitId: 'h1',
                date: day,
              ),
            );
      }
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Launch',
              createdAt: DateTime(2026, 5, 1),
            ),
          );
      await db
          .into(db.projectMilestones)
          .insert(
            ProjectMilestonesCompanion.insert(
              id: 'm1',
              projectId: 'p1',
              title: 'Beta',
              targetDate: Value(DateTime(2026, 5, 19)),
              completedAt: Value(DateTime(2026, 5, 19, 12)),
              createdAt: DateTime(2026, 5, 1),
              updatedAt: DateTime(2026, 5, 1),
            ),
          );

      final snapshot = await snapshots.load(
        now: today,
        reviewFrom: DateTime(2026, 5, 18),
        reviewTo: DateTime(2026, 5, 20),
      );
      final review = snapshot.weeklyReview!;
      expect(review.from, DateTime(2026, 5, 18));
      expect(review.to, DateTime(2026, 5, 20));
      expect(review.completedOccurrences, 1);
      expect(review.completedDistinctTasks, 1);
      expect(review.carriedTasks, 1);
      expect(review.overdueTasks, 1);
      expect(review.focusMinutes, 90);
      expect(review.focusSessions, 2);
      expect(review.habitCompletions, 2);
      expect(review.habitPossible, 3); // one habit × three days
      expect(review.milestonesCompleted, 1);
      expect(review.milestonesDue, 1);
    },
  );

  test('a capacity snapshot follows the Phase 2 precedence rule', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: today,
        workingHours: const [ClockWindow(9 * 60, 12 * 60)],
        breaks: const [ClockWindow(10 * 60, 10 * 60 + 30)],
        busyEvents: [
          (
            start: DateTime(2026, 5, 20, 11),
            end: DateTime(2026, 5, 20, 11, 30),
          ),
        ],
        blocks: [
          BookedInterval(
            taskKey: 'todo:a',
            start: DateTime(2026, 5, 20, 9),
            end: DateTime(2026, 5, 20, 10),
          ),
        ],
        plannedMinutesByTask: const {'todo:a': 45},
      ),
    );
    expect(summary.plannedMinutes, 60);
    expect(summary.taskMinutes['todo:a'], 60);
    expect(summary.availableMinutes, 120);
  });
}
