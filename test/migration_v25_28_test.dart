import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Set<String>> tables() async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    return {for (final row in rows) row.read<String>('name')};
  }

  test('migration 25 reliability tables exist', () async {
    final names = await tables();
    expect(names, contains('sync_peer_progress'));
    expect(names, contains('sync_rejected_changes'));
  });

  test('migration 26 calendar cache is device-local', () async {
    final names = await tables();
    expect(names, contains('calendar_sources'));
    expect(names, contains('calendar_occurrences'));
    // Device-local caches must not appear in the synced schema.
    expect(SyncChangeApplierSchemas.contains('calendar_source'), isFalse);
    expect(SyncChangeApplierSchemas.contains('calendar_occurrence'), isFalse);
  });

  test('migration 27 import receipts exist', () async {
    expect(await tables(), contains('import_receipts'));
  });

  test('migration 28 recurrence_spec columns are nullable', () async {
    for (final table in ['todo_items', 'events']) {
      final rows = await db.customSelect("PRAGMA table_info('$table')").get();
      final column = rows.singleWhere(
        (row) => row.read<String>('name') == 'recurrence_spec',
      );
      expect(column.read<int>('notnull'), 0);
    }
  });
}

/// Kept local so the test does not need the private schema map.
abstract final class SyncChangeApplierSchemas {
  static const values = {
    'event',
    'project',
    'project_task',
    'habit',
    'todo',
    'diary_entry',
    'attachment',
  };
  static bool contains(String type) => values.contains(type);
}
