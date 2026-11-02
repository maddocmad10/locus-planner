import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/landing_page_provider.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/core/utils/sync_ids.dart';
import 'package:locus_planner/features/my_day/data/my_day_models.dart';
import 'package:locus_planner/features/my_day/data/my_day_repository.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/features/tasks/data/task_metadata.dart';
import 'package:locus_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late MyDayRepository repository;
  late TaskRepository tasks;
  late ProjectRepository projects;
  final day = DateTime(2026, 5, 20);

  setUp(() {
    AppClock.now = () => DateTime(2026, 5, 20, 9, 30);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final undo = UndoService();
    tasks = TaskRepository(db, undo);
    projects = ProjectRepository(db, undo);
    repository = MyDayRepository(db, tasks, projects);
  });

  tearDown(() async {
    await db.close();
    AppClock.now = DateTime.now;
  });

  Future<String> addTodo(
    String title, {
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    bool completed = false,
  }) async {
    final id = await db.addTodoItem(title, dueDate, priority: priority.value);
    if (completed) await db.toggleTodoItem(id, true);
    return id;
  }

  Future<(String, String)> addProjectTask(String title) async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'project-1',
            name: 'Work',
            createdAt: day,
          ),
        );
    await db.addTask('project-1', title);
    final row = await (db.select(
      db.tasks,
    )..where((t) => t.title.equals(title))).getSingle();
    return (row.projectId, row.id);
  }

  group('My Day repository', () {
    test('opening a day does not create a plan row', () async {
      final view = await repository.watchDay(day).first;

      expect(view.planId, isNull);
      expect(view.intention, isEmpty);
      expect(await db.select(db.dailyPlans).get(), isEmpty);
    });

    test('the first intention edit creates one plan row', () async {
      await repository.setIntention(day: day, intention: 'Ship the release');
      await repository.setIntention(day: day, intention: 'Ship the release');

      final plans = await db.select(db.dailyPlans).get();
      expect(plans, hasLength(1));
      expect(plans.single.dayKey, '2026-05-20');
      expect(plans.single.intention, 'Ship the release');
      expect(
        (await repository.watchDay(day).first).intention,
        'Ship the release',
      );
    });

    test('plan and item ids are deterministic', () async {
      final todoId = await addTodo('Deterministic task');
      await repository.addTodo(day: day, todoId: todoId);

      final plan = (await db.select(db.dailyPlans).get()).single;
      expect(plan.id, SyncIds.dailyPlanId(day));
      final item = (await db.select(db.dailyPlanItems).get()).single;
      expect(
        item.id,
        SyncIds.dailyPlanItemId(planId: plan.id, todoItemId: todoId),
      );
      expect(item.planId, plan.id);
    });

    test('personal and project tasks can be planned together', () async {
      final todoId = await addTodo('Write notes');
      final (_, projectTaskId) = await addProjectTask('Review pull request');

      await repository.addTodo(day: day, todoId: todoId);
      await repository.addProjectTask(day: day, taskId: projectTaskId);

      final view = await repository.watchDay(day).first;
      expect(view.items, hasLength(2));
      expect(
        view.items.map((item) => item.source),
        containsAll([PlannedTaskSource.todo, PlannedTaskSource.projectTask]),
      );
      expect(view.items.map((item) => item.sortOrder), [0, 1]);
      expect(view.items.last.projectName, 'Work');
    });

    test('the same task cannot be planned twice on one day', () async {
      final todoId = await addTodo('Write notes');
      await repository.addTodo(day: day, todoId: todoId);
      await repository.addTodo(day: day, todoId: todoId);

      expect((await db.select(db.dailyPlanItems).get()), hasLength(1));
    });

    test('manual ordering persists', () async {
      final first = await addTodo('First');
      final second = await addTodo('Second');
      final third = await addTodo('Third');
      for (final id in [first, second, third]) {
        await repository.addTodo(day: day, todoId: id);
      }

      final before = await repository.watchDay(day).first;
      final reversed = before.items.reversed.toList();
      await repository.reorderItems([
        for (final item in reversed) item.planItemId,
      ]);

      final after = await repository.watchDay(day).first;
      expect(after.items.map((item) => item.title), [
        'Third',
        'Second',
        'First',
      ]);
    });

    test('moving a task creates the destination plan', () async {
      final todoId = await addTodo('Write notes');
      await repository.addTodo(day: day, todoId: todoId);
      final item = (await repository.watchDay(day).first).items.single;

      await repository.moveItem(
        itemId: item.planItemId,
        targetDay: DateTime(2026, 5, 21),
      );

      expect((await repository.watchDay(day).first).items, isEmpty);
      final tomorrow = await repository.watchDay(DateTime(2026, 5, 21)).first;
      expect(tomorrow.items.single.taskId, todoId);
      expect(await db.select(db.dailyPlans).get(), hasLength(2));
      final todo = await db.getTodoItem(todoId);
      expect(todo!.dueDate, isNull);
    });

    test(
      'moving into a day that already has the task drops the duplicate',
      () async {
        final todoId = await addTodo('Write notes');
        await repository.addTodo(day: day, todoId: todoId);
        final tomorrow = DateTime(2026, 5, 21);
        await repository.addTodo(day: tomorrow, todoId: todoId);
        final todayItem = (await repository.watchDay(day).first).items.single;

        await repository.moveItem(
          itemId: todayItem.planItemId,
          targetDay: tomorrow,
        );

        expect((await repository.watchDay(day).first).items, isEmpty);
        expect((await repository.watchDay(tomorrow).first).items, hasLength(1));
      },
    );

    test('completing a planned to-do updates the original task', () async {
      final todoId = await addTodo('Write notes');
      await repository.addTodo(day: day, todoId: todoId);
      final item = (await repository.watchDay(day).first).items.single;

      await repository.setCompleted(item, true);

      final todo = await db.getTodoItem(todoId);
      expect(todo!.completed, isTrue);
      final view = await repository.watchDay(day).first;
      expect(view.items.single.completed, isTrue);
      expect(view.completedCount, 1);
    });

    test(
      'completing a planned project task updates the checklist row',
      () async {
        final (_, taskId) = await addProjectTask('Review pull request');
        await repository.addProjectTask(day: day, taskId: taskId);
        final item = (await repository.watchDay(day).first).items.single;

        await repository.setCompleted(item, true);

        final row = await (db.select(
          db.tasks,
        )..where((t) => t.id.equals(taskId))).getSingle();
        expect(row.completed, isTrue);
      },
    );

    test('due date and planned day are independent', () async {
      final due = DateTime(2026, 5, 22);
      final todoId = await addTodo('Write notes', dueDate: due);
      await repository.addTodo(day: day, todoId: todoId);

      final item = (await repository.watchDay(day).first).items.single;
      expect(item.dueDate, due);
      final todo = await db.getTodoItem(todoId);
      expect(todo!.dueDate, due);
      expect(item.sortOrder, 0);
    });

    test('deleting the original task removes its planned entry', () async {
      final todoId = await addTodo('Write notes');
      await repository.addTodo(day: day, todoId: todoId);

      await (db.delete(db.todoItems)..where((t) => t.id.equals(todoId))).go();

      expect(await db.select(db.dailyPlanItems).get(), isEmpty);
      expect((await repository.watchDay(day).first).items, isEmpty);
    });

    test(
      'suggestions cover overdue, due today, high priority and no date',
      () async {
        await addTodo('Overdue', dueDate: DateTime(2026, 5, 19));
        await addTodo('Due today', dueDate: day);
        await addTodo(
          'Important later',
          dueDate: DateTime(2026, 5, 25),
          priority: TaskPriority.high,
        );
        await addTodo('No date');
        await addTodo('Completed', completed: true);

        final planned = await addTodo('Already planned');
        await repository.addTodo(day: day, todoId: planned);

        final view = await repository.watchDay(day).first;
        final byTitle = {
          for (final suggestion in view.suggestions)
            suggestion.title: suggestion.reason,
        };
        expect(byTitle['Overdue'], SuggestedReason.overdue);
        expect(byTitle['Due today'], SuggestedReason.dueToday);
        expect(byTitle['Important later'], SuggestedReason.highPriority);
        expect(byTitle['No date'], SuggestedReason.noDate);
        expect(byTitle.containsKey('Completed'), isFalse);
        expect(byTitle.containsKey('Already planned'), isFalse);
      },
    );

    test(
      'plannable tasks mark already planned rows but keep them visible',
      () async {
        final todoId = await addTodo('Write notes');
        final (_, projectTaskId) = await addProjectTask('Review pull request');
        await repository.addTodo(day: day, todoId: todoId);

        final plannable = await repository.plannableTasks(day);
        expect(
          plannable.singleWhere((task) => task.taskId == todoId).alreadyPlanned,
          isTrue,
        );
        expect(
          plannable
              .singleWhere((task) => task.taskId == projectTaskId)
              .alreadyPlanned,
          isFalse,
        );
      },
    );

    test('a planned duration must be positive', () async {
      final todoId = await addTodo('Write notes');
      await repository.addTodo(day: day, todoId: todoId);
      final item = (await repository.watchDay(day).first).items.single;

      expect(
        () => repository.updateEstimate(
          itemId: item.planItemId,
          plannedMinutes: 0,
        ),
        throwsArgumentError,
      );

      await repository.updateEstimate(
        itemId: item.planItemId,
        plannedMinutes: 45,
      );
      final view = await repository.watchDay(day).first;
      expect(view.items.single.plannedMinutes, 45);
      expect(view.knownMinutes, 45);
    });
  });

  group('schema 12 to 13 migration', () {
    test('creates My Day tables and keeps existing data', () async {
      final dir = await Directory.systemTemp.createTemp('locus-v12-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}locus.db');

      final before = AppDatabase.forTesting(NativeDatabase(file));
      await before.ensureDeviceIdentity();
      final todoId = await before.addTodoItem(
        'Existing task',
        DateTime(2026, 5, 20),
      );
      // Simulate a schema-12 database: remove the tables, columns and triggers
      // added by later migrations, then advertise the older version.
      final beforeTriggers = await before
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .get();
      for (final row in beforeTriggers) {
        await before.customStatement(
          'DROP TRIGGER IF EXISTS ${row.read<String>('name')}',
        );
      }
      await before.customStatement('DROP TABLE todo_completions');
      await before.customStatement('DROP TABLE daily_plan_items');
      await before.customStatement('DROP TABLE daily_plans');
      await before.customStatement('ALTER TABLE events DROP COLUMN all_day');
      await before.customStatement(
        'ALTER TABLE events DROP COLUMN recurrence_end',
      );
      await before.customStatement(
        'ALTER TABLE events DROP COLUMN recurrence_exceptions',
      );
      await before.customStatement('PRAGMA user_version = 12');
      await before.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(upgraded.close);

      final tables = await upgraded
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final names = tables.map((row) => row.read<String>('name')).toSet();
      expect(names, containsAll(['daily_plans', 'daily_plan_items']));

      final version = await upgraded
          .customSelect('PRAGMA user_version')
          .getSingle();
      expect(version.data.values.single, AppDatabase.currentSchemaVersion);

      final triggers = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'trigger' "
            "AND name LIKE 'sync_outbox_daily_plan%'",
          )
          .get();
      expect(triggers, hasLength(6));

      final todo = await upgraded.getTodoItem(todoId);
      expect(todo?.title, 'Existing task');

      final indexes = await upgraded
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' "
            "AND name IN ('ux_daily_plan_todo', 'ux_daily_plan_project_task')",
          )
          .get();
      expect(indexes, hasLength(2));
    });
  });

  group('landing page preference', () {
    test('stored values are stable and unknown values fall back to Today', () {
      expect(LandingPage.fromStorage('my_day'), LandingPage.myDay);
      expect(LandingPage.fromStorage('tasks'), LandingPage.tasks);
      expect(LandingPage.fromStorage(null), LandingPage.dashboard);
      expect(LandingPage.fromStorage('future_page'), LandingPage.dashboard);
      expect(
        LandingPage.values.map((page) => page.storageValue).toSet(),
        hasLength(LandingPage.values.length),
      );
    });
  });

  group('backup round-trip', () {
    test('daily plans and items are exported and restored', () async {
      final todoId = await addTodo('Write notes');
      await repository.setIntention(day: day, intention: 'Focus');
      await repository.addTodo(day: day, todoId: todoId, plannedMinutes: 30);

      final json = await DataExportService(db).buildBackupJson();

      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      final report = await DataExportService(restored).restoreFromJson(json);
      expect(report.isClean, isTrue);

      final plans = await restored.select(restored.dailyPlans).get();
      final items = await restored.select(restored.dailyPlanItems).get();
      expect(plans.single.dayKey, '2026-05-20');
      expect(plans.single.intention, 'Focus');
      expect(items.single.todoItemId, todoId);
      expect(items.single.plannedMinutes, 30);
    });

    test('a plans-only backup is merged into existing tasks', () async {
      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      final todoId = await restored.addTodoItem('Existing task', null);

      final report = await DataExportService(restored).restoreFromJson(
        jsonEncode({
          'format_version': 2,
          'daily_plans': [
            {
              'id': 'plan-1',
              'dayKey': '2026-05-20',
              'intention': 'Focus',
              'createdAt': 1760000000000,
              'updatedAt': 1760000000000,
            },
          ],
          'daily_plan_items': [
            {
              'id': 'item-1',
              'planId': 'plan-1',
              'todoItemId': todoId,
              'projectTaskId': null,
              'sortOrder': 0,
              'plannedMinutes': 25,
              'createdAt': 1760000000000,
              'updatedAt': 1760000000000,
            },
            {
              'id': 'item-2',
              'planId': 'missing-plan',
              'todoItemId': todoId,
              'projectTaskId': null,
              'sortOrder': 1,
              'plannedMinutes': null,
              'createdAt': 1760000000000,
              'updatedAt': 1760000000000,
            },
          ],
        }),
      );

      expect(report.skippedRows, 1);
      expect(await restored.getTodoItem(todoId), isNotNull);
      final plans = await restored.select(restored.dailyPlans).get();
      final items = await restored.select(restored.dailyPlanItems).get();
      expect(plans.single.id, 'plan-1');
      expect(items.single.id, 'item-1');
      expect(items.single.plannedMinutes, 25);
    });
  });
}
