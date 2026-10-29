import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_outbox_pruner.dart';
import 'package:locus_planner/core/utils/app_clock.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  Future<void> addTodo(String id) => database
      .into(database.todoItems)
      .insert(
        TodoItemsCompanion.insert(
          id: id,
          title: id,
          createdAt: DateTime.utc(2026, 10, 22, 8),
        ),
      );

  Future<int> outboxCount() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
        .getSingle();
    return row.read<int>('n');
  }

  Future<void> pairClient({int desktopCursor = 0}) => database.setSetting(
    AppDatabase.syncServerPairedClientsSettingKey,
    jsonEncode([
      {
        'deviceId': 'phone',
        'name': 'Phone',
        'pairedAt': '2026-10-22T08:00:00Z',
        'tokenHash': 'hash',
        'cursors': {'desktop': desktopCursor},
      },
    ]),
  );

  test('pruning clears the outbox before LAN sync is ever started', () async {
    await addTodo('one');
    await addTodo('two');
    expect(await outboxCount(), 2);

    await SyncOutboxPruner(database).prune();

    expect(await outboxCount(), 0);
    expect(await database.outboxPrunedThrough(), 2);
    // The rows themselves are user data and are untouched.
    final todos = await database
        .customSelect('SELECT COUNT(*) AS n FROM todo_items')
        .getSingle();
    expect(todos.read<int>('n'), 2);
  });

  test('rows a paired phone has not acknowledged are kept', () async {
    await pairClient();
    await addTodo('pending');

    await SyncOutboxPruner(database).prune();

    expect(await outboxCount(), 1);
  });

  test('rows every paired phone acknowledged are deleted', () async {
    await addTodo('first');
    await addTodo('second');
    await pairClient(desktopCursor: 1);

    await SyncOutboxPruner(database).prune();

    expect(await outboxCount(), 1);
    expect(await database.outboxPrunedThrough(), 1);
  });

  test('an unacknowledged row older than retention is dropped', () async {
    await pairClient();
    final old = AppClock.now()
        .subtract(const Duration(days: 61))
        .millisecondsSinceEpoch;
    await database.customStatement(
      'INSERT INTO sync_outbox '
      '(entity_type, entity_id, operation, payload, device_id, created_at) '
      'VALUES (?, ?, ?, ?, NULL, ?)',
      ['todo', 'ancient', 'upsert', '{}', old],
    );
    await addTodo('recent');
    expect(await outboxCount(), 2);

    await SyncOutboxPruner(database).prune();

    expect(await outboxCount(), 1);
    expect(await database.outboxPrunedThrough(), 1);
  });
}
