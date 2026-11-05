import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

import 'generated_migrations/schema.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test('schema 17 to 19 backfills status without changing task ids', () async {
    final schema = await verifier.schemaAt(17);
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
      "INSERT INTO projects (id, name, created_at) "
      "VALUES ('p1', 'Launch', 1760000000)",
    );
    raw.execute(
      "INSERT INTO tasks (id, project_id, title, completed, sort_order) "
      "VALUES ('t-todo', 'p1', 'Open', 0, 0)",
    );
    raw.execute(
      "INSERT INTO tasks (id, project_id, title, completed, sort_order) "
      "VALUES ('t-done', 'p1', 'Closed', 1, 1)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 19);

    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      19,
    );
    final tasks = await db.select(db.tasks).get();
    expect(tasks.map((task) => task.id), containsAll(['t-todo', 't-done']));
    expect(tasks.firstWhere((task) => task.id == 't-todo').statusKey, 'todo');
    expect(tasks.firstWhere((task) => task.id == 't-done').statusKey, 'done');
    expect(tasks.firstWhere((task) => task.id == 't-done').completed, isTrue);

    final statuses = await db.select(db.projectStatuses).get();
    expect(statuses, hasLength(5));
    expect(
      statuses.map((status) => status.statusKey),
      containsAll(['backlog', 'todo', 'in_progress', 'waiting', 'done']),
    );

    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(
      tables.map((row) => row.read<String>('name')),
      containsAll([
        'project_statuses',
        'project_milestones',
        'task_dependencies',
      ]),
    );
  });

  test(
    'schema 18 to 19 adds dependencies without touching task rows',
    () async {
      final schema = await verifier.schemaAt(18);
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
        "INSERT INTO projects (id, name, created_at) "
        "VALUES ('p2', 'Project', 1760000000)",
      );
      raw.execute(
        "INSERT INTO tasks (id, project_id, title, completed, status_key) "
        "VALUES ('t1', 'p2', 'Task', 1, 'done')",
      );

      final db = AppDatabase.forTesting(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 19);

      final task = await db.select(db.tasks).getSingle();
      expect(task.id, 't1');
      expect(task.statusKey, 'done');
      expect(task.completed, isTrue);
      expect(await db.select(db.taskDependencies).get(), isEmpty);
    },
  );
}
