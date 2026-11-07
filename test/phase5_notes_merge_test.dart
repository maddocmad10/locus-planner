import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/utils/diary_merge.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> currentTodoPayload(String id) async {
    final state = await SyncChangeApplier.readFullState(db);
    return state.singleWhere(
          (row) => row['entityType'] == 'todo' && row['entityId'] == id,
        )['payload']
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> currentEventPayload(String id) async {
    final state = await SyncChangeApplier.readFullState(db);
    return state.singleWhere(
          (row) => row['entityType'] == 'event' && row['entityId'] == id,
        )['payload']
        as Map<String, dynamic>;
  }

  test('a losing todo note is appended instead of discarded', () async {
    final id = await db.addTodoItem('Task', null, notes: 'Local note');
    final payload = await currentTodoPayload(id);
    final localVersion = payload['updated_at'] as int;

    final result = await SyncChangeApplier(db).apply([
      {
        'entityType': 'todo',
        'entityId': id,
        'operation': 'upsert',
        'deviceId': 'phone',
        'payload': {
          ...payload,
          'notes': 'Remote note',
          'notes_format': 'md1',
          'updated_at': localVersion - 1000,
        },
      },
    ]);

    expect(result.applied, 1);
    final row = (await db.select(db.todoItems).getSingle());
    expect(row.notes, contains('Local note'));
    expect(row.notes, contains('Remote note'));
    expect(row.notes, contains(diaryMergeDivider.trim()));
    expect(row.notesFormat, 'md1');

    // The merged text is queued back to the sender.
    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox.where((entry) => entry.entityType == 'todo'), isNotEmpty);
    expect(outbox.last.payload, contains('Remote note'));
  });

  test('a winning incoming note keeps the local text too', () async {
    final id = await db.addTodoItem('Task', null, notes: 'Local note');
    final payload = await currentTodoPayload(id);
    final localVersion = payload['updated_at'] as int;

    await SyncChangeApplier(db).apply([
      {
        'entityType': 'todo',
        'entityId': id,
        'operation': 'upsert',
        'deviceId': 'phone',
        'payload': {
          ...payload,
          'notes': 'Remote note',
          'notes_format': 'md1',
          'updated_at': localVersion + 1000,
        },
      },
    ]);

    final row = await db.select(db.todoItems).getSingle();
    expect(row.notes, contains('Remote note'));
    expect(row.notes, contains('Local note'));
    expect(row.notes, contains(diaryMergeDivider.trim()));
    expect(row.notesFormat, 'md1');
  });

  test(
    'merging the same losing change twice does not duplicate text',
    () async {
      final id = await db.addTodoItem('Task', null, notes: 'Local note');
      final payload = await currentTodoPayload(id);
      final localVersion = payload['updated_at'] as int;
      final change = {
        'entityType': 'todo',
        'entityId': id,
        'operation': 'upsert',
        'deviceId': 'phone',
        'payload': {
          ...payload,
          'notes': 'Remote note',
          'notes_format': 'plain',
          'updated_at': localVersion - 1000,
        },
      };

      await SyncChangeApplier(db).apply([change]);
      final once = (await db.select(db.todoItems).getSingle()).notes;
      final outboxAfterFirst = await db.outboxHead();

      await SyncChangeApplier(db).apply([change]);
      final twice = (await db.select(db.todoItems).getSingle()).notes;

      expect(twice, once);
      expect(
        twice!.split('Remote note').length - 1,
        1,
        reason: 'the divider merge must be idempotent',
      );
      expect(await db.outboxHead(), outboxAfterFirst);
    },
  );

  test('event descriptions use the same divider', () async {
    const eventId = 'event-1';
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: eventId,
            title: 'Meeting',
            description: const Value('Local agenda'),
            descriptionFormat: const Value('md1'),
            startTime: DateTime(2026, 11, 7, 9),
          ),
        );
    final payload = await currentEventPayload(eventId);
    final localVersion = payload['updated_at'] as int;

    await SyncChangeApplier(db).apply([
      {
        'entityType': 'event',
        'entityId': eventId,
        'operation': 'upsert',
        'deviceId': 'phone',
        'payload': {
          ...payload,
          'description': 'Remote agenda',
          'description_format': 'plain',
          'updated_at': localVersion - 1000,
        },
      },
    ]);

    final event = await db.select(db.events).getSingle();
    expect(event.description, contains('Local agenda'));
    expect(event.description, contains('Remote agenda'));
    expect(event.description, contains(diaryMergeDivider.trim()));
    expect(event.descriptionFormat, 'md1');
  });
}
