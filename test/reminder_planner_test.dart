import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/features/mobile/data/reminder_planner.dart';

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
  final now = DateTime(2026, 10, 28, 8);

  group('ReminderPlanner.plan', () {
    test('plans one reminder ahead of a future event', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 28, 9)),
      ], now: now);

      expect(plan, hasLength(1));
      expect(plan.single.fireAt, DateTime(2026, 10, 28, 8, 50));
      expect(plan.single.title, 'Dentist');
      expect(plan.single.body, 'Starts in 10 min');
      expect(plan.single.eventId, 'e1');
    });

    test('skips events without a reminder', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 28, 9), hasReminder: false),
      ], now: now);

      expect(plan, isEmpty);
    });

    test('skips a reminder whose time has already passed', () {
      final plan = ReminderPlanner.plan([
        // Starts in 5 minutes, but the reminder was due 5 minutes ago.
        event(start: DateTime(2026, 10, 28, 8, 5)),
        event(id: 'old', start: DateTime(2026, 10, 1, 9)),
      ], now: now);

      expect(plan, isEmpty);
    });

    test('a reminder at the start time fires then and says so', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 28, 9), minutes: 0),
      ], now: now);

      expect(plan.single.fireAt, DateTime(2026, 10, 28, 9));
      expect(plan.single.body, 'Starting now');
    });

    test('skips an unknown recurrence rule instead of failing', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 28, 9), rule: 'every-blue-moon'),
      ], now: now);

      expect(plan, isEmpty);
    });

    test('a daily event gets one reminder per day inside the window', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 20, 9), rule: 'daily'),
      ], now: now);

      // 28 Oct 08:50 up to 26 Nov 08:50; 27 Nov 08:50 is after the window.
      expect(plan, hasLength(30));
      expect(plan.first.fireAt, DateTime(2026, 10, 28, 8, 50));
      expect(plan.last.fireAt, DateTime(2026, 11, 26, 8, 50));
      for (var i = 0; i < plan.length; i++) {
        expect(plan[i].fireAt, DateTime(2026, 10, 28 + i, 8, 50));
      }
      expect(plan.map((r) => r.id).toSet(), hasLength(plan.length));
    });

    test('a weekly event started in the past continues from today', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 14, 9), rule: 'weekly'),
      ], now: now);

      expect(plan.map((r) => r.fireAt), [
        DateTime(2026, 10, 28, 8, 50),
        DateTime(2026, 11, 4, 8, 50),
        DateTime(2026, 11, 11, 8, 50),
        DateTime(2026, 11, 18, 8, 50),
        DateTime(2026, 11, 25, 8, 50),
      ]);
    });

    test('a recurring event whose reminder today passed starts tomorrow', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 10, 20, 7), rule: 'daily'),
      ], now: now);

      expect(plan.first.fireAt, DateTime(2026, 10, 29, 6, 50));
    });

    test('limits one event to perEventLimit reminders', () {
      final plan = ReminderPlanner.plan(
        [event(start: DateTime(2026, 10, 28, 9), rule: 'daily')],
        now: now,
        perEventLimit: 3,
      );

      expect(plan, hasLength(3));
    });

    test('keeps the earliest reminders when over the total limit', () {
      final plan = ReminderPlanner.plan(
        [
          event(id: 'a', start: DateTime(2026, 10, 28, 9), rule: 'daily'),
          event(id: 'b', start: DateTime(2026, 10, 28, 10), rule: 'daily'),
        ],
        now: now,
        totalLimit: 4,
      );

      expect(plan.map((r) => r.fireAt), [
        DateTime(2026, 10, 28, 8, 50),
        DateTime(2026, 10, 28, 9, 50),
        DateTime(2026, 10, 29, 8, 50),
        DateTime(2026, 10, 29, 9, 50),
      ]);
    });

    test('is ordered by time across events', () {
      final plan = ReminderPlanner.plan([
        event(id: 'late', start: DateTime(2026, 10, 28, 15)),
        event(id: 'early', start: DateTime(2026, 10, 28, 9)),
        event(id: 'tomorrow', start: DateTime(2026, 10, 29, 9)),
      ], now: now);

      expect(plan.map((r) => r.eventId), ['early', 'late', 'tomorrow']);
    });

    test('ignores events beyond the window', () {
      final plan = ReminderPlanner.plan([
        event(start: DateTime(2026, 12, 25, 9)),
      ], now: now);

      expect(plan, isEmpty);
    });
  });

  group('ReminderPlanner.bodyFor', () {
    test('words the lead time', () {
      expect(ReminderPlanner.bodyFor(0), 'Starting now');
      expect(ReminderPlanner.bodyFor(5), 'Starts in 5 min');
      expect(ReminderPlanner.bodyFor(60), 'Starts in 1 h');
      expect(ReminderPlanner.bodyFor(90), 'Starts in 90 min');
      expect(ReminderPlanner.bodyFor(120), 'Starts in 2 h');
    });
  });

  test('PlannedReminder.toMap carries epoch milliseconds', () {
    final plan = ReminderPlanner.plan([
      event(start: DateTime(2026, 10, 28, 9)),
    ], now: now);

    expect(plan.single.toMap(), {
      'id': plan.single.id,
      'at': DateTime(2026, 10, 28, 8, 50).millisecondsSinceEpoch,
      'title': 'Dentist',
      'body': 'Starts in 10 min',
    });
  });
}
