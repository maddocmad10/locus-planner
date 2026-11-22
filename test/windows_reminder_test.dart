import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/models/reminder_kind.dart';
import 'package:locus_planner/core/reminders/platform_reminder_store.dart';
import 'package:locus_planner/core/reminders/reminder_identity.dart';
import 'package:locus_planner/core/reminders/reminder_planner.dart';
import 'package:locus_planner/core/reminders/windows_reminder_service.dart';
import 'package:locus_planner/core/reminders/windows_toast_platform.dart';
import 'package:locus_planner/core/services/notification_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/events/data/event_repository.dart';
import 'package:locus_planner/features/tasks/data/task_repository.dart';

class _FakeToastPlatform extends WindowsToastPlatform {
  final scheduled = <Map<String, Object>>[];
  final cancelled = <Set<String>>[];
  final accepted = <String>{};
  bool Function(String id)? acceptId;
  bool listThrows = false;
  bool cancelThrows = false;
  bool scheduleResult = true;
  int badge = 0;

  @override
  Future<bool> setBadge(int count) async {
    badge = count;
    return true;
  }

  @override
  Future<bool> schedule(List<Map<String, Object>> items) async {
    scheduled.addAll(items);
    for (final item in items) {
      final id = item['id']! as String;
      if (acceptId?.call(id) ?? true) accepted.add(id);
    }
    return scheduleResult;
  }

  @override
  Future<void> cancelAllExcept(Set<String> keepIds) async {
    if (cancelThrows) throw PlatformException(code: 'cancel');
    cancelled.add(keepIds);
    accepted.removeWhere((id) => !keepIds.contains(id));
  }

  @override
  Future<List<String>?> listScheduled() async {
    if (listThrows) throw PlatformException(code: 'nope');
    return accepted.toList();
  }
}

