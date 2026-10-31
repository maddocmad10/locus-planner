import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

/// Habit sync lets the phone be a writer, not just a viewer: the upcoming-day
/// checklist toggles a `habit_log`, which has to survive the round trip to the
/// desktop and back.
void main() {
  late AppDatabase desktop;
  late AppDatabase phone;

  setUp(() async {
    desktop = AppDatabase.forTesting(NativeDatabase.memory());
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    await desktop.ensureDeviceIdentity();
    await phone.ensureDeviceIdentity();
  });

  tearDown(() async {
    await desktop.close();
    await phone.close();
  });

  Future<void> addHabit(AppDatabase db, String id, String name) => db
      .into(db.habits)
      .insert(
        HabitsCompanion.insert(
          id: id,
          name: name,
          icon: const Value('🌱'),
          createdAt: DateTime(2026, 10, 1),
          targetPerWeek: const Value(3),
        ),
      );

  Future<void> addLog(
    AppDatabase db,
    String id,
    String habitId, {
    DateTime? day,
  }) => db
      .into(db.habitLogs)
      .insert(
        HabitLogsCompanion.insert(
          id: id,
          habitId: habitId,
          date: day ?? DateTime(2026, 10, 31),
        ),
      );

  Future<List<Map<String, dynamic>>> outbox(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT entity_type, entity_id, operation, payload '
          'FROM sync_outbox ORDER BY id',
        )
        .get();
    return rows
        .map(
          (row) => <String, dynamic>{
            'entityType': row.read<String>('entity_type'),
            'entityId': row.read<String>('entity_id'),
            'operation': row.read<String>('operation'),
            'payload': jsonDecode(row.read<String>('payload')),
          },
        )
        .toList();
  }

  test('phone habit edits are captured in the outbox', () async {
    await addHabit(phone, 'h1', 'Read');
    await addLog(phone, 'l1', 'h1');

    final changes = await outbox(phone);
    expect(changes.map((change) => change['entityType']), [
      'habit',
      'habit_log',
    ]);
    expect(changes.every((change) => change['operation'] == 'upsert'), isTrue);
    expect(changes.first['payload']['name'], 'Read');
    expect(changes.last['payload']['habit_id'], 'h1');
  });

  test('a phone snapshot applies habits before their logs', () async {
    await addHabit(phone, 'h1', 'Read');
    await addLog(phone, 'l1', 'h1');

    final state = await SyncChangeApplier.readFullState(phone);
    final habitIndex = state.indexWhere(
      (change) => change['entityType'] == 'habit',
    );
    final logIndex = state.indexWhere(
      (change) => change['entityType'] == 'habit_log',
    );
    expect(habitIndex, isNonNegative);
    expect(logIndex, greaterThan(habitIndex));

    final result = await SyncChangeApplier(desktop).apply(state);
    expect(result.applied, 2);
    expect((await desktop.select(desktop.habits).get()).single.name, 'Read');
    final log = (await desktop.select(desktop.habitLogs).get()).single;
    expect(log.habitId, 'h1');
    expect(log.completed, isTrue);
  });

  test('a habit log whose parent is missing is skipped, not fatal', () async {
    await addHabit(phone, 'h1', 'Read');
    final state = await SyncChangeApplier.readFullState(phone);
    final log = state
        .where((change) => change['entityType'] == 'habit_log')
        .toList();
    // No log exists yet, so build one for a parent the desktop does not have.
    log.add({
      'entityType': 'habit_log',
      'entityId': 'orphan',
      'operation': 'upsert',
      'deviceId': 'phone',
      'payload': {
        'id': 'orphan',
        'habit_id': 'missing',
        'date': DateTime(2026, 10, 31).millisecondsSinceEpoch,
        'completed': 1,
        'updated_at': 10,
      },
    });

    final result = await SyncChangeApplier(desktop).apply(log);
    expect(result.applied, 0);
    expect(result.skipped, 1);
    expect(await desktop.select(desktop.habitLogs).get(), isEmpty);
  });

  test('deleting a habit removes its logs on both devices', () async {
    await addHabit(phone, 'h1', 'Read');
    await addLog(phone, 'l1', 'h1');
    await SyncChangeApplier(
      desktop,
    ).apply(await SyncChangeApplier.readFullState(phone));
    expect(await desktop.select(desktop.habitLogs).get(), hasLength(1));

    await (phone.delete(phone.habits)..where((h) => h.id.equals('h1'))).go();
    expect(await phone.select(phone.habitLogs).get(), isEmpty);

    final deletes = (await outbox(
      phone,
    )).where((change) => change['operation'] == 'delete').toList();
    await SyncChangeApplier(desktop).apply(deletes);

    expect(await desktop.select(desktop.habits).get(), isEmpty);
    expect(await desktop.select(desktop.habitLogs).get(), isEmpty);
  });

  test('replaying a habit change is idempotent', () async {
    await addHabit(phone, 'h1', 'Read');
    final change = (await outbox(phone)).single;

    final applier = SyncChangeApplier(desktop);
    expect((await applier.apply([change])).applied, 1);
    expect((await applier.apply([change])).skipped, 1);
    expect(await desktop.select(desktop.habits).get(), hasLength(1));
  });
}
