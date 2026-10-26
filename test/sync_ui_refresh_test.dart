import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/notification_service.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/events/data/event_repository.dart';

void main() {
  late AppDatabase db;
  late DateTime Function() originalNow;

  setUp(() {
    originalNow = AppClock.now;
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    AppClock.now = originalNow;
    await db.close();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  Map<String, dynamic> change(
    String type,
    String id,
    Map<String, dynamic> fields, {
    String operation = 'upsert',
    int version = 1000,
  }) => {
    'entityType': type,
    'entityId': id,
    'operation': operation,
    'deviceId': 'remote-device',
    'payload': {'id': id, ...fields, 'updated_at': version},
  };

  Map<String, dynamic> todo(String id, String title, {int version = 1000}) =>
      change('todo', id, {
        'title': title,
        'completed': 0,
        'created_at': 1760000000,
        'due_date': null,
      }, version: version);

  test('applied changes refresh watch() streams', () async {
    final titles = <List<String>>[];
    final sub = db
        .select(db.todoItems)
        .watch()
        .listen((rows) => titles.add([for (final row in rows) row.title]));
    await settle();
    expect(titles.last, isEmpty);

    await SyncChangeApplier(db).apply([todo('t1', 'from phone')]);
    await settle();
    expect(titles.last, ['from phone']);

    await SyncChangeApplier(
      db,
    ).apply([todo('t1', 'edited on phone', version: 2000)]);
    await settle();
    expect(titles.last, ['edited on phone']);

    await SyncChangeApplier(
      db,
    ).apply([change('todo', 't1', {}, operation: 'delete', version: 3000)]);
    await settle();
    expect(titles.last, isEmpty);
    await sub.cancel();
  });

  test('skipped changes do not notify streams', () async {
    final applier = SyncChangeApplier(db);
    await applier.apply([todo('t1', 'newest', version: 5000)]);
    var emissions = 0;
    final sub = db.select(db.todoItems).watch().listen((_) => emissions++);
    await settle();
    final before = emissions;

    final result = await applier.apply([todo('t1', 'stale', version: 1000)]);
    await settle();
    expect(result.applied, 0);
    expect(emissions, before);
    await sub.cancel();
  });

  test('the result lists the rows that changed', () async {
    final result = await SyncChangeApplier(db).apply([
      todo('t1', 'one'),
      change('todo', 't2', {}, operation: 'delete'),
      todo('t1', 'older', version: 1),
    ]);
    expect(result.applied, 2);
    expect(result.skipped, 1);
    expect(result.changes, [
      (type: 'todo', id: 't1', deleted: false),
      (type: 'todo', id: 't2', deleted: true),
    ]);
  });

  test('deleting a project by sync refreshes its task stream', () async {
    final applier = SyncChangeApplier(db);
    await applier.apply([
      change('project', 'p1', {
        'name': 'Project',
        'description': null,
        'created_at': 1760000000,
        'target_date': null,
        'target_progress': 100,
      }),
      change('project_task', 'k1', {
        'project_id': 'p1',
        'title': 'Task',
        'completed': 0,
        'sort_order': 0,
      }),
    ]);

    final counts = <int>[];
    final sub = db
        .select(db.tasks)
        .watch()
        .listen((rows) => counts.add(rows.length));
    await settle();
    expect(counts.last, 1);

    await applier.apply([
      change('project', 'p1', {}, operation: 'delete', version: 2000),
    ]);
    await settle();
    expect(counts.last, 0);
    await sub.cancel();
  });

  group('event reminders for synced events', () {
    // A fixed clock half a second past a whole second lets a stored event
    // (whole-second precision) have a reminder due 500 ms from now.
    final now = DateTime(2026, 10, 23, 9, 0, 0, 500);
    final start = DateTime(2026, 10, 23, 9, 0, 1);

    Map<String, dynamic> eventChange({String operation = 'upsert'}) => change(
      'event',
      'e1',
      operation == 'delete'
          ? {}
          : {
              'title': 'Synced meeting',
              'description': null,
              'start_time': start.millisecondsSinceEpoch ~/ 1000,
              'end_time': null,
              'category': 'general',
              'has_reminder': 1,
              'reminder_minutes': 0,
              'recurrence_rule': null,
            },
      operation: operation,
    );

    test('a synced event with a reminder is armed', () async {
      AppClock.now = () => now;
      final shown = <String>[];
      final notifications = NotificationService(
        showOverride: ({required title, required body}) async =>
            shown.add(title),
      );
      final repository = EventRepository(db, notifications, UndoService());

      final result = await SyncChangeApplier(db).apply([eventChange()]);
      await repository.rescheduleReminders(
        result.changes.where((c) => c.type == 'event').map((c) => c.id),
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(shown, ['Synced meeting']);
      notifications.dispose();
    });

    test('a synced delete cancels the armed reminder', () async {
      AppClock.now = () => now;
      final shown = <String>[];
      final notifications = NotificationService(
        showOverride: ({required title, required body}) async =>
            shown.add(title),
      );
      final repository = EventRepository(db, notifications, UndoService());
      final applier = SyncChangeApplier(db);

      await applier.apply([eventChange()]);
      await repository.rescheduleReminders(['e1']);
      final result = await applier.apply([
        change('event', 'e1', {}, operation: 'delete', version: 2000),
      ]);
      await repository.rescheduleReminders(result.changes.map((c) => c.id));
      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(shown, isEmpty);
      notifications.dispose();
    });
  });
}