void main() {
  late AppDatabase db;
  late _FakeToastPlatform toast;
  late NotificationService notifications;
  late List<String> shown;
  late WindowsReminderService service;
  late PlatformReminderStore store;

  setUp(() {
    NotificationService.clearOsScheduledIds();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    toast = _FakeToastPlatform();
    shown = [];
    notifications = NotificationService(
      db: db,
      showOverride: ({required title, required body}) async {
        shown.add(title);
      },
    );
    store = PlatformReminderStore(db);
    service = WindowsReminderService(
      db,
      toastPlatform: toast,
      store: store,
      notificationService: notifications,
    );
  });

  tearDown(() async {
    notifications.dispose();
    await db.close();
  });

  test('stable ids derive from the occurrence, not the fire time', () {
    final start = DateTime.utc(2026, 11, 20, 9);
    final first = stableReminderId(_reminder(start));
    final sameOccurrence = stableReminderId(
      _reminder(start, fireAt: start.subtract(const Duration(minutes: 10))),
    );
    final nextOccurrence = stableReminderId(
      _reminder(start.add(const Duration(days: 1))),
    );
    expect(first, hasLength(16));
    expect(first, sameOccurrence);
    expect(first, isNot(nextOccurrence));
    expect(
      first,
      ReminderOccurrence(
        kind: ReminderKind.task,
        entityId: 't1',
        occurrenceStart: start,
      ).stableId,
    );
  });

  test('refresh schedules tasks and events and records local state', () async {
    final now = DateTime.now();
    await insertTask(
      db,
      now,
      id: 'task-1',
      reminderAt: now.add(const Duration(minutes: 5)),
    );
    await insertEvent(db, now, id: 'event-1');

    await service.refresh();

    final tasks = await db.select(db.todoItems).get();
    final events = await db.select(db.events).get();
    final plan = planFor(tasks, events, now);
    expect(plan, hasLength(2));
    expect(toast.scheduled, hasLength(2));
    expect(
      toast.scheduled.map((item) => item['title']),
      containsAll(['Task', 'Event']),
    );
    final rows = await store.all();
    expect(rows, hasLength(2));
    expect(rows.every((row) => row.owner == 'os'), isTrue);
    expect(rows.every((row) => !row.degraded), isTrue);
  });

  test('hide titles never sends the title or body to the OS', () async {
    final now = DateTime.now();
    await db.setSetting(AppDatabase.hideNotificationTitlesSettingKey, '1');
    await insertTask(db, now, id: 'task-1', title: 'Secret title');

    await service.refresh();

    expect(toast.scheduled.single['title'], 'Locus reminder');
    expect(toast.scheduled.single['body'], '');
  });

  test(
    'per-id acceptance leaves exactly one owner for each occurrence',
    () async {
      final now = DateTime.now();
      await insertTask(
        db,
        now,
        id: 'task-1',
        reminderAt: now.add(const Duration(minutes: 5)),
      );
      await insertEvent(db, now, id: 'event-1');
      var calls = 0;
      toast.acceptId = (_) => calls++ == 0;

      await service.refresh();

      final tasks = await db.select(db.todoItems).get();
      final events = await db.select(db.events).get();
      final plan = planFor(tasks, events, now);
      final rows = {for (final row in await store.all()) row.id: row};
      expect(rows, hasLength(2));

      var osOwned = 0;
      var fallback = 0;
      for (final reminder in plan) {
        final row = rows[reminder.stableId];
        expect(row == null, isFalse);
        if (row!.owner == 'os') {
          osOwned++;
          expect(NotificationService.isOsOwnedId(reminder.stableId), isTrue);
          expect(
            notifications.scheduledReminderKeys,
            isNot(contains(reminder.id)),
          );
        } else {
          fallback++;
          expect(row.owner, 'app');
          expect(row.degraded, isTrue);
          expect(NotificationService.isOsOwnedId(reminder.stableId), isFalse);
          expect(notifications.scheduledReminderKeys, contains(reminder.id));
        }
      }
      expect(osOwned, 1);
      expect(fallback, 1);
      expect(toast.accepted, hasLength(1));
    },
  );

  test(
    'swapping which id is accepted swaps ownership, never duplicates',
    () async {
      final now = DateTime.now();
      await insertTask(
        db,
        now,
        id: 'task-1',
        reminderAt: now.add(const Duration(minutes: 5)),
      );
      await insertEvent(db, now, id: 'event-1');
      var calls = 0;
      toast.acceptId = (_) => calls++ == 1;

      await service.refresh();

      final tasks = await db.select(db.todoItems).get();
      final events = await db.select(db.events).get();
      final plan = planFor(tasks, events, now);
      final rows = {for (final row in await store.all()) row.id: row};
      expect(rows, hasLength(2));
      for (final reminder in plan) {
        final row = rows[reminder.stableId]!;
        expect(
          row.owner,
          toast.accepted.contains(reminder.stableId) ? 'os' : 'app',
        );
        expect(
          notifications.scheduledReminderKeys.contains(reminder.id),
          !toast.accepted.contains(reminder.stableId),
        );
      }
      expect(rows.values.where((row) => row.owner == 'os'), hasLength(1));
      expect(rows.values.where((row) => row.owner == 'app'), hasLength(1));
    },
  );

  test('listScheduled failure is unknown, not empty', () async {
    final now = DateTime.now();
    await insertTask(
      db,
      now,
      id: 'task-1',
      reminderAt: now.add(const Duration(minutes: 5)),
    );
    toast.listThrows = true;

    await service.refresh();

    final rows = await store.all();
    expect(rows, hasLength(1));
    expect(rows.single.owner, 'os');
    expect(rows.single.degraded, isFalse);
    expect(notifications.scheduledReminderKeys, isEmpty);
  });

  test('unknown batch failure arms no fallback', () async {
    final now = DateTime.now();
    await insertTask(
      db,
      now,
      id: 'task-1',
      reminderAt: now.add(const Duration(minutes: 5)),
    );
    toast.listThrows = true;
    toast.scheduleResult = false;
    toast.acceptId = (_) => false;

    await service.refresh();

    final rows = await store.all();
    expect(rows.single.owner, 'unknown');
    expect(rows.single.degraded, isTrue);
    expect(rows.single.needsAppRunning, isTrue);
    expect(notifications.scheduledReminderKeys, isEmpty);
  });

  test('a cancelAllExcept failure does not abort reconciliation', () async {
    final now = DateTime.now();
    await insertTask(db, now, id: 'task-1');
    toast.cancelThrows = true;

    await service.refresh();

    expect(toast.scheduled, isNotEmpty);
    expect(await store.all(), hasLength(1));
  });

  test('an enumerated empty list is trusted and arms fallbacks', () async {
    final now = DateTime.now();
    await insertTask(
      db,
      now,
      id: 'task-1',
      reminderAt: now.add(const Duration(minutes: 5)),
    );
    toast.acceptId = (_) => false;

    await service.refresh();

    final rows = await store.all();
    expect(rows.single.owner, 'app');
    expect(rows.single.degraded, isTrue);
    final task = (await db.select(db.todoItems).get()).single;
    final reminder = planFor([task], const [], now).single;
    expect(notifications.scheduledReminderKeys, contains(reminder.id));
  });

  test('one canonical occurrence produces one in-process timer', () async {
    final start = DateTime.now().add(const Duration(hours: 1));
    final reminder = _reminder(start);
    await notifications.scheduleEventReminder(
      eventId: 'event-1',
      reminderId: reminder.id,
      stableId: reminder.stableId,
      title: 'Event',
      scheduledTime: start,
    );
    await notifications.scheduleEventReminder(
      eventId: 'event-1',
      reminderId: reminder.id,
      stableId: reminder.stableId,
      title: 'Event',
      scheduledTime: start.add(const Duration(minutes: 5)),
    );
    expect(notifications.scheduledReminderKeys, hasLength(1));
  });

  test('edit, delete and complete cancel canonical and hashed keys', () async {
    final now = DateTime.now();
    final eventRepo = EventRepository(db, notifications, UndoService());
    final eventId = await eventRepo.create(
      title: 'Event',
      startTime: now.add(const Duration(hours: 2)),
      hasReminder: true,
      reminderMinutes: 10,
    );
    final event = (await db.select(db.events).get()).single;
    final eventOccurrence = ReminderOccurrence(
      kind: ReminderKind.event,
      entityId: eventId,
      occurrenceStart: event.startTime,
    );
    expect(notifications.scheduledReminderKeys, contains(eventOccurrence.key));

    await eventRepo.update(
      event.copyWith(
        title: 'Changed',
        startTime: event.startTime.add(const Duration(hours: 1)),
      ),
    );
    expect(
      notifications.scheduledReminderKeys.contains(eventOccurrence.key),
      isFalse,
    );
    expect(NotificationService.isOsOwnedId(eventOccurrence.stableId), isFalse);

    await eventRepo.delete(eventId);
    expect(notifications.scheduledReminderKeys, isEmpty);

    final taskRepo = TaskRepository(db, UndoService(), notifications);
    final taskId = await taskRepo.add(
      title: 'Task',
      reminderAt: now.add(const Duration(hours: 2)),
    );
    final task = await db.getTodoItem(taskId);
    final taskOccurrence = ReminderOccurrence(
      kind: ReminderKind.task,
      entityId: taskId,
      occurrenceStart: task!.reminderAt!,
    );
    expect(notifications.scheduledReminderKeys, contains(taskOccurrence.key));

    await taskRepo.toggle(taskId, true);
    expect(
      notifications.scheduledReminderKeys,
      isNot(contains(taskOccurrence.key)),
    );
    expect(notifications.scheduledReminderKeys, isEmpty);
  });

  test('disabling reminders cancels all keys and shows no popup', () async {
    final key = canonicalReminderKey(
      ReminderKind.event,
      'event-1',
      DateTime.now().add(const Duration(seconds: 30)),
    );
    await notifications.scheduleEventReminder(
      eventId: 'event-1',
      reminderId: key,
      stableId: stableIdForKey(key),
      title: 'Should not show',
      scheduledTime: DateTime.now().add(const Duration(milliseconds: 40)),
    );
    expect(notifications.scheduledReminderKeys, contains(key));

    await notifications.setEventRemindersEnabled(false);
    expect(notifications.scheduledReminderKeys, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(shown, isEmpty);
    await notifications.setEventRemindersEnabled(true);
  });

  test('disabling reminders also cancels legacy hashed fallbacks', () async {
    final occurrence = ReminderOccurrence(
      kind: ReminderKind.event,
      entityId: 'event-legacy',
      occurrenceStart: DateTime.now().add(const Duration(hours: 1)),
    );
    await notifications.scheduleEventReminder(
      eventId: 'event-legacy',
      reminderId: occurrence.stableId,
      stableId: occurrence.stableId,
      title: 'Legacy hash key',
      scheduledTime: DateTime.now().add(const Duration(minutes: 30)),
    );
    expect(notifications.scheduledReminderKeys, contains(occurrence.stableId));

    await notifications.setEventRemindersEnabled(false);
    expect(notifications.scheduledReminderKeys, isEmpty);
    await notifications.setEventRemindersEnabled(true);
  });

  test('snooze survives a concurrent refresh', () async {
    final now = DateTime.now();
    await insertTask(
      db,
      now,
      id: 'task-snooze',
      reminderAt: now.add(const Duration(minutes: 5)),
    );
    await service.refresh();
    final original = (await store.all()).single;

    final snooze = service.snooze(original.id, 10);
    final first = service.refresh();
    final second = service.refresh();
    await Future.wait([snooze, first, second]);

    final after = (await store.all()).single;
    expect(after.id, original.id);
    expect(after.snoozedFrom, original.id);
    expect(after.fireAt.isAfter(now), isTrue);
    expect(after.fireAt.isAfter(original.fireAt), isTrue);
  });

  test(
    'startup reconcile returns confirmed ids before fallbacks are armed',
    () async {
      final now = DateTime.now();
      await insertTask(
        db,
        now,
        id: 'task-1',
        reminderAt: now.add(const Duration(minutes: 5)),
      );
      await insertEvent(db, now, id: 'event-1');

      final confirmed = await service.reconcileStartup();
      expect(confirmed, hasLength(2));

      await EventRepository(
        db,
        notifications,
        UndoService(),
      ).restoreFutureReminders(osConfirmedIds: confirmed);
      await TaskRepository(
        db,
        UndoService(),
        notifications,
      ).restoreAllReminders(osConfirmedIds: confirmed);
      expect(notifications.scheduledReminderKeys, isEmpty);
    },
  );

  test('missed reminders are returned once and marked delivered', () async {
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    final occurrence = ReminderOccurrence(
      kind: ReminderKind.task,
      entityId: 't1',
      occurrenceStart: start,
    );
    await store.replaceAll([
      PlatformReminderWrite(
        id: occurrence.stableId,
        kind: 'task',
        entityId: 't1',
        occurrenceStart: start,
        fireAt: start,
        owner: 'app',
        degraded: true,
      ),
    ]);
    final missed = await service.takeMissed();
    expect(missed.single.id, occurrence.stableId);
    expect(await service.takeMissed(), isEmpty);
  });

  test('badge counts overdue and due-today open tasks', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 12);
    final tomorrow = DateTime(now.year, now.month, now.day + 1, 12);
    Future<void> insert(String id, DateTime? due, {bool completed = false}) =>
        db
            .into(db.todoItems)
            .insert(
              TodoItemsCompanion.insert(
                id: id,
                title: id,
                createdAt: now,
                dueDate: Value(due),
                completed: Value(completed),
              ),
            );
    await insert('overdue', now.subtract(const Duration(days: 2)));
    await insert('today', today);
    await insert('tomorrow', tomorrow);
    await insert('done', today, completed: true);

    await service.refresh();

    expect(toast.badge, 2);
  });

  test('snooze keeps the original id and persists snoozed_from', () async {
    final now = DateTime.now();
    await insertTask(db, now, id: 'task-snooze', title: 'Snooze me');
    await service.refresh();
    final scheduled = await store.all();
    expect(scheduled, hasLength(1));
    final originalId = scheduled.single.id;

    await service.snooze(originalId, 10);

    final after = await store.all();
    expect(after.single.id, originalId);
    expect(after.single.snoozedFrom, originalId);
    expect(after.single.fireAt.isAfter(now), isTrue);
    expect(toast.scheduled.last['id'], originalId);
  });
}

