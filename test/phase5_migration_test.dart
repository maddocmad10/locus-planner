import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

import 'generated_migrations/schema.dart';

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  void seedLegacyRows(dynamic raw) {
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
      "VALUES ('todo-1', 'Legacy task', 0, 1760000000, 0, '[]')",
    );
    raw.execute(
      "INSERT INTO events (id, title, start_time, category) "
      "VALUES ('event-1', 'Legacy event', 1760000000, 'general')",
    );
  }

  test('schema 16, 19 and 20 upgrade to 21 without losing rows', () async {
    for (final from in const [16, 19, 20]) {
      final schema = await verifier.schemaAt(from);
      seedLegacyRows(schema.rawDatabase);

      final db = AppDatabase.forTesting(
        schema.newConnection(),
        schemaVersion: 21,
      );
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 21);

      final todo = await db.select(db.todoItems).getSingle();
      expect(todo.id, 'todo-1');
      expect(todo.title, 'Legacy task');
      expect(todo.notesFormat, 'plain');

      final event = await db.select(db.events).getSingle();
      expect(event.id, 'event-1');
      expect(event.title, 'Legacy event');
      expect(event.descriptionFormat, 'plain');

      final tables = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        containsAll(['attachments', 'attachment_blobs']),
      );

      await db.close();
    }
  });

  test('migration 21 rebuilds triggers and syncs attachment metadata', () async {
    final schema = await verifier.schemaAt(20);
    seedLegacyRows(schema.rawDatabase);

    final db = AppDatabase.forTesting(
      schema.newConnection(),
      schemaVersion: 21,
    );
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 21);

    final triggers = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    final triggerNames = triggers.map((row) => row.read<String>('name')).toSet();
    expect(triggerNames, contains('sync_outbox_todo_items_update'));
    expect(triggerNames, contains('sync_outbox_events_update'));
    expect(triggerNames, contains('sync_outbox_attachments_insert'));
    expect(triggerNames, isNot(contains('sync_outbox_attachment_blobs_insert')));

    await db.customStatement(
      "UPDATE todo_items SET title = 'Renamed' WHERE id = 'todo-1'",
    );
    final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: 'attachment-1',
            kind: 'file',
            displayName: 'notes.txt',
            mimeType: 'text/plain',
            sizeBytes: 5,
            sha256: 'a' * 64,
            createdAt: now,
            updatedAt: now,
            todoId: const Value('todo-1'),
          ),
        );

    final outbox = await db.select(db.syncOutbox).get();
    final todoPayload = outbox
        .where((row) => row.entityType == 'todo' && row.entityId == 'todo-1')
        .map((row) => jsonDecode(row.payload) as Map<String, dynamic>)
        .last;
    expect(todoPayload['notes_format'], 'plain');

    final attachment = outbox.singleWhere(
      (row) => row.entityType == 'attachment' && row.entityId == 'attachment-1',
    );
    final attachmentPayload =
        jsonDecode(attachment.payload) as Map<String, dynamic>;
    expect(attachmentPayload['todo_id'], 'todo-1');
    expect(attachmentPayload['display_name'], 'notes.txt');
    expect(attachmentPayload['sha256'], 'a' * 64);
  });

  test('attachment rows require exactly one parent', () async {
    final schema = await verifier.schemaAt(20);
    seedLegacyRows(schema.rawDatabase);

    final db = AppDatabase.forTesting(
      schema.newConnection(),
      schemaVersion: 21,
    );
    addTearDown(db.close);
    await verifier.migrateAndValidate(db, 21);

    final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);
    Future<void> insert(String id, {String? todoId, String? eventId}) {
      return db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: id,
              kind: 'file',
              displayName: 'notes.txt',
              mimeType: 'text/plain',
              sizeBytes: 5,
              sha256: 'b' * 64,
              createdAt: now,
              updatedAt: now,
              todoId: Value(todoId),
              eventId: Value(eventId),
            ),
          );
    }

    await expectLater(insert('no-parent'), throwsA(anything));
    await expectLater(
      insert('two-parents', todoId: 'todo-1', eventId: 'event-1'),
      throwsA(anything),
    );
    await insert('valid', todoId: 'todo-1');
    expect(await db.select(db.attachments).get(), hasLength(1));
  });
}
