import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

import 'package:drift_dev/api/migrations_native.dart';

import 'generated_migrations/schema.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  Future<void> upgradePair(int from, int to) async {
    final schema = await verifier.schemaAt(from);
    schema.rawDatabase.execute('''
      CREATE TABLE IF NOT EXISTS sync_row_versions (
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL, device_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      ) WITHOUT ROWID;
    ''');
    final db = AppDatabase.forTesting(
      schema.newConnection(),
      schemaVersion: to,
    );
    await verifier.migrateAndValidate(db, to);
    await db.close();
  }

  test('every released step upgrades in isolation', () async {
    for (final pair in const [
      (9, 12),
      (9, 14),
      (10, 11),
      (11, 12),
      (12, 13),
      (13, 14),
      (14, 15),
      (15, 16),
      (16, 17),
    ]) {
      await upgradePair(pair.$1, pair.$2);
    }
  });

  test('schema 12 and 13 upgrade to the current version', () async {
    for (final version in const [12, 13]) {
      final connection = await verifier.startAt(version);
      final db = AppDatabase.forTesting(connection);
      await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);
      await db.close();
    }
  });

  test('a populated schema-9 database upgrades to the current version', () async {
    final schema = await verifier.schemaAt(9);
    final raw = schema.rawDatabase;
    // Non-Drift state that exists in a real schema-9 file. The dump cannot
    // describe it, but migrations 10+ rebuild triggers against it.
    raw.execute('''
      CREATE TABLE sync_row_versions (
        entity_type TEXT NOT NULL, entity_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL, device_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      ) WITHOUT ROWID;
    ''');
    raw.execute(
      "INSERT INTO sync_row_versions "
      "(entity_type, entity_id, updated_at, device_id, deleted) "
      "VALUES ('todo', 'todo-1', 1234, 'old-device', 0)",
    );
    raw.execute(
      "INSERT INTO app_settings (key, value) VALUES ('sync.epoch', 'old-epoch')",
    );

    const seconds = 1760000000;
    raw.execute(
      "INSERT INTO projects (id, name, created_at) VALUES ('p1', 'Project', $seconds)",
    );
    raw.execute(
      "INSERT INTO tasks (id, project_id, title) VALUES ('t1', 'p1', 'Task')",
    );
    raw.execute(
      "INSERT INTO events (id, title, start_time) VALUES ('e1', 'Event', $seconds)",
    );
    raw.execute(
      "INSERT INTO todo_items (id, title, created_at) VALUES ('todo-1', 'Todo', $seconds)",
    );
    raw.execute(
      "INSERT INTO diary_entries (id, date, mood, content) "
      "VALUES ('d1', $seconds, 4, 'Diary')",
    );
    raw.execute(
      "INSERT INTO habits (id, name, created_at) VALUES ('h1', 'Habit', $seconds)",
    );
    raw.execute(
      "INSERT INTO habit_logs (id, habit_id, date) VALUES ('l1', 'h1', $seconds)",
    );

    final db = AppDatabase.forTesting(schema.newConnection());
    await verifier.migrateAndValidate(db, AppDatabase.currentSchemaVersion);

    expect((await db.select(db.projects).getSingle()).name, 'Project');
    expect((await db.select(db.tasks).getSingle()).title, 'Task');
    expect((await db.select(db.events).getSingle()).title, 'Event');
    expect((await db.select(db.todoItems).getSingle()).title, 'Todo');
    final migratedTodo = await db.select(db.todoItems).getSingle();
    expect(migratedTodo.priority, 0);
    expect(migratedTodo.tags, '[]');
    expect((await db.select(db.diaryEntries).getSingle()).content, 'Diary');
    expect((await db.select(db.habits).getSingle()).name, 'Habit');
    expect((await db.select(db.habitLogs).getSingle()).habitId, 'h1');
    expect(await db.getSetting('sync.epoch'), isNot('old-epoch'));

    // The version row written before the upgrade is untouched by migration.
    final versionRow = await db
        .customSelect(
          "SELECT updated_at FROM sync_row_versions "
          "WHERE entity_type = 'todo' AND entity_id = 'todo-1'",
        )
        .getSingle();
    expect(versionRow.read<int>('updated_at'), 1234);

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), AppDatabase.currentSchemaVersion);

    final triggerRows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    final triggers = triggerRows.map((row) => row.read<String>('name')).toSet();
    expect(
      triggers,
      containsAll([
        'sync_outbox_events_insert',
        'sync_outbox_todo_items_update',
        'sync_outbox_daily_plans_insert',
        'sync_outbox_daily_plan_items_insert',
        'sync_outbox_todo_completions_insert',
      ]),
    );

    await db.customStatement(
      "UPDATE todo_items SET title = 'Updated' WHERE id = 'todo-1'",
    );
    final payloadRows = await db
        .customSelect(
          "SELECT payload FROM sync_outbox WHERE entity_type = 'todo' "
          "ORDER BY id DESC LIMIT 1",
        )
        .get();
    expect(payloadRows, isNotEmpty);
    final payload = payloadRows.first.read<String>('payload');
    expect(payload, contains('"priority"'));
    expect(payload, contains('"tags"'));
    expect(payload, contains('"notes"'));

    // A plan item edit carries business time and sync version separately.
    await db.customStatement(
      "INSERT INTO daily_plans (id, day_key, created_at, updated_at) "
      "VALUES ('plan-1', '2026-05-20', $seconds, $seconds)",
    );
    final planPayload =
        (await db
                .customSelect(
                  "SELECT payload FROM sync_outbox WHERE entity_type = 'daily_plan' "
                  'ORDER BY id DESC LIMIT 1',
                )
                .get())
            .first
            .read<String>('payload');
    expect(planPayload, contains('"updated_at":$seconds'));
    expect(planPayload, contains('"sync_updated_at"'));

    expect(
      await db
          .customSelect('PRAGMA integrity_check')
          .getSingle()
          .then((row) => row.data.values.first),
      'ok',
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

    // The CHECK constraints reject rows that are not a single task reference.
    await expectLater(
      db.customStatement(
        "INSERT INTO daily_plan_items "
        "(id, plan_id, todo_item_id, project_task_id, created_at, updated_at) "
        "VALUES ('bad', 'plan-1', NULL, NULL, $seconds, $seconds)",
      ),
      throwsA(anything),
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO daily_plan_items "
        "(id, plan_id, todo_item_id, planned_minutes, created_at, updated_at) "
        "VALUES ('bad-2', 'plan-1', 'todo-1', 0, $seconds, $seconds)",
      ),
      throwsA(anything),
    );
    await db.customStatement(
      "INSERT INTO daily_plan_items "
      "(id, plan_id, todo_item_id, created_at, updated_at) "
      "VALUES ('item-1', 'plan-1', 'todo-1', $seconds, $seconds)",
    );
    await expectLater(
      db.customStatement(
        "INSERT INTO daily_plan_items "
        "(id, plan_id, todo_item_id, created_at, updated_at) "
        "VALUES ('item-dup', 'plan-1', 'todo-1', $seconds, $seconds)",
      ),
      throwsA(anything),
    );

    // Foreign keys still behave after the upgrade.
    final parentId = await db.addTodoItem('Upgrade parent', null);
    final childId = await db.addTodoItem(
      'Upgrade child',
      null,
      parentId: parentId,
    );
    await db.deleteTodoItem(parentId);
    expect(await db.getTodoItem(childId), isNull);

    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p2',
            name: 'Linked project',
            createdAt: DateTime(2026, 5, 20),
          ),
        );
    final linkedId = await db.addTodoItem('Linked task', null, projectId: 'p2');
    await (db.delete(db.projects)..where((t) => t.id.equals('p2'))).go();
    expect((await db.getTodoItem(linkedId))?.projectId, isNull);

    await db.close();
  });
}