Future<void> insertTask(
  AppDatabase db,
  DateTime now, {
  required String id,
  String title = 'Task',
  DateTime? reminderAt,
}) => db
    .into(db.todoItems)
    .insert(
      TodoItemsCompanion.insert(
        id: id,
        title: title,
        createdAt: now,
        reminderAt: Value(reminderAt ?? now.add(const Duration(minutes: 5))),
      ),
    );

Future<void> insertEvent(AppDatabase db, DateTime now, {required String id}) =>
    db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: id,
            title: 'Event',
            startTime: now.add(const Duration(minutes: 20)),
            hasReminder: const Value(true),
            reminderMinutes: const Value(10),
          ),
        );

List<PlannedReminder> planFor(
  List<TodoItem> tasks,
  List<Event> events,
  DateTime now,
) => ReminderPlanner.plan(<PlannedSource>[
  ...ReminderPlanner.sourcesForTasks(tasks, now: now),
  ...ReminderPlanner.sourcesForEvents(events, now: now),
], now: now);

PlannedReminder _reminder(DateTime occurrenceStart, {DateTime? fireAt}) {
  final occurrence = ReminderOccurrence(
    kind: ReminderKind.task,
    entityId: 't1',
    occurrenceStart: occurrenceStart,
  );
  return PlannedReminder(
    kind: ReminderKind.task,
    entityId: 't1',
    id: occurrence.key,
    occurrenceStart: occurrenceStart,
    fireAt: fireAt ?? occurrenceStart,
    title: 'Task',
    body: 'Task reminder',
  );
}
