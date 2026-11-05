import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/planning/capacity_service.dart';
import 'package:locus_planner/core/planning/saved_filter.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/calendar/data/planning_preferences_repository.dart';
import 'package:locus_planner/features/calendar/data/saved_filter_repository.dart';
import 'package:locus_planner/features/calendar/data/schedule_block_repository.dart';

String taskFilter({int priority = 0}) => jsonEncode({
  'version': 1,
  'scope': 'tasks',
  'field': 'priority',
  'op': 'gte',
  'value': priority,
});

void main() {
  late AppDatabase db;
  late UndoService undo;
  late ScheduleBlockRepository blocks;
  late SavedFilterRepository filters;
  late PlanningPreferencesRepository planning;

  final dayStart = DateTime(2026, 5, 20);
  final dayEnd = DateTime(2026, 5, 21);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    undo = UndoService();
    blocks = ScheduleBlockRepository(db, undo);
    filters = SavedFilterRepository(db, undo);
    planning = PlanningPreferencesRepository(db);
  });

  tearDown(() async {
    undo.dispose();
    await db.close();
  });

  group('schedule block repository', () {
    test('creates a block and turns it back into an undoable delete', () async {
      final todoId = await db.addTodoItem('Write the report', null);
      final block = await blocks.createBlock(
        todoItemId: todoId,
        startAt: DateTime(2026, 5, 20, 9),
        endAt: DateTime(2026, 5, 20, 10),
        blockKind: 'focus',
        note: '  quiet room  ',
      );

      expect(block.todoItemId, todoId);
      expect(block.projectTaskId, isNull);
      expect(block.blockKind, 'focus');
      expect(block.note, 'quiet room');

      final visible = await blocks.watchForRange(dayStart, dayEnd).first;
      expect(visible.single.id, block.id);

      await blocks.deleteBlock(block);
      expect(await db.select(db.taskScheduleBlocks).get(), isEmpty);
      expect(undo.hasUndo, isTrue);

      expect(await undo.undo(), isTrue);
      expect(await db.select(db.taskScheduleBlocks).get(), hasLength(1));
    });

    test('moves keep duration and resizes clamp to five minutes', () async {
      final todoId = await db.addTodoItem('Plan', null);
      final block = await blocks.createBlock(
        todoItemId: todoId,
        startAt: DateTime(2026, 5, 20, 9),
        endAt: DateTime(2026, 5, 20, 10),
      );

      await blocks.moveBlock(block: block, newStart: DateTime(2026, 5, 20, 14));
      var moved = (await db.select(db.taskScheduleBlocks).getSingle());
      expect(moved.startAt, DateTime(2026, 5, 20, 14));
      expect(moved.endAt, DateTime(2026, 5, 20, 15));

      await blocks.resizeBlock(
        block: moved,
        newEnd: DateTime(2026, 5, 20, 14, 1),
      );
      moved = await db.select(db.taskScheduleBlocks).getSingle();
      expect(moved.endAt, DateTime(2026, 5, 20, 14, 5));
    });

    test('validates targets, parents and intervals', () async {
      final todoId = await db.addTodoItem('Task', null);

      await expectLater(
        blocks.createBlock(
          startAt: DateTime(2026, 5, 20, 9),
          endAt: DateTime(2026, 5, 20, 10),
        ),
        throwsArgumentError,
      );
      await expectLater(
        blocks.createBlock(
          todoItemId: todoId,
          projectTaskId: 'task-1',
          startAt: DateTime(2026, 5, 20, 9),
          endAt: DateTime(2026, 5, 20, 10),
        ),
        throwsArgumentError,
      );
      await expectLater(
        blocks.createBlock(
          todoItemId: todoId,
          startAt: DateTime(2026, 5, 20, 9),
          endAt: DateTime(2026, 5, 20, 9, 4),
        ),
        throwsArgumentError,
      );
      await expectLater(
        blocks.createBlock(
          todoItemId: todoId,
          startAt: DateTime(2026, 5, 20, 9),
          endAt: DateTime(2026, 5, 20, 10),
          blockKind: 'meeting',
        ),
        throwsArgumentError,
      );
      await expectLater(
        blocks.createBlock(
          todoItemId: 'missing',
          startAt: DateTime(2026, 5, 20, 9),
          endAt: DateTime(2026, 5, 20, 10),
        ),
        throwsStateError,
      );
    });

    test('a project checklist task can own a block', () async {
      await db
          .into(db.projects)
          .insert(
            ProjectsCompanion.insert(
              id: 'p1',
              name: 'Launch',
              createdAt: DateTime(2026, 5, 1),
            ),
          );
      await db.addTask('p1', 'Ship the beta');
      final task = await db.select(db.tasks).getSingle();

      final block = await blocks.createBlock(
        projectTaskId: task.id,
        startAt: DateTime(2026, 5, 20, 11),
        endAt: DateTime(2026, 5, 20, 12),
      );

      expect(block.projectTaskId, task.id);
      expect(block.todoItemId, isNull);
    });

    test(
      'plannable tasks exclude block owners and include estimates',
      () async {
        final blocked = await db.addTodoItem('Blocked', null);
        final free = await db.addTodoItem('Free', null);
        await (db.update(db.todoItems)..where((t) => t.id.equals(free))).write(
          const TodoItemsCompanion(estimatedMinutes: Value(45)),
        );
        await blocks.createBlock(
          todoItemId: blocked,
          startAt: dayStart.add(const Duration(hours: 9)),
          endAt: dayStart.add(const Duration(hours: 10)),
        );

        final plannable = await blocks
            .watchPlannableTasks(dayStart, dayEnd)
            .first;
        expect(plannable.map((task) => task.title), ['Free']);
        expect(plannable.single.key, 'todo:$free');
        expect(plannable.single.estimatedMinutes, 45);
      },
    );
  });

  group('saved filter repository', () {
    test('creates, canonicalises and rejects duplicate names', () async {
      final id = await filters.create(
        scope: 'tasks',
        name: '  High priority  ',
        filterJson: jsonEncode({
          'version': 1,
          'scope': 'tasks',
          'field': 'priority',
          'op': 'gte',
          'value': 2,
          'unknown': 'dropped',
        }),
      );

      final saved = (await filters.watchForScope('tasks').first).single;
      expect(saved.id, id);
      expect(saved.name, 'High priority');
      expect(saved.filterJson, isNot(contains('unknown')));

      await expectLater(
        filters.create(
          scope: 'tasks',
          name: 'HIGH PRIORITY',
          filterJson: taskFilter(),
        ),
        throwsA(isA<SavedFilterException>()),
      );

      // The same name is allowed in another scope.
      await filters.create(
        scope: 'projects',
        name: 'High priority',
        filterJson: jsonEncode({
          'version': 1,
          'scope': 'projects',
          'field': 'name',
          'op': 'contains',
          'value': 'Launch',
        }),
      );
    });

    test('pins, reorders and undoes a delete', () async {
      final first = await filters.create(
        scope: 'tasks',
        name: 'First',
        filterJson: taskFilter(),
      );
      final second = await filters.create(
        scope: 'tasks',
        name: 'Second',
        filterJson: taskFilter(),
      );
      final third = await filters.create(
        scope: 'tasks',
        name: 'Third',
        filterJson: taskFilter(),
      );

      await filters.reorder('tasks', [third, first, second]);
      var saved = await filters.watchForScope('tasks').first;
      expect(saved.map((row) => row.name), ['Third', 'First', 'Second']);
      expect(saved.map((row) => row.position), [0, 1, 2]);

      await filters.setPinned(
        saved.firstWhere((row) => row.id == second),
        true,
      );
      saved = await filters.watchForScope('tasks').first;
      expect(saved.first.id, second);

      final removed = saved.firstWhere((row) => row.id == second);
      await filters.delete(removed);
      expect(await filters.watchForScope('tasks').first, hasLength(2));
      expect(await undo.undo(), isTrue);
      expect(await filters.watchForScope('tasks').first, hasLength(3));
    });

    test('validates names, pages and definition versions', () async {
      await expectLater(
        filters.create(scope: 'tasks', name: '   ', filterJson: taskFilter()),
        throwsA(isA<SavedFilterException>()),
      );
      await expectLater(
        filters.create(
          scope: 'tasks',
          name: 'x' * 81,
          filterJson: taskFilter(),
        ),
        throwsA(isA<SavedFilterException>()),
      );

      final id = await filters.create(
        scope: 'tasks',
        name: 'Mine',
        filterJson: taskFilter(),
      );
      final saved = (await filters.watchForScope('tasks').first).single;
      expect(saved.id, id);

      await expectLater(
        filters.updateDefinition(savedFilter: saved, definitionVersion: 2),
        throwsA(isA<SavedFilterException>()),
      );
    });

    test('compiles a stored definition', () async {
      await filters.create(
        scope: 'tasks',
        name: 'Mine',
        filterJson: taskFilter(priority: 2),
        sortJson: jsonEncode([
          {'field': 'title', 'descending': false},
        ]),
      );
      final saved = (await filters.watchForScope('tasks').first).single;
      final compiled = filters.compile(saved, now: DateTime(2026, 5, 20));

      expect(compiled.whereSql, 'priority >= ?');
      expect(compiled.variables.single.value, 2);
      expect(compiled.orderBySql, ' ORDER BY title ASC');
    });
  });

  group('planning preferences repository', () {
    test('returns defaults without writing until saved', () async {
      final profile = await planning.loadProfile();

      expect(profile.id, PlanningPreferencesRepository.defaultProfileId);
      expect(profile.defaultSlotMinutes, 30);
      expect(profile.bufferMinutes, 10);
      expect(profile.workingHours, hasLength(5));
      expect(profile.breaks, isEmpty);
      expect(await db.select(db.planningPreferences).get(), isEmpty);
      expect(await db.select(db.workingHours).get(), isEmpty);
    });

    test('saves preferences and replaces working hours and breaks', () async {
      await planning.savePreferences(
        timezoneId: ' Europe/Berlin ',
        defaultSlotMinutes: 45,
        weekStartDay: 3,
        dayStartMinute: 8 * 60 + 30,
        dayEndMinute: 18 * 60 + 30,
        bufferMinutes: 5,
      );

      await planning.replaceWorkingHours([
        const WorkingWindowDraft(
          weekday: 1,
          startMinute: 9 * 60,
          endMinute: 12 * 60,
        ),
        const WorkingWindowDraft(
          id: 'keep-me',
          weekday: 2,
          startMinute: 13 * 60,
          endMinute: 17 * 60,
          enabled: false,
        ),
      ]);
      await planning.replaceBreaks([
        const WorkingWindowDraft(
          weekday: 1,
          startMinute: 10 * 60,
          endMinute: 10 * 60 + 15,
          label: 'Coffee',
        ),
      ]);

      final profile = await planning.loadProfile();
      expect(profile.timezoneId, 'Europe/Berlin');
      expect(profile.defaultSlotMinutes, 45);
      expect(profile.weekStartDay, 3);
      expect(profile.dayStartMinute, 8 * 60 + 30);
      expect(profile.dayEndMinute, 18 * 60 + 30);
      expect(profile.bufferMinutes, 5);
      expect(profile.workingHours, hasLength(2));
      expect(profile.workingHours.first.id, isNotEmpty);
      expect(profile.workingHours.last.id, 'keep-me');
      expect(profile.workingHours.last.enabled, isFalse);
      expect(profile.breaks.single.label, 'Coffee');
    });

    test('rejects invalid preferences and windows', () async {
      await expectLater(
        planning.savePreferences(dayStartMinute: 600, dayEndMinute: 600),
        throwsArgumentError,
      );
      await expectLater(
        planning.savePreferences(bufferMinutes: -1),
        throwsArgumentError,
      );
      await expectLater(
        planning.replaceWorkingHours([
          const WorkingWindowDraft(
            weekday: 0,
            startMinute: 9 * 60,
            endMinute: 10 * 60,
          ),
        ]),
        throwsArgumentError,
      );
      await expectLater(
        planning.replaceBreaks([
          const WorkingWindowDraft(
            weekday: 1,
            startMinute: 10 * 60,
            endMinute: 10 * 60,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('builds capacity for the profile weekday', () async {
      await planning.replaceWorkingHours([
        const WorkingWindowDraft(
          weekday: 3,
          startMinute: 9 * 60,
          endMinute: 12 * 60,
        ),
      ]);
      await planning.replaceBreaks([
        const WorkingWindowDraft(
          weekday: 3,
          startMinute: 10 * 60,
          endMinute: 10 * 60 + 30,
        ),
      ]);
      final profile = (await planning.loadProfile()).copyWith(
        bufferMinutes: 15,
      );

      // 2026-05-20 is a Wednesday.
      final summary = planning.capacityFor(
        day: dayStart,
        profile: profile,
        blocks: [
          BookedInterval(
            taskKey: 'todo:a',
            start: DateTime(2026, 5, 20, 9),
            end: DateTime(2026, 5, 20, 10),
          ),
        ],
      );

      expect(summary.workingMinutes, 180);
      expect(summary.breakMinutes, 30);
      expect(summary.bufferMinutes, 15);
      expect(summary.availableMinutes, 135);
      expect(summary.plannedMinutes, 60);
      expect(summary.remainingMinutes, 75);
    });
  });
}
