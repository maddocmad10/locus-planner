import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

void main() {
  late AppDatabase desktop;
  late AppDatabase phone;

  setUp(() async {
    desktop = AppDatabase.forTesting(NativeDatabase.memory());
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    // Opening the connection runs migration and creates the device identity.
    await desktop.ensureDeviceIdentity();
    await phone.ensureDeviceIdentity();
  });

  tearDown(() async {
    await desktop.close();
    await phone.close();
  });

  Future<List<Map<String, dynamic>>> outbox(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT entity_type, entity_id, operation, payload, device_id '
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
            'deviceId': row.readNullable<String>('device_id'),
          },
        )
        .toList();
  }

  Future<void> insertTodo(AppDatabase db, String id, String title) =>
      db.customStatement(
        'INSERT INTO todo_items (id, title, completed, created_at) '
        'VALUES (?, ?, 0, 1760000000)',
        [id, title],
      );

  Future<void> renameTodo(AppDatabase db, String id, String title) =>
      db.customStatement('UPDATE todo_items SET title = ? WHERE id = ?', [
        title,
        id,
      ]);

  Future<String?> titleOf(AppDatabase db, String id) async {
    final rows = await db
        .customSelect(
          'SELECT title FROM todo_items WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('title');
  }

  Map<String, dynamic> todoChange(
    String id,
    String title, {
    int? version,
    String device = 'remote-device',
    String operation = 'upsert',
  }) => {
    'entityType': 'todo',
    'entityId': id,
    'operation': operation,
    'deviceId': device,
    'payload': {
      'id': id,
      if (operation == 'upsert') ...{
        'title': title,
        'completed': 0,
        'created_at': 1760000000,
        'due_date': null,
      },
      if (version != null) 'updated_at': version,
    },
  };

  test('local edits get a rising version carried in the payload', () async {
    await insertTodo(desktop, 't1', 'one');
    await renameTodo(desktop, 't1', 'two');
    await desktop.customStatement("DELETE FROM todo_items WHERE id = 't1'");

    final changes = await outbox(desktop);
    final versions = changes
        .map((change) => change['payload']['updated_at'] as int)
        .toList();
    expect(changes.map((change) => change['operation']), [
      'upsert',
      'upsert',
      'delete',
    ]);
    expect(versions.first, greaterThan(0));
    expect(versions[1], greaterThan(versions[0]));
    expect(versions[2], greaterThan(versions[1]));

    final stored = await desktop
        .customSelect(
          "SELECT updated_at, deleted FROM sync_row_versions "
          "WHERE entity_type = 'todo' AND entity_id = 't1'",
        )
        .getSingle();
    expect(stored.read<int>('updated_at'), versions.last);
    expect(stored.read<int>('deleted'), 1);
  });

  test('upsert and replace writes on a synced row keep versioning', () async {
    const upsert =
        'INSERT INTO todo_items (id, title, completed, created_at) '
        'VALUES (?, ?, 0, 1760000000) '
        'ON CONFLICT(id) DO UPDATE SET title = excluded.title';
    await desktop.customStatement(upsert, ['t1', 'first']);
    await desktop.customStatement(upsert, ['t1', 'second']);
    await desktop.customStatement(
      'INSERT OR REPLACE INTO todo_items (id, title, completed, created_at) '
      "VALUES ('t1', 'third', 0, 1760000000)",
    );

    final versions = (await outbox(desktop))
        .map((change) => change['payload']['updated_at'] as int)
        .toList();
    expect(versions, hasLength(3));
    expect(versions[1], greaterThan(versions[0]));
    expect(versions[2], greaterThan(versions[1]));
  });

  test('concurrent edits converge on the later edit', () async {
    await insertTodo(desktop, 'shared', 'original');
    final firstBatch = await outbox(desktop);
    await SyncChangeApplier(phone).apply(firstBatch);
    expect(await titleOf(phone, 'shared'), 'original');

    await renameTodo(desktop, 'shared', 'from desktop');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await renameTodo(phone, 'shared', 'from phone');

    // Same order as MobileSyncClient: push phone changes, then pull desktop's.
    final pushed = await outbox(phone);
    final pulled = (await outbox(desktop)).skip(firstBatch.length).toList();
    await SyncChangeApplier(desktop).apply(pushed);
    await SyncChangeApplier(phone).apply(pulled);

    expect(await titleOf(desktop, 'shared'), 'from phone');
    expect(await titleOf(phone, 'shared'), 'from phone');
  });

  test('a stale upsert does not overwrite a newer local edit', () async {
    await insertTodo(desktop, 't1', 'first');
    final stale = (await outbox(desktop)).single;
    await renameTodo(desktop, 't1', 'newer');

    final result = await SyncChangeApplier(desktop).apply([stale]);
    expect(result.skipped, 1);
    expect(result.applied, 0);
    expect(await titleOf(desktop, 't1'), 'newer');
  });

  test('replaying a change is idempotent', () async {
    final change = todoChange('t1', 'hello', version: 5000);
    final applier = SyncChangeApplier(desktop);
    expect((await applier.apply([change])).applied, 1);
    expect((await applier.apply([change])).skipped, 1);
    expect(await titleOf(desktop, 't1'), 'hello');
  });

  test('an exact version tie is won by the higher device id', () async {
    final applier = SyncChangeApplier(desktop);
    Future<void> receive(String title, String device) => applier.apply([
      todoChange('t1', title, version: 9000, device: device),
    ]);

    await receive('from b', 'b');
    await receive('from a', 'a');
    expect(await titleOf(desktop, 't1'), 'from b');
    await receive('from c', 'c');
    expect(await titleOf(desktop, 't1'), 'from c');
  });

  test('a delete tombstone beats older upserts; newer ones revive', () async {
    final applier = SyncChangeApplier(desktop);
    await applier.apply([todoChange('t1', 'x', version: 1000)]);
    await applier.apply([
      todoChange('t1', '', version: 2000, operation: 'delete'),
    ]);
    expect(await titleOf(desktop, 't1'), isNull);

    final stale = await applier.apply([todoChange('t1', 'old', version: 1500)]);
    expect(stale.skipped, 1);
    expect(await titleOf(desktop, 't1'), isNull);

    final revived = await applier.apply([
      todoChange('t1', 'new', version: 3000),
    ]);
    expect(revived.applied, 1);
    expect(await titleOf(desktop, 't1'), 'new');
  });

  test('changes from a peer without versions are still applied', () async {
    await insertTodo(desktop, 't1', 'local');
    final result = await SyncChangeApplier(
      desktop,
    ).apply([todoChange('t1', 'legacy peer')]);
    expect(result.applied, 1);
    expect(await titleOf(desktop, 't1'), 'legacy peer');
  });

  test('applying remote changes still creates no outbox echo', () async {
    await SyncChangeApplier(desktop).apply([
      todoChange('t1', 'remote', version: 4000),
    ]);
    expect(await outbox(desktop), isEmpty);
  });
}
