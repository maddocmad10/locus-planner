import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

void main() {
  group('schema 13 to 16 migration', () {
    test('rotates the epoch and keeps every row and trigger', () async {
      final dir = await Directory.systemTemp.createTemp('locus-v13-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}locus.db');

      final before = AppDatabase.forTesting(NativeDatabase(file));
      await before.ensureDeviceIdentity();
      final oldEpoch = await before.ensureSyncEpoch();
      await before
          .into(before.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              name: 'Read',
              createdAt: DateTime(2026, 5, 1),
            ),
          );
      await before
          .into(before.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: 'log-1',
              habitId: 'h1',
              date: DateTime(2026, 5, 20),
            ),
          );
      await before.addTodoItem('Plan the day', DateTime(2026, 5, 20));
      final todo = (await before.select(before.todoItems).get()).single;
      await before
          .into(before.dailyPlans)
          .insert(
            DailyPlansCompanion.insert(
              id: 'plan-1',
              dayKey: '2026-05-20',
              createdAt: DateTime(2026, 5, 20),
              updatedAt: DateTime(2026, 5, 20),
            ),
          );
      await before
          .into(before.dailyPlanItems)
          .insert(
            DailyPlanItemsCompanion.insert(
              id: 'item-1',
              planId: 'plan-1',
              todoItemId: Value(todo.id),
              createdAt: DateTime(2026, 5, 20),
              updatedAt: DateTime(2026, 5, 20),
            ),
          );
      await before
          .into(before.events)
          .insert(
            EventsCompanion.insert(
              id: 'event-1',
              title: 'Standup',
              startTime: DateTime(2026, 5, 20, 9),
              allDay: const Value(true),
              recurrenceEnd: Value(DateTime(2026, 6, 20, 9)),
              recurrenceExceptions: const Value('["2026-05-21"]'),
            ),
          );
      final logVersion = await _versionOf(before, 'habit_log', 'log-1');
      final versionCount = await _versionCount(before);

      // Simulate the schema-13 shape: remove the columns and table added by
      // migrations 15 and 16, drop the triggers, and reset the version.
      final triggers = await before
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .get();
      for (final row in triggers) {
        await before.customStatement(
          'DROP TRIGGER IF EXISTS ${row.read<String>('name')}',
        );
      }
      await before.customStatement('DROP TABLE todo_completions');
      await before.customStatement('ALTER TABLE events DROP COLUMN all_day');
      await before.customStatement(
        'ALTER TABLE events DROP COLUMN recurrence_end',
      );
      await before.customStatement(
        'ALTER TABLE events DROP COLUMN recurrence_exceptions',
      );
      // Simulate the schema-13 shape for the Phase 2 additions too: they were
      // introduced by migration 17, so they must not already exist here.
      await before.customStatement('DROP TABLE IF EXISTS task_schedule_blocks');
      await before.customStatement('DROP TABLE IF EXISTS saved_filters');
      await before.customStatement('DROP TABLE IF EXISTS planning_preferences');
      await before.customStatement('DROP TABLE IF EXISTS working_hours');
      await before.customStatement('DROP TABLE IF EXISTS working_breaks');
      await before.customStatement(
        'ALTER TABLE todo_items DROP COLUMN estimated_minutes',
      );
      await before.customStatement('PRAGMA user_version = 13');
      await before.close();

      final after = AppDatabase.forTesting(NativeDatabase(file));
      addTearDown(after.close);
      final version =
          (await after.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version');
      expect(version, AppDatabase.currentSchemaVersion);
      expect(version, 17);
      expect(await after.ensureSyncEpoch(), isNot(oldEpoch));

      // Existing rows survive an upgrade that only adds tables and columns.
      expect((await after.select(after.habits).get()).single.id, 'h1');
      expect((await after.select(after.habitLogs).get()).single.id, 'log-1');
      expect((await after.select(after.dailyPlans).get()).single.id, 'plan-1');
      expect(
        (await after.select(after.dailyPlanItems).get()).single.id,
        'item-1',
      );
      expect((await after.select(after.todoItems).get()).single.id, todo.id);
      final event = (await after.select(after.events).get()).single;
      // The v13 row had no values for these columns, so migration 15 fills the
      // documented defaults.
      expect(event.allDay, isFalse);
      expect(event.recurrenceEnd, isNull);
      expect(event.recurrenceExceptions, '[]');

      // Versions are not rotated, so a stale peer still resolves correctly.
      expect(await _versionOf(after, 'habit_log', 'log-1'), logVersion);
      expect(await _versionCount(after), versionCount);

      final eventColumns = await after
          .customSelect('PRAGMA table_info(events)')
          .get();
      expect(
        eventColumns.map((row) => row.read<String>('name')),
        containsAll(['all_day', 'recurrence_end', 'recurrence_exceptions']),
      );
      final completionColumns = await after
          .customSelect('PRAGMA table_info(todo_completions)')
          .get();
      expect(
        completionColumns.map((row) => row.read<String>('name')),
        containsAll(['id', 'todo_id', 'occurrence_due', 'completed_at']),
      );

      final triggersAfter = await after
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
          .get();
      final names = triggersAfter
          .map((row) => row.read<String>('name'))
          .toSet();
      expect(
        names,
        containsAll([
          'sync_outbox_habit_logs_insert',
          'sync_outbox_habit_logs_update',
          'sync_outbox_habit_logs_delete',
          'sync_outbox_daily_plans_insert',
          'sync_outbox_daily_plan_items_insert',
          'sync_outbox_todo_completions_insert',
          'sync_outbox_events_update',
        ]),
      );
    });
  });

  group('event recurrence columns', () {
    test('survive a backup round trip', () async {
      final source = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(source.close);
      await source
          .into(source.events)
          .insert(
            EventsCompanion.insert(
              id: 'event-1',
              title: 'Conference',
              startTime: DateTime(2026, 5, 20, 9),
              endTime: Value(DateTime(2026, 5, 20, 17)),
              allDay: const Value(true),
              recurrenceEnd: Value(DateTime(2026, 5, 22, 9)),
              recurrenceExceptions: const Value('["2026-05-21"]'),
            ),
          );

      final json = await DataExportService(source).buildBackupJson();

      final target = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(target.close);
      final report = await DataExportService(target).restoreFromJson(json);
      expect(report.isClean, isTrue);
      final event = (await target.select(target.events).get()).single;
      expect(event.allDay, isTrue);
      expect(event.recurrenceEnd, DateTime(2026, 5, 22, 9));
      expect(event.recurrenceExceptions, '["2026-05-21"]');
    });
  });

  group('deterministic id lint', () {
    test('habit logs and My Day rows never use random ids', () {
      final habitSource = File(
        'lib/features/habits/data/habit_repository.dart',
      ).readAsStringSync();
      final toggleBody = habitSource.substring(
        habitSource.indexOf('Future<void> toggleDay'),
      );
      expect(toggleBody, contains('SyncIds.habitLogId'));
      expect(toggleBody, isNot(contains('v4()')));

      final myDaySource = File(
        'lib/features/my_day/data/my_day_repository.dart',
      ).readAsStringSync();
      expect(myDaySource, contains('SyncIds.dailyPlanId(day)'));
      expect(myDaySource, contains('SyncIds.dailyPlanItemId('));
      expect(myDaySource, isNot(contains('Uuid()')));
    });
  });

  group('todo completion sync', () {
    test('round-trips after its parent to-do', () async {
      final desktop = AppDatabase.forTesting(NativeDatabase.memory());
      final phone = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(desktop.close);
      addTearDown(phone.close);
      await desktop.ensureDeviceIdentity();
      await phone.ensureDeviceIdentity();

      final todoId = await desktop.addTodoItem(
        'Water plants',
        DateTime(2026, 5, 20, 9),
        recurrenceRule: 'weekly',
      );
      await desktop.addTodoCompletion(
        todoId: todoId,
        occurrenceDue: DateTime(2026, 5, 20, 9),
        completedAt: DateTime(2026, 5, 20, 10),
      );

      final state = await SyncChangeApplier.readFullState(desktop);
      expect(
        state.indexWhere((change) => change['entityType'] == 'todo'),
        lessThan(
          state.indexWhere(
            (change) => change['entityType'] == 'todo_completion',
          ),
        ),
      );
      final result = await SyncChangeApplier(phone).apply(state);
      expect(result.rejected, isEmpty);
      final completion =
          (await phone.select(phone.todoCompletions).get()).single;
      expect(completion.todoId, todoId);
      expect(completion.occurrenceDue, DateTime(2026, 5, 20, 9));
      expect(completion.completedAt, DateTime(2026, 5, 20, 10));
    });

    test('a completion for a missing to-do is skipped, not fatal', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final result = await SyncChangeApplier(db).apply([
        {
          'entityType': 'todo_completion',
          'entityId': 'completion-1',
          'operation': 'upsert',
          'payload': {
            'id': 'completion-1',
            'todo_id': 'missing',
            'occurrence_due': null,
            'completed_at': 1760000000,
            'updated_at': 5000,
          },
          'deviceId': 'remote-device',
        },
      ]);
      expect(result.rejected, isEmpty);
      expect(result.skipped, 1);
      expect(await db.select(db.todoCompletions).get(), isEmpty);
    });
  });
}

Future<int> _versionOf(AppDatabase db, String type, String id) async {
  final rows = await db
      .customSelect(
        'SELECT updated_at FROM sync_row_versions '
        'WHERE entity_type = ? AND entity_id = ?',
        variables: [Variable.withString(type), Variable.withString(id)],
      )
      .get();
  return rows.isEmpty ? 0 : rows.first.read<int>('updated_at');
}

Future<int> _versionCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS count FROM sync_row_versions')
      .getSingle();
  return row.read<int>('count');
}
