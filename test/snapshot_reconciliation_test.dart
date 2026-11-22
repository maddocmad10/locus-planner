import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/snapshot_reconciliation_service.dart';

void main() {
  late AppDatabase db;
  late SnapshotReconciliationService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SnapshotReconciliationService(db);
  });
  tearDown(() => db.close());

  Future<void> reviewItem({
    required String changeId,
    required String type,
    required String id,
    required String payloadJson,
  }) async {
    await db.customStatement(
      'INSERT OR IGNORE INTO snapshot_session '
      '(snapshot_id, peer_id, epoch, phase, created_at, updated_at) '
      "VALUES ('s1', 'desktop', 'e1', 'upload', 1, 1)",
    );
    await db.customStatement(
      'INSERT INTO snapshot_item '
      '(snapshot_id, change_id, ordinal, payload_json, disposition, reason, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        's1',
        changeId,
        int.parse(changeId.replaceAll(RegExp('[^0-9]'), '')),
        payloadJson,
        'review',
        'phone_only_after_reset',
        1,
      ],
    );
  }

  test('recovering a row allocates a fresh id and keeps references', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Project',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    await db.addTodoItem('Old task', null, id: 't1', projectId: 'p1');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 't1',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 't1',
        'operation': 'upsert',
        'payload': {
          'id': 't1',
          'title': 'Old task',
          'project_id': 'p1',
          'parent_id': null,
        },
      }),
    );
    expect(await service.reviewCount(), 1);

    final result = await service.resolve({'phone/1': 'recover'});
    expect(result.recovered, 1);
    expect(result.remaining, 0);
    final rows = await db.select(db.todoItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, isNot('t1'));
    expect(rows.single.projectId, 'p1');
    final item = await db
        .customSelect(
          "SELECT * FROM snapshot_item WHERE disposition = 'pending'",
        )
        .getSingle();
    final payload = jsonDecode(item.read<String>('payload_json'));
    expect(payload['entityId'], rows.single.id);
    expect(payload['payload']['id'], rows.single.id);

    final outbox = await db
        .customSelect(
          "SELECT entity_id, payload FROM sync_outbox WHERE entity_type = 'todo'",
        )
        .getSingle();
    expect(outbox.read<String>('entity_id'), rows.single.id);
    final outboxPayload = jsonDecode(outbox.read<String>('payload'));
    expect(outboxPayload['id'], rows.single.id);
    expect(outboxPayload['project_id'], 'p1');
  });

  test('recovering a parent includes referenced children', () async {
    await db.addTodoItem('Parent', null, id: 'parent');
    await db.addTodoItem('Child', null, id: 'child', parentId: 'parent');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 'parent',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'parent',
        'operation': 'upsert',
        'payload': {'id': 'parent', 'title': 'Parent', 'parent_id': null},
      }),
    );
    await reviewItem(
      changeId: 'phone/2',
      type: 'todo',
      id: 'child',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'child',
        'operation': 'upsert',
        'payload': {'id': 'child', 'title': 'Child', 'parent_id': 'parent'},
      }),
    );

    final result = await service.resolve({
      'phone/1': 'recover',
      'phone/2': 'leave',
    });
    expect(result.recovered, 2);
    final rows = await db.select(db.todoItems).get();
    final parent = rows.singleWhere((row) => row.title == 'Parent');
    final child = rows.singleWhere((row) => row.title == 'Child');
    expect(parent.id, isNot('parent'));
    expect(child.id, isNot('child'));
    expect(child.parentId, parent.id);
  });

  test('keeping the desktop deletion removes the phone-only row', () async {
    await db.addTodoItem('Delete me', null, id: 't1');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 't1',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 't1',
        'operation': 'upsert',
        'payload': {'id': 't1', 'title': 'Delete me'},
      }),
    );
    final result = await service.resolve({'phone/1': 'keep'});
    expect(result.kept, 1);
    expect(await db.getTodoItem('t1'), isNull);
    expect(await service.reviewCount(), 0);
    final outbox = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM sync_outbox "
          "WHERE entity_type = 'todo' AND entity_id = 't1'",
        )
        .getSingle();
    expect(outbox.read<int>('n'), 0);
  });

  test('keeping a parent also keeps its undecided children', () async {
    await db.addTodoItem('Parent', null, id: 'parent');
    await db.addTodoItem('Child', null, id: 'child', parentId: 'parent');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 'parent',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'parent',
        'operation': 'upsert',
        'payload': {'id': 'parent', 'title': 'Parent', 'parent_id': null},
      }),
    );
    await reviewItem(
      changeId: 'phone/2',
      type: 'todo',
      id: 'child',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'child',
        'operation': 'upsert',
        'payload': {'id': 'child', 'title': 'Child', 'parent_id': 'parent'},
      }),
    );

    final result = await service.resolve({'phone/1': 'keep'});
    expect(result.kept, 2);
    expect(result.recovered, 0);
    expect(result.remaining, 0);
    expect(await db.select(db.todoItems).get(), isEmpty);
  });

  test('a recovered child survives a kept parent by detaching', () async {
    await db.addTodoItem('Parent', null, id: 'parent');
    await db.addTodoItem('Child', null, id: 'child', parentId: 'parent');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 'parent',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'parent',
        'operation': 'upsert',
        'payload': {'id': 'parent', 'title': 'Parent', 'parent_id': null},
      }),
    );
    await reviewItem(
      changeId: 'phone/2',
      type: 'todo',
      id: 'child',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'child',
        'operation': 'upsert',
        'payload': {'id': 'child', 'title': 'Child', 'parent_id': 'parent'},
      }),
    );

    final result = await service.resolve({
      'phone/1': 'keep',
      'phone/2': 'recover',
    });
    expect(result.kept, 1);
    expect(result.recovered, 1);
    final rows = await db.select(db.todoItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.title, 'Child');
    expect(rows.single.id, isNot('child'));
    expect(rows.single.parentId, isNull);
    final item = await db
        .customSelect(
          "SELECT * FROM snapshot_item WHERE disposition = 'pending'",
        )
        .getSingle();
    final payload = jsonDecode(item.read<String>('payload_json'));
    expect(payload['payload']['parent_id'], isNull);
  });

  test('a completion cannot recover without its deleted todo', () async {
    await db.addTodoItem('Todo', null, id: 'todo1');
    await db.addTodoCompletion(todoId: 'todo1', id: 'c1');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 'todo1',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 'todo1',
        'operation': 'upsert',
        'payload': {'id': 'todo1', 'title': 'Todo'},
      }),
    );
    await reviewItem(
      changeId: 'phone/2',
      type: 'todo_completion',
      id: 'c1',
      payloadJson: jsonEncode({
        'entityType': 'todo_completion',
        'entityId': 'c1',
        'operation': 'upsert',
        'payload': {'id': 'c1', 'todo_id': 'todo1'},
      }),
    );

    final result = await service.resolve({
      'phone/1': 'keep',
      'phone/2': 'recover',
    });
    expect(result.kept, 2);
    expect(result.recovered, 0);
    expect(await db.select(db.todoItems).get(), isEmpty);
    expect(await db.select(db.todoCompletions).get(), isEmpty);
  });

  test('leaving a row keeps it staged for later', () async {
    await db.addTodoItem('Later', null, id: 't1');
    await reviewItem(
      changeId: 'phone/1',
      type: 'todo',
      id: 't1',
      payloadJson: jsonEncode({
        'entityType': 'todo',
        'entityId': 't1',
        'operation': 'upsert',
        'payload': {'id': 't1', 'title': 'Later'},
      }),
    );
    final result = await service.resolve({'phone/1': 'leave'});
    expect(result.remaining, 1);
    expect(await service.reviewCount(), 1);
    expect(await db.getTodoItem('t1'), isNotNull);
  });
}
