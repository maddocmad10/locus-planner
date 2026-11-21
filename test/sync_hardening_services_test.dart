import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_activity_service.dart';
import 'package:locus_planner/core/services/sync_tombstone_gc.dart';

void main() {
  test('tombstone GC prunes only old unreferenced tombstones', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = now - const Duration(days: 200).inMilliseconds;
    await db.customStatement(
      'INSERT INTO sync_row_versions '
      '(entity_type, entity_id, updated_at, hlc_counter, deleted) '
      "VALUES ('todo', 'old', ?, 0, 1)",
      [old],
    );
    await db.customStatement(
      'INSERT INTO sync_row_versions '
      '(entity_type, entity_id, updated_at, hlc_counter, deleted) '
      "VALUES ('todo', 'recent', ?, 0, 1)",
      [now],
    );

    final pruned = await SyncTombstoneGc(db).prune();
    expect(pruned, 1);
    final rows = await db
        .customSelect('SELECT entity_id FROM sync_row_versions')
        .get();
    expect(rows.map((row) => row.read<String>('entity_id')), ['recent']);
    expect(
      await db.getSetting(AppDatabase.syncTombstoneHorizonSettingKey),
      '$old',
    );
  });

  test('sync activity records attempts and reviews conflicts', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final service = SyncActivityService(db);
    await service.record(
      startedAt: DateTime.now(),
      durationMs: 42,
      peerId: 'phone-1',
      direction: 'push',
      applied: 2,
      skipped: 1,
      rejected: 0,
    );
    final logs = await service.recent();
    expect(logs.single.applied, 2);
    expect(logs.single.peerId, 'phone-1');

    await db.customStatement(
      'INSERT INTO sync_conflicts '
      '(entity_type, entity_id, field, kind, loser_value, loser_device, '
      'loser_wall, winner_wall, created_at) '
      "VALUES ('todo', 't1', 'title', 'field', '\"mine\"', 'phone-1', 1, 2, ?)",
      [DateTime.now().millisecondsSinceEpoch],
    );
    final open = await service.openConflicts();
    expect(open.single.field, 'title');
    await service.markReviewed(open.single.id);
    expect(await service.openConflicts(), isEmpty);
  });
}
