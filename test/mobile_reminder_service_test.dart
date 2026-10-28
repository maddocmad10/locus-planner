import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/mobile/data/mobile_reminder_service.dart';

import 'helpers/fake_reminder_platform.dart';

void main() {
  late AppDatabase db;
  late FakeReminderPlatform platform;
  late MobileReminderService service;

  setUp(() {
    AppClock.now = () => DateTime(2026, 10, 28, 8);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    platform = FakeReminderPlatform();
    service = MobileReminderService(db, platform);
  });

  tearDown(() async {
    AppClock.now = DateTime.now;
    await service.stop();
    await db.close();
  });

  Future<void> addEvent(
    String id, {
    required DateTime start,
    bool reminder = true,
    int minutes = 15,
  }) => db
      .into(db.events)
      .insert(
        EventsCompanion.insert(
          id: id,
          title: 'Event $id',
          startTime: start,
          hasReminder: Value(reminder),
          reminderMinutes: Value(minutes),
        ),
      );

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: 'condition was not met in time');
  }

  test('refresh sends the upcoming reminders to the phone', () async {
    await addEvent('a', start: DateTime(2026, 10, 28, 9));

    await service.refresh();

    final sent = platform.replaced.last;
    expect(sent, hasLength(1));
    expect(sent.single.title, 'Event a');
    expect(sent.single.fireAt, DateTime(2026, 10, 28, 8, 45));
    expect(sent.single.body, 'Starts in 15 min');
  });

  test('an event added later is picked up by the watcher', () async {
    service.start();
    await until(() => platform.replaced.isNotEmpty);
    expect(platform.replaced.last, isEmpty);

    await addEvent('a', start: DateTime(2026, 10, 28, 9));

    await until(() => platform.replaced.last.isNotEmpty);
    expect(platform.replaced.last.single.eventId, 'a');
  });

  test('rows written by a sync are picked up like any other', () async {
    service.start();
    await until(() => platform.replaced.isNotEmpty);

    // The sync applier writes straight to the table and then announces it.
    final startSeconds =
        DateTime(2026, 10, 28, 12).millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT INTO events (id, title, start_time, has_reminder, '
      'reminder_minutes) VALUES (?, ?, ?, 1, 10)',
      ['from-desktop', 'From desktop', startSeconds],
    );
    db.markTablesUpdated([db.events]);

    await until(() => platform.replaced.last.isNotEmpty);
    expect(platform.replaced.last.single.eventId, 'from-desktop');
  });

  test('a deleted event loses its reminder', () async {
    await addEvent('a', start: DateTime(2026, 10, 28, 9));
    await service.refresh();
    expect(platform.replaced.last, hasLength(1));

    await (db.delete(db.events)..where((t) => t.id.equals('a'))).go();
    await service.refresh();

    expect(platform.replaced.last, isEmpty);
  });

  test('turning reminders off cancels everything and on restores it', () async {
    await addEvent('a', start: DateTime(2026, 10, 28, 9));
    await service.refresh();
    final sentBefore = platform.replaced.length;

    await service.setEnabled(false);

    expect(await service.isEnabled(), isFalse);
    expect(platform.cancelled, 1);
    expect(platform.replaced.length, sentBefore);

    await service.setEnabled(true);

    expect(await service.isEnabled(), isTrue);
    expect(platform.replaced.last, hasLength(1));
  });

  test('reminders are on until the user switches them off', () async {
    expect(await service.isEnabled(), isTrue);
  });

  test('a failing phone does not break refresh or the next one', () async {
    await addEvent('a', start: DateTime(2026, 10, 28, 9));
    platform.failing = true;

    await service.refresh();
    expect(platform.replaced, isEmpty);

    platform.failing = false;
    await service.refresh();
    expect(platform.replaced.last, hasLength(1));
  });

  test('a burst of refreshes costs at most two passes', () async {
    await addEvent('a', start: DateTime(2026, 10, 28, 9));

    await Future.wait([for (var i = 0; i < 6; i++) service.refresh()]);

    expect(platform.replaced.length, lessThanOrEqualTo(2));
    expect(platform.replaced.last, hasLength(1));
  });

  test('stop ends the watcher', () async {
    service.start();
    await until(() => platform.replaced.isNotEmpty);
    await service.stop();
    final count = platform.replaced.length;

    await addEvent('a', start: DateTime(2026, 10, 28, 9));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(platform.replaced.length, count);
  });
}
