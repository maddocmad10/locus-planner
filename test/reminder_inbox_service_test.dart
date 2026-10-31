import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/notification_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/events/data/reminder_inbox_service.dart';

Event event({
  String id = 'e1',
  String title = 'Dentist',
  required DateTime start,
  bool hasReminder = true,
  int minutes = 10,
  String? rule,
}) => Event(
  id: id,
  title: title,
  description: null,
  startTime: start,
  endTime: null,
  category: 'general',
  hasReminder: hasReminder,
  reminderMinutes: minutes,
  recurrenceRule: rule,
);

void main() {
  group('ReminderInboxService.computeMissedReminders', () {
    test('finds a reminder that came due while the app was closed', () {
      final result = ReminderInboxService.computeMissedReminders(
        [event(start: DateTime(2026, 10, 28, 9))],
        from: DateTime(2026, 10, 28, 8, 30),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result, hasLength(1));
      expect(result.single.reminderAt, DateTime(2026, 10, 28, 8, 50));
      expect(result.single.occurrenceStart, DateTime(2026, 10, 28, 9));
      expect(result.single.title, 'Dentist');
    });

    test('ignores a reminder that was already due before the window', () {
      final result = ReminderInboxService.computeMissedReminders(
        [event(start: DateTime(2026, 10, 28, 9))],
        from: DateTime(2026, 10, 28, 8, 55),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result, isEmpty);
    });

    test('ignores a missed reminder older than the retention window', () {
      final result = ReminderInboxService.computeMissedReminders(
        [event(start: DateTime(2026, 9, 1, 9))],
        from: DateTime(2026, 8, 31, 8),
        now: DateTime(2026, 10, 28, 10),
      );

      // The caller caps `from`; this also proves an old occurrence is not
      // resurrected merely because the event is still stored.
      expect(
        ReminderInboxService.computeMissedReminders(
          [event(start: DateTime(2026, 9, 1, 9))],
          from: DateTime(2026, 10, 21, 10),
          now: DateTime(2026, 10, 28, 10),
        ),
        isEmpty,
      );
      expect(result, hasLength(1));
    });

    test(
      'includes a reminder due before now for an event that starts soon',
      () {
        final result = ReminderInboxService.computeMissedReminders(
          [event(start: DateTime(2026, 10, 28, 10, 5))],
          from: DateTime(2026, 10, 28, 9),
          now: DateTime(2026, 10, 28, 10),
        );

        expect(result.single.reminderAt, DateTime(2026, 10, 28, 9, 55));
      },
    );

    test('does not include a reminder that is still in the future', () {
      final result = ReminderInboxService.computeMissedReminders(
        [event(start: DateTime(2026, 10, 28, 11))],
        from: DateTime(2026, 10, 28, 9),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result, isEmpty);
    });

    test('ignores events without a reminder', () {
      final result = ReminderInboxService.computeMissedReminders(
        [event(start: DateTime(2026, 10, 28, 9), hasReminder: false)],
        from: DateTime(2026, 10, 28, 8),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result, isEmpty);
    });

    test('expands every missed occurrence of a recurring event', () {
      final result = ReminderInboxService.computeMissedReminders(
        [
          event(
            start: DateTime(2026, 10, 26, 9),
            rule: 'daily',
            title: 'Standup',
          ),
        ],
        from: DateTime(2026, 10, 27, 8),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result, hasLength(2));
      expect(result.first.occurrenceStart, DateTime(2026, 10, 28, 9));
      expect(result.last.occurrenceStart, DateTime(2026, 10, 27, 9));
      expect(result.map((item) => item.key).toSet(), hasLength(2));
    });

    test('lists the most recently missed reminder first', () {
      final result = ReminderInboxService.computeMissedReminders(
        [
          event(id: 'early', start: DateTime(2026, 10, 28, 9)),
          event(id: 'late', start: DateTime(2026, 10, 28, 9, 30)),
        ],
        from: DateTime(2026, 10, 28, 8),
        now: DateTime(2026, 10, 28, 10),
      );

      expect(result.map((item) => item.eventId), ['late', 'early']);
    });
  });

  group('ReminderInboxService persistence', () {
    late AppDatabase db;
    late NotificationService notifications;
    late List<String> shown;
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 10, 28, 10);
      AppClock.now = () => now;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      shown = [];
      notifications = NotificationService(
        db: db,
        showOverride: ({required title, required body}) async {
          shown.add(title);
        },
      );
      await notifications.init();
      await db.setSetting(
        AppDatabase.remindersLastRunningSettingKey,
        DateTime(2026, 10, 28, 8).toIso8601String(),
      );
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'e1',
              title: 'Dentist',
              startTime: DateTime(2026, 10, 28, 9),
              hasReminder: const Value(true),
            ),
          );
    });

    tearDown(() async {
      AppClock.now = DateTime.now;
      notifications.dispose();
      await db.close();
    });

    test('detects a missed reminder and keeps it across restarts', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();

      expect(service.current, hasLength(1));
      expect(service.current.single.title, 'Dentist');
      expect(
        await db.getSetting(AppDatabase.remindersPendingSettingKey),
        contains('Dentist'),
      );
      service.dispose();

      now = DateTime(2026, 10, 28, 12);
      final restarted = ReminderInboxService(db, notifications, now: () => now);
      await restarted.start();

      expect(restarted.current, hasLength(1));
      expect(
        restarted.current.single.reminderAt,
        DateTime(2026, 10, 28, 8, 50),
      );
      restarted.dispose();
    });

    test('dismiss removes the reminder permanently', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();

      await service.dismiss(service.current.single);

      expect(service.current, isEmpty);
      expect(await db.getSetting(AppDatabase.remindersPendingSettingKey), '[]');

      service.dispose();
      now = DateTime(2026, 10, 28, 12);
      final restarted = ReminderInboxService(db, notifications, now: () => now);
      await restarted.start();
      expect(restarted.current, isEmpty);
      restarted.dispose();
    });

    test('snoozing hides the reminder and persists the snooze', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();

      await service.snooze(service.current.single, const Duration(minutes: 10));

      expect(service.current, isEmpty);
      final snoozed = await db.getSetting(
        AppDatabase.remindersSnoozedSettingKey,
      );
      expect(snoozed, contains('snoozeUntil'));
      expect(snoozed, contains('Dentist'));
      service.dispose();
    });

    test('an expired snooze returns to the missed list', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();
      await service.snooze(service.current.single, const Duration(minutes: 10));
      service.dispose();

      now = DateTime(2026, 10, 28, 10, 20);
      final restarted = ReminderInboxService(db, notifications, now: () => now);
      await restarted.start();

      expect(restarted.current, hasLength(1));
      expect(await db.getSetting(AppDatabase.remindersSnoozedSettingKey), '[]');
      restarted.dispose();
    });

    test(
      'rememberMissed adds a reminder that became late at runtime',
      () async {
        final service = ReminderInboxService(db, notifications, now: () => now);
        await service.start();

        await service.rememberMissed(
          eventId: 'e2',
          title: 'Laptop was asleep',
          occurrenceStart: DateTime(2026, 10, 28, 10, 5),
          reminderAt: DateTime(2026, 10, 28, 9, 55),
        );

        expect(service.current, hasLength(2));
        expect(service.current.first.title, 'Laptop was asleep');
        expect(
          await db.getSetting(AppDatabase.remindersPendingSettingKey),
          contains('Laptop was asleep'),
        );
        service.dispose();
      },
    );

    test('drops a pending reminder when its event no longer has one', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();
      expect(service.current, hasLength(1));
      service.dispose();

      await (db.delete(db.events)..where((t) => t.id.equals('e1'))).go();
      now = DateTime(2026, 10, 28, 12);
      final restarted = ReminderInboxService(db, notifications, now: () => now);
      await restarted.start();

      expect(restarted.current, isEmpty);
      expect(await db.getSetting(AppDatabase.remindersPendingSettingKey), '[]');
      restarted.dispose();
    });

    test(
      'a corrupt stored inbox is ignored instead of failing startup',
      () async {
        await db.setSetting(
          AppDatabase.remindersPendingSettingKey,
          '{not json',
        );
        final service = ReminderInboxService(db, notifications, now: () => now);
        await service.start();

        expect(service.current, hasLength(1));
        expect(service.current.single.title, 'Dentist');
        service.dispose();
      },
    );

    test(
      'disabled reminders hide the inbox until they are switched on',
      () async {
        final service = ReminderInboxService(db, notifications, now: () => now);
        await service.start();
        await service.snooze(
          service.current.single,
          const Duration(minutes: 10),
        );
        service.dispose();

        await notifications.setEventRemindersEnabled(false);
        now = DateTime(2026, 10, 28, 10, 30);
        final restarted = ReminderInboxService(
          db,
          notifications,
          now: () => now,
        );
        await restarted.start();

        expect(restarted.current, isEmpty);
        // The expired snooze is kept while reminders are off instead of being
        // silently dropped or shown against the user's choice.
        expect(
          await db.getSetting(AppDatabase.remindersSnoozedSettingKey),
          contains('Dentist'),
        );

        await notifications.setEventRemindersEnabled(true);
        await restarted.rearmSnoozes();

        expect(restarted.current, hasLength(1));
        expect(restarted.current.single.title, 'Dentist');
        expect(
          await db.getSetting(AppDatabase.remindersSnoozedSettingKey),
          '[]',
        );
        restarted.dispose();
      },
    );

    test('markStopped records the end of the session', () async {
      final service = ReminderInboxService(db, notifications, now: () => now);
      await service.start();
      now = DateTime(2026, 10, 28, 10, 45);
      await service.markStopped();

      expect(
        await db.getSetting(AppDatabase.remindersLastRunningSettingKey),
        now.toIso8601String(),
      );
      service.dispose();
    });

    test('reminder runtime state stays out of backups', () {
      expect(
        AppDatabase.isTransientSetting(
          AppDatabase.remindersLastRunningSettingKey,
        ),
        isTrue,
      );
      expect(
        AppDatabase.isTransientSetting(AppDatabase.remindersPendingSettingKey),
        isTrue,
      );
      expect(
        AppDatabase.isTransientSetting(AppDatabase.remindersSnoozedSettingKey),
        isTrue,
      );
    });
  });
}
