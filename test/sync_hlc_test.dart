import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

Future<AppDatabase> _db(String device) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.setSetting(AppDatabase.syncDeviceIdSettingKey, device);
  return db;
}

Future<Map<String, dynamic>> _lastPayload(AppDatabase db) async {
  final row = await db
      .customSelect(
        'SELECT payload, device_id FROM sync_outbox ORDER BY id DESC LIMIT 1',
      )
      .getSingle();
  return {
    'payload': jsonDecode(row.read<String>('payload')) as Map<String, dynamic>,
    'deviceId': row.readNullable<String>('device_id'),
  };
}

Future<void> _apply(AppDatabase target, Map<String, dynamic> change) async {
  await SyncChangeApplier(target).apply([
    {
      'entityType': 'todo',
      'entityId': 't1',
      'operation': 'upsert',
      'payload': change['payload'],
      'deviceId': change['deviceId'],
    },
  ]);
}

void main() {
  test('different fields edited on two devices both survive', () async {
    final a = await _db('device-a');
    final b = await _db('device-b');
    addTearDown(a.close);
    addTearDown(b.close);

    for (final db in [a, b]) {
      await db
          .into(db.todoItems)
          .insert(
            TodoItemsCompanion.insert(
              id: 't1',
              title: 'Original',
              createdAt: DateTime.utc(2026, 11, 19),
              dueDate: Value(DateTime.utc(2026, 11, 20)),
            ),
          );
      await db.customStatement('DELETE FROM sync_outbox');
    }

    await (a.update(a.todoItems)..where((t) => t.id.equals('t1'))).write(
      const TodoItemsCompanion(title: Value('Title from A')),
    );
    final fromA = await _lastPayload(a);

    await (b.update(b.todoItems)..where((t) => t.id.equals('t1'))).write(
      TodoItemsCompanion(dueDate: Value(DateTime.utc(2026, 12, 1))),
    );
    final fromB = await _lastPayload(b);

    final payloadA = fromA['payload'] as Map<String, dynamic>;
    expect(payloadA['fv'], isA<Map>());
    expect((payloadA['fv'] as Map).containsKey('title'), isTrue);

    await _apply(b, fromA);
    await _apply(a, fromB);

    final rowA = await (a.select(
      a.todoItems,
    )..where((t) => t.id.equals('t1'))).getSingle();
    final rowB = await (b.select(
      b.todoItems,
    )..where((t) => t.id.equals('t1'))).getSingle();
    expect(rowA.title, 'Title from A');
    expect(rowB.title, 'Title from A');
    expect(rowA.dueDate?.toUtc(), DateTime.utc(2026, 12, 1));
    expect(rowB.dueDate?.toUtc(), DateTime.utc(2026, 12, 1));
  });

  test('a far-future incoming version is clamped', () async {
    final db = await _db('device-a');
    addTearDown(db.close);
    await db
        .into(db.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: 't1',
            title: 'Original',
            createdAt: DateTime.utc(2026, 11, 19),
          ),
        );
    await db.customStatement('DELETE FROM sync_outbox');

    final now = DateTime.now().millisecondsSinceEpoch;
    await SyncChangeApplier(db).apply([
      {
        'entityType': 'todo',
        'entityId': 't1',
        'operation': 'upsert',
        'payload': <String, dynamic>{
          'id': 't1',
          'title': 'From 2030',
          'notes': null,
          'notes_format': 'plain',
          'completed': 0,
          'created_at': DateTime.utc(2026, 11, 19).millisecondsSinceEpoch,
          'start_date': null,
          'due_date': null,
          'priority': 0,
          'tags': '[]',
          'recurrence_rule': null,
          'parent_id': null,
          'project_id': null,
          'reminder_at': null,
          'estimated_minutes': null,
          'is_important': 0,
          'urgency_override': null,
          'updated_at': DateTime.utc(2030, 1, 1).millisecondsSinceEpoch,
          'hlc_counter': 0,
        },
        'deviceId': 'future',
      },
    ]);

    final version = await db
        .customSelect(
          'SELECT updated_at FROM sync_row_versions '
          "WHERE entity_type = 'todo' AND entity_id = 't1'",
        )
        .getSingle();
    expect(
      version.read<int>('updated_at'),
      lessThanOrEqualTo(now + 11 * 60 * 1000),
    );
  });
}
