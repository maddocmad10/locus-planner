import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

import 'generated_migrations/schema.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('schema 19 to 20 adds Eisenhower fields with safe defaults', () async {
    final schema = await verifier.schemaAt(19);
    final raw = schema.rawDatabase;
    raw.execute('''
      CREATE TABLE IF NOT EXISTS sync_row_versions (
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL, device_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      ) WITHOUT ROWID;
    ''');
    raw.execute(
      "INSERT INTO todo_items (id, title, completed, created_at, priority, tags) "
      "VALUES ('todo-1', 'Task', 0, 1760000000, 0, '[]')",
    );
    raw.execute(
      "INSERT INTO planning_preferences "
      "(id, default_slot_minutes, week_start_day, day_start_minute, "
      "day_end_minute, buffer_minutes, created_at, updated_at) "
      "VALUES ('profile-1', 30, 1, 480, 1080, 10, 1760000000, 1760000000)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 20);

    final todo = await db.select(db.todoItems).getSingle();
    expect(todo.id, 'todo-1');
    expect(todo.isImportant, isFalse);
    expect(todo.urgencyOverride, isNull);
    final profile = await db.select(db.planningPreferences).getSingle();
    expect(profile.id, 'profile-1');
    expect(profile.urgencyWindowDays, 3);
  });
}
