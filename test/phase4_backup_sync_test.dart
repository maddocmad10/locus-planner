import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/calendar/data/planning_preferences_repository.dart';
import 'package:locus_planner/features/planning_intelligence/data/planning_repository.dart';
import 'package:locus_planner/features/planning_intelligence/data/planning_snapshot_repository.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_engine.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_models.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late UndoService undo;
  late PlanningPreferencesRepository preferences;

  final today = DateTime(2026, 5, 20);

  setUp(() async {
    DatabaseSecurity.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('locus-phase4-');
    undo = UndoService();
    preferences = PlanningPreferencesRepository(db);
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
      urgencyWindowDays: 7,
    );
  });

  tearDown(() async {
    DatabaseSecurity.reset();
    undo.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'Eisenhower fields and urgency window survive backup and restore',
    () async {
      final todoId = await db.addTodoItem('Plan', null);
      await (db.update(db.todoItems)..where((t) => t.id.equals(todoId))).write(
        const TodoItemsCompanion(
          isImportant: Value(true),
          urgencyOverride: Value(true),
        ),
      );

      final json = await DataExportService(
        db,
        backupDirectory: dir,
      ).buildBackupJson();
      final restored = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(restored.close);
      final report = await DataExportService(restored).restoreFromJson(json);
      expect(report.skippedRows, 0);

      final todo = await restored.select(restored.todoItems).getSingle();
      expect(todo.isImportant, isTrue);
      expect(todo.urgencyOverride, isTrue);
      final profile = await restored
          .select(restored.planningPreferences)
          .getSingle();
      expect(profile.urgencyWindowDays, 7);
    },
  );

  test('sync carries the new fields and older peers get defaults', () async {
    final todoId = await db.addTodoItem('Plan', null);
    await (db.update(db.todoItems)..where((t) => t.id.equals(todoId))).write(
      const TodoItemsCompanion(
        isImportant: Value(true),
        urgencyOverride: Value(false),
      ),
    );
    final phone = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(phone.close);
    await phone.ensureDeviceIdentity();
    final state = await SyncChangeApplier.readFullState(db);
    final result = await SyncChangeApplier(phone).apply(state);
    expect(result.rejected, isEmpty);
    final synced = await phone.select(phone.todoItems).getSingle();
    expect(synced.isImportant, isTrue);
    expect(synced.urgencyOverride, isFalse);
    final profile = await phone.select(phone.planningPreferences).getSingle();
    expect(profile.urgencyWindowDays, 7);

    final oldPeer = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(oldPeer.close);
    await oldPeer.ensureDeviceIdentity();
    final oldResult = await SyncChangeApplier(oldPeer).apply([
      {
        'entityType': 'todo',
        'entityId': 'old-todo',
        'operation': 'upsert',
        'payload': {
          'id': 'old-todo',
          'title': 'Old',
          'notes': null,
          'completed': 0,
          'created_at': 1760000000,
          'start_date': null,
          'due_date': null,
          'priority': 0,
          'tags': '[]',
          'recurrence_rule': null,
          'parent_id': null,
          'project_id': null,
          'reminder_at': null,
          'estimated_minutes': null,
          'updated_at': 1000,
        },
        'deviceId': 'old-peer',
      },
    ]);
    expect(oldResult.rejected, isEmpty);
    final oldTodo = await oldPeer.select(oldPeer.todoItems).getSingle();
    expect(oldTodo.isImportant, isFalse);
    expect(oldTodo.urgencyOverride, isNull);
  });

  test('an applied suggestion syncs the moved block', () async {
    final a = await db.addTodoItem('A', null);
    final b = await db.addTodoItem('B', null);
    await (db.update(db.todoItems)..where((t) => t.id.equals(a))).write(
      const TodoItemsCompanion(priority: Value(3)),
    );
    for (final entry in [
      (id: a, start: DateTime(2026, 5, 20, 9), end: DateTime(2026, 5, 20, 12)),
      (id: b, start: DateTime(2026, 5, 20, 9), end: DateTime(2026, 5, 20, 10)),
    ]) {
      await db
          .into(db.taskScheduleBlocks)
          .insert(
            TaskScheduleBlocksCompanion.insert(
              id: 'block-${entry.id}',
              todoItemId: Value(entry.id),
              startAt: entry.start,
              endAt: entry.end,
              createdAt: DateTime(2026, 5, 19),
              updatedAt: DateTime(2026, 5, 19),
            ),
          );
    }

    final snapshots = PlanningSnapshotRepository(db, preferences);
    final suggestion = PlanningEngine.build(await snapshots.load(now: today))
        .suggestions
        .firstWhere(
          (suggestion) =>
              suggestion.type == PlanningSuggestionType.overcommittedDay,
        );
    await PlanningRepository(db, undo, preferences).applySuggestion(suggestion);

    final phone = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(phone.close);
    await phone.ensureDeviceIdentity();
    final result = await SyncChangeApplier(
      phone,
    ).apply(await SyncChangeApplier.readFullState(db));
    expect(result.rejected, isEmpty);
    final moved = await (phone.select(
      phone.taskScheduleBlocks,
    )..where((block) => block.todoItemId.equals(b))).getSingle();
    expect(moved.startAt, DateTime(2026, 5, 21, 9));
    expect(moved.endAt, DateTime(2026, 5, 21, 10));
  });
}
