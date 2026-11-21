import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/reminders/platform_reminder_store.dart';
import 'package:locus_planner/core/models/reminder_kind.dart';
import 'package:locus_planner/core/reminders/reminder_planner.dart';
import 'package:locus_planner/core/reminders/windows_reminder_service.dart';
import 'package:locus_planner/core/reminders/windows_toast_platform.dart';

class _FakeToastPlatform extends WindowsToastPlatform {
  final scheduled = <Map<String, Object>>[];
  final cancelled = <Set<String>>[];
  int badge = 0;

  @override
  Future<void> setBadge(int count) async {
    badge = count;
  }

  @override
  Future<bool> schedule(List<Map<String, Object>> items) async {
    scheduled.addAll(items);
    return true;
  }

  @override
  Future<void> cancelAllExcept(Set<String> keepIds) async {
    cancelled.add(keepIds);
  }

  @override
  Future<List<String>> listScheduled() async => [
    for (final item in scheduled) item['id']! as String,
  ];
}

void main() {
  late AppDatabase db;
  late _FakeToastPlatform toast;
  late WindowsReminderService service;
  late PlatformReminderStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    toast = _FakeToastPlatform();
    store = PlatformReminderStore(db);
    service = WindowsReminderService(db, toastPlatform: toast, store: store);
  });

  tearDown(() => db.close());

  test('stable ids are 16 characters and change with the fire time', () {
    final now = DateTime.utc(2026, 11, 20, 9);
    final reminder = _reminder(now);
    final first = stableReminderId(reminder);
    final second = stableReminderId(
      _reminder(now.add(const Duration(minutes: 1))),
    );
    expect(first, hasLength(16));
    expect(first, stableReminderId(_reminder(now)));
    expect(first, isNot(second));
  });

  test('refresh schedules tasks and events and records local state', () async {
    final now = DateTime.now();
    await db.setSetting(AppDatabase.syncDeviceIdSettingKey, 'desktop');
    await db
        .into(db.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: 'task-1',
            title: 'Task',
            createdAt: now,
            reminderAt: Value(now.add(const Duration(minutes: 5))),
          ),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'event-1',
            title: 'Event',
            startTime: now.add(const Duration(minutes: 20)),
            hasReminder: const Value(true),
            reminderMinutes: const Value(10),
          ),
        );

    await service.refresh();

    final tasks = await db.select(db.todoItems).get();
    final events = await db.select(db.events).get();
    expect(tasks, hasLength(1));
    expect(events, hasLength(1));
    final sources = <PlannedSource>[
      ...ReminderPlanner.sourcesForTasks(tasks, now: now),
      ...ReminderPlanner.sourcesForEvents(events, now: now),
    ];
    expect(sources, hasLength(2));
    expect(toast.scheduled, hasLength(2));
    expect(
      toast.scheduled.map((item) => item['title']),
      containsAll(['Task', 'Event']),
    );
    expect(await store.all(), hasLength(2));
  });

  test('hide titles never sends the title or body to the OS', () async {
    final now = DateTime.now();
    await db.setSetting(AppDatabase.hideNotificationTitlesSettingKey, '1');
    await db
        .into(db.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: 'task-1',
            title: 'Secret title',
            createdAt: now,
            reminderAt: Value(now.add(const Duration(minutes: 5))),
          ),
        );

    await service.refresh();

    expect(toast.scheduled.single['title'], 'Locus reminder');
    expect(toast.scheduled.single['body'], '');
  });

  test('missed reminders are returned once and marked delivered', () async {
    await db.customStatement(
      'INSERT INTO platform_reminder_state '
      '(id, kind, entity_id, fire_at, scheduled_at) '
      "VALUES ('missed', 'task', 't1', ?, ?)",
      [DateTime.now().millisecondsSinceEpoch - 60000, 1],
    );
    final missed = await service.takeMissed();
    expect(missed.single.id, 'missed');
    expect(await service.takeMissed(), isEmpty);
  });

  test('snooze keeps the original id and persists snoozed_from', () async {
    final now = DateTime.now();
    await db
        .into(db.todoItems)
        .insert(
          TodoItemsCompanion.insert(
            id: 'task-snooze',
            title: 'Snooze me',
            createdAt: now,
            reminderAt: Value(now.add(const Duration(minutes: 5))),
          ),
        );
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

PlannedReminder _reminder(DateTime at) => PlannedReminder(
  kind: ReminderKind.task,
  entityId: 't1',
  id: 'task:t1@${at.millisecondsSinceEpoch}',
  fireAt: at,
  title: 'Task',
  body: 'Task reminder',
);
