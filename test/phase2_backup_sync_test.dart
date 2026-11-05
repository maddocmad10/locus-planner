import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() {
    DatabaseSecurity.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('locus-phase2-backup-');
  });

  tearDown(() async {
    DatabaseSecurity.reset();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> seed() async {
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
    final projectTask = await db.select(db.tasks).getSingle();

    final todoId = await db.addTodoItem('Write the report', null);
    await (db.update(db.todoItems)..where((t) => t.id.equals(todoId))).write(
      const TodoItemsCompanion(estimatedMinutes: Value(75)),
    );
    await db
        .into(db.taskScheduleBlocks)
        .insert(
          TaskScheduleBlocksCompanion.insert(
            id: 'block-1',
            todoItemId: Value(todoId),
            startAt: DateTime(2026, 5, 20, 9),
            endAt: DateTime(2026, 5, 20, 10),
            blockKind: const Value('focus'),
            note: const Value('quiet room'),
            createdAt: DateTime(2026, 5, 20, 8),
            updatedAt: DateTime(2026, 5, 20, 8),
          ),
        );
    await db
        .into(db.taskScheduleBlocks)
        .insert(
          TaskScheduleBlocksCompanion.insert(
            id: 'block-2',
            projectTaskId: Value(projectTask.id),
            startAt: DateTime(2026, 5, 20, 11),
            endAt: DateTime(2026, 5, 20, 12),
            createdAt: DateTime(2026, 5, 20, 8),
            updatedAt: DateTime(2026, 5, 20, 8),
          ),
        );
    await db
        .into(db.savedFilters)
        .insert(
          SavedFiltersCompanion.insert(
            id: 'filter-1',
            name: 'High priority',
            entityScope: 'tasks',
            filterJson:
                '{"version":1,"scope":"tasks","field":"priority","op":"gte","value":2}',
            sortJson: const Value('[{"field":"dueDate","descending":false}]'),
            isPinned: const Value(true),
            position: const Value(2),
            createdAt: DateTime(2026, 5, 1),
            updatedAt: DateTime(2026, 5, 1),
          ),
        );
    await db
        .into(db.planningPreferences)
        .insert(
          PlanningPreferencesCompanion.insert(
            id: 'profile-1',
            timezoneId: const Value('Europe/Berlin'),
            defaultSlotMinutes: const Value(45),
            weekStartDay: const Value(3),
            dayStartMinute: const Value(510),
            dayEndMinute: const Value(1110),
            bufferMinutes: const Value(5),
            createdAt: DateTime(2026, 5, 1),
            updatedAt: DateTime(2026, 5, 1),
          ),
        );
    await db
        .into(db.workingHours)
        .insert(
          WorkingHoursCompanion.insert(
            id: 'hours-1',
            weekday: 1,
            startMinute: 540,
            endMinute: 720,
            createdAt: DateTime(2026, 5, 1),
            updatedAt: DateTime(2026, 5, 1),
          ),
        );
    await db
        .into(db.workingBreaks)
        .insert(
          WorkingBreaksCompanion.insert(
            id: 'break-1',
            weekday: 1,
            startMinute: 600,
            endMinute: 615,
            label: const Value('Coffee'),
            createdAt: DateTime(2026, 5, 1),
            updatedAt: DateTime(2026, 5, 1),
          ),
        );
  }

  test('backup v3 exports and restores every Phase 2 section', () async {
    await seed();
    final json = await DataExportService(
      db,
      backupDirectory: dir,
    ).buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    for (final section in const [
      'task_schedule_blocks',
      'saved_filters',
      'planning_preferences',
      'working_hours',
      'working_breaks',
    ]) {
      expect(decoded[section], isA<List<dynamic>>(), reason: section);
      expect(
        (decoded['tables'] as Map<String, dynamic>).keys,
        contains(section),
      );
    }
    final todoRows = decoded['todo_items'] as List<dynamic>;
    expect((todoRows.single as Map<String, dynamic>)['estimatedMinutes'], 75);

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final report = await DataExportService(restored).restoreFromJson(json);

    expect(report.skippedRows, 0);
    final restoredTodo = await restored.select(restored.todoItems).getSingle();
    expect(restoredTodo.estimatedMinutes, 75);

    final restoredBlocks = await restored
        .select(restored.taskScheduleBlocks)
        .get();
    expect(restoredBlocks, hasLength(2));
    final focusBlock = restoredBlocks.firstWhere((b) => b.id == 'block-1');
    expect(focusBlock.startAt, DateTime(2026, 5, 20, 9));
    expect(focusBlock.endAt, DateTime(2026, 5, 20, 10));
    expect(focusBlock.blockKind, 'focus');
    expect(focusBlock.note, 'quiet room');

    final savedFilter = await restored
        .select(restored.savedFilters)
        .getSingle();
    expect(savedFilter.name, 'High priority');
    expect(savedFilter.isPinned, isTrue);
    expect(savedFilter.position, 2);

    final profile = await restored
        .select(restored.planningPreferences)
        .getSingle();
    expect(profile.timezoneId, 'Europe/Berlin');
    expect(profile.defaultSlotMinutes, 45);
    expect(profile.bufferMinutes, 5);

    final hours = await restored.select(restored.workingHours).getSingle();
    expect(hours.weekday, 1);
    expect(hours.startMinute, 540);
    final breaks = await restored.select(restored.workingBreaks).getSingle();
    expect(breaks.label, 'Coffee');
  });

  test('an old backup without Phase 2 sections still restores', () async {
    await db.addTodoItem('Legacy', DateTime(2026, 5, 20));
    final json = await DataExportService(
      db,
      backupDirectory: dir,
    ).buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final manifest = decoded['tables'] as Map<String, dynamic>;
    for (final section in const [
      'task_schedule_blocks',
      'saved_filters',
      'planning_preferences',
      'working_hours',
      'working_breaks',
    ]) {
      decoded.remove(section);
      manifest.remove(section);
    }
    // The payload checksum covered the removed sections, so the older
    // document has no payload checksum at all.
    decoded.remove('payload_sha256');

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final report = await DataExportService(
      restored,
    ).restoreFromJson(jsonEncode(decoded));

    expect(report.skippedRows, 0);
    expect(await restored.select(restored.todoItems).get(), hasLength(1));
    expect(await restored.select(restored.taskScheduleBlocks).get(), isEmpty);
  });

  test('sync outbox captures new entities and cascades block deletes', () async {
    await seed();
    final outbox = await db
        .customSelect(
          'SELECT entity_type, operation FROM sync_outbox '
          'WHERE operation = ?',
          variables: [Variable.withString('upsert')],
        )
        .get();
    final types = outbox.map((row) => row.read<String>('entity_type')).toSet();
    expect(
      types,
      containsAll([
        'task_schedule_block',
        'saved_filter',
        'planning_preference',
        'working_hours',
        'working_break',
      ]),
    );

    await db.customStatement(
      "DELETE FROM todo_items WHERE id = "
      "(SELECT todo_item_id FROM task_schedule_blocks WHERE id = 'block-1')",
    );
    final tombstones = await db
        .customSelect(
          'SELECT entity_type, entity_id FROM sync_outbox WHERE operation = ?',
          variables: [Variable.withString('delete')],
        )
        .get();
    expect(
      tombstones.any(
        (row) =>
            row.read<String>('entity_type') == 'task_schedule_block' &&
            row.read<String>('entity_id') == 'block-1',
      ),
      isTrue,
    );
  });

  test('full state syncs Phase 2 rows and keeps business timestamps', () async {
    await seed();
    final phone = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(phone.close);
    await phone.ensureDeviceIdentity();

    final state = await SyncChangeApplier.readFullState(db);
    final blockChange = state.firstWhere(
      (change) =>
          change['entityType'] == 'task_schedule_block' &&
          change['entityId'] == 'block-1',
    );
    final payload = blockChange['payload'] as Map<String, dynamic>;
    expect(payload['sync_updated_at'], isA<int>());
    expect(payload['sync_updated_at'], greaterThan(0));
    expect(
      payload['updated_at'],
      DateTime(2026, 5, 20, 8).millisecondsSinceEpoch ~/ 1000,
    );

    final result = await SyncChangeApplier(phone).apply(state);
    expect(result.rejected, isEmpty);

    final phoneTodos = await phone.select(phone.todoItems).get();
    expect(phoneTodos.single.estimatedMinutes, 75);
    final phoneBlocks = await phone.select(phone.taskScheduleBlocks).get();
    expect(phoneBlocks, hasLength(2));
    final phoneBlock = phoneBlocks.firstWhere((b) => b.id == 'block-1');
    expect(phoneBlock.updatedAt, DateTime(2026, 5, 20, 8));
    expect(phoneBlock.blockKind, 'focus');
    expect(await phone.select(phone.savedFilters).get(), hasLength(1));
    expect(await phone.select(phone.planningPreferences).get(), hasLength(1));
    expect(await phone.select(phone.workingHours).get(), hasLength(1));
    expect(await phone.select(phone.workingBreaks).get(), hasLength(1));
  });

  test(
    'deleting a todo removes its blocks and tombstones the snapshot',
    () async {
      await seed();
      final phone = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(phone.close);
      await phone.ensureDeviceIdentity();
      await SyncChangeApplier(
        phone,
      ).apply(await SyncChangeApplier.readFullState(db));
      expect(await phone.select(phone.taskScheduleBlocks).get(), hasLength(2));

      await db.customStatement(
        "DELETE FROM todo_items WHERE id = "
        "(SELECT todo_item_id FROM task_schedule_blocks WHERE id = 'block-1')",
      );
      final state = await SyncChangeApplier.readFullState(db);
      expect(
        state.any(
          (change) =>
              change['entityType'] == 'task_schedule_block' &&
              change['entityId'] == 'block-1' &&
              change['operation'] == 'delete',
        ),
        isTrue,
      );

      await SyncChangeApplier(phone).apply(state);
      final remaining = await phone.select(phone.taskScheduleBlocks).get();
      expect(remaining.map((b) => b.id), ['block-2']);
    },
  );

  test('an older peer skips an unknown future entity type', () async {
    final result = await SyncChangeApplier(db).apply([
      {
        'entityType': 'future_planning_entity',
        'entityId': 'x1',
        'operation': 'upsert',
        'payload': {'id': 'x1'},
        'deviceId': 'future-device',
      },
    ]);

    expect(result.applied, 0);
    expect(result.skipped, 1);
    expect(result.rejected, isEmpty);
  });
}
