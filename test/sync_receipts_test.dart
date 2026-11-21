import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/services/sync_receipt_store.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Map<String, dynamic> change(
    String changeId, {
    String id = 't1',
    int version = 1000,
    String reason = '',
  }) => {
    'changeId': changeId,
    'entityType': 'todo',
    'entityId': id,
    'operation': 'upsert',
    'deviceId': 'phone',
    'payload': {
      'id': id,
      'title': 'Task $changeId',
      'notes': null,
      'notes_format': 'plain',
      'completed': 0,
      'created_at': 1760000000,
      'start_date': null,
      'due_date': null,
      'priority': 0,
      'tags': '[]',
      'recurrence_rule': null,
      'recurrence_spec': null,
      'parent_id': null,
      'project_id': null,
      'reminder_at': null,
      'estimated_minutes': null,
      'is_important': 0,
      'urgency_override': null,
      'updated_at': version,
      'hlc_counter': 0,
      if (reason.isNotEmpty) 'unexpected': reason,
    },
  };

  test(
    'a batch echoes one receipt per change and persists clean progress',
    () async {
      final result = await SyncChangeApplier(db).apply(
        [change('phone/1'), change('phone/2', id: 't2')],
        receiptContext: const SyncReceiptContext(
          peerId: 'desktop',
          epoch: 'e1',
          direction: 'push',
        ),
      );
      expect(result.receipts, hasLength(2));
      expect(result.receipts.map((r) => r.outcome), ['applied', 'applied']);
      expect(result.receipts.map((r) => r.changeId), ['phone/1', 'phone/2']);
      final store = SyncReceiptStore(db);
      expect(await store.openRejectionCount(), 0);
      expect((await store.latestClean())?.lastClean, isNotNull);
    },
  );

  test(
    'a rejected change keeps its original revision and resolves on retry',
    () async {
      final bad = <String, dynamic>{
        'changeId': 'phone/9',
        'entityType': 'habit_log',
        'entityId': 'log-9',
        'operation': 'upsert',
        'deviceId': 'phone',
        'payload': {
          'id': 'log-9',
          'habit_id': 'missing-habit',
          'date': 1760000000,
          'completed': 1,
          'updated_at': 1000,
          'hlc_counter': 0,
        },
      };
      final first = await SyncChangeApplier(db).apply(
        [bad],
        receiptContext: const SyncReceiptContext(
          peerId: 'desktop',
          epoch: 'e1',
          direction: 'push',
        ),
      );
      expect(first.receipts.single.outcome, 'rejected');
      final store = SyncReceiptStore(db);
      final open = await store.openRejections();
      expect(open, hasLength(1));
      expect(open.single.changeId, 'phone/9');
      expect(open.single.reasonCode, 'missing_parent');

      await db.customStatement(
        'INSERT INTO habits (id, name, created_at, target_per_week) '
        'VALUES (?, ?, ?, ?)',
        ['missing-habit', 'Habit', 1760000000, 5],
      );
      final retry = await SyncChangeApplier(db).apply(
        [bad],
        receiptContext: const SyncReceiptContext(
          peerId: 'desktop',
          epoch: 'e1',
          direction: 'push',
        ),
      );
      expect(retry.receipts.single.outcome, 'applied');
      expect(await store.openRejectionCount(), 0);
    },
  );

  test('an identical replay is reported as replay, not applied', () async {
    final applier = SyncChangeApplier(db);
    await applier.apply([change('phone/1')]);
    final second = await applier.apply([change('phone/1')]);
    expect(second.receipts.single.outcome, 'replay');
  });

  test('an older change is superseded and keeps the existing row', () async {
    final applier = SyncChangeApplier(db);
    await applier.apply([change('phone/1', version: 2000)]);
    final older = await applier.apply([change('phone/2', version: 1000)]);
    expect(older.receipts.single.outcome, 'superseded');
    final row = await db.getTodoItem('t1');
    expect(row?.title, 'Task phone/1');
  });

  test('unsupported future entities do not create repairs', () async {
    final result = await SyncChangeApplier(db).apply(
      [
        {
          'changeId': 'phone/7',
          'entityType': 'future_planning_entity',
          'entityId': 'x1',
          'operation': 'upsert',
          'deviceId': 'phone',
          'payload': {'id': 'x1'},
        },
      ],
      receiptContext: const SyncReceiptContext(
        peerId: 'desktop',
        epoch: 'e1',
        direction: 'push',
      ),
    );
    expect(result.receipts.single.outcome, 'unsupported');
    expect(await SyncReceiptStore(db).openRejectionCount(), 1);
  });

  test('snapshot staging resumes and clears only after completion', () async {
    final store = SyncReceiptStore(db);
    await store.createSnapshotSession(
      snapshotId: 'snap-1',
      peerId: 'desktop',
      epoch: 'e1',
      trustedBaselineServerMs: 123,
    );
    await store.saveSnapshotItems('snap-1', [
      (
        changeId: 'snapshot:1',
        ordinal: 0,
        payloadJson: '{"entityType":"todo","entityId":"t1"}',
      ),
      (
        changeId: 'snapshot:2',
        ordinal: 1,
        payloadJson: '{"entityType":"todo","entityId":"t2"}',
      ),
    ]);
    final session = await store.latestSnapshotSession(
      peerId: 'desktop',
      epoch: 'e1',
    );
    expect(session!['snapshot_id'], 'snap-1');
    await store.markSnapshotItem(
      snapshotId: 'snap-1',
      changeId: 'snapshot:1',
      disposition: 'applied',
    );
    await store.updateSnapshotSession(
      snapshotId: 'snap-1',
      remoteCursor: 42,
      resumeToken: 'row-b',
      phase: 'upload',
    );
    final items = await store.snapshotItems('snap-1');
    expect(items, hasLength(2));
    expect(items.first['disposition'], 'applied');
    expect(items.last['disposition'], 'pending');

    await store.completeSnapshotSession('snap-1');
    expect(await store.snapshotItems('snap-1'), isEmpty);
    expect(
      await store.latestSnapshotSession(peerId: 'desktop', epoch: 'e1'),
      isNull,
    );
  });
}
