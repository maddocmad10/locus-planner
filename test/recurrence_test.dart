import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/core/db/app_database.dart';

Event _event(DateTime start, String rule) => Event(
  id: 'e1',
  title: 'Event',
  description: null,
  startTime: start,
  endTime: start.add(const Duration(hours: 1)),
  category: 'general',
  hasReminder: false,
  reminderMinutes: 10,
  recurrenceRule: rule,
);

void main() {

  test('invalid recurrence rules are rejected instead of looping forever', () {
    expect(Recurrence.isValidRule('banana'), isFalse);
    expect(
      Recurrence.nextRemindableStart(
        start: DateTime(2026, 10, 5, 9),
        rule: 'banana',
        reminderMinutes: 10,
        now: DateTime(2026, 10, 5, 8),
      ),
      isNull,
    );
    expect(
      Recurrence.expand(
        _event(DateTime(2026, 10, 5, 9), 'banana'),
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
      ),
      hasLength(1),
    );
  });

  test('negative reminder minutes are rejected', () {
    expect(
      Recurrence.nextRemindableStart(
        start: DateTime(2026, 10, 5, 9),
        rule: Recurrence.daily,
        reminderMinutes: -1,
        now: DateTime(2026, 10, 5, 8),
      ),
      isNull,
    );
  });

  test('daily recurrence finds next occurrence', () {
    final start = DateTime(2026, 10, 5, 9);
    expect(
      Recurrence.next(start, Recurrence.daily, from: DateTime(2026, 10, 5, 10)),
      DateTime(2026, 10, 6, 9),
    );
  });

  test('weekdays skips Saturday and Sunday', () {
    final friday = DateTime(2026, 10, 9, 9);
    expect(
      Recurrence.next(friday, Recurrence.weekdays, from: friday),
      DateTime(2026, 10, 12, 9),
    );
  });

  test('monthly recurrence clamps invalid month days', () {
    final jan31 = DateTime(2026, 1, 31, 9);
    expect(
      Recurrence.next(jan31, Recurrence.monthly, from: jan31),
      DateTime(2026, 2, 28, 9),
    );
  });

  test('monthly recurrence keeps the original day across clamped months', () {
    final start = DateTime(2026, 1, 31, 9);
    expect(Recurrence.next(start, Recurrence.monthly, from: DateTime(2026, 2, 28, 10)), DateTime(2026, 3, 31, 9));
    expect(Recurrence.next(start, Recurrence.monthly, from: DateTime(2026, 3, 31, 10)), DateTime(2026, 4, 30, 9));
    expect(Recurrence.next(start, Recurrence.monthly, from: DateTime(2026, 4, 30, 10)), DateTime(2026, 5, 31, 9));
  });

  test('yearly recurrence restores Feb 29 on leap years', () {
    final start = DateTime(2024, 2, 29, 9);
    expect(Recurrence.next(start, Recurrence.yearly, from: DateTime(2025, 2, 28, 10)), DateTime(2026, 2, 28, 9));
    expect(Recurrence.next(start, Recurrence.yearly, from: DateTime(2026, 2, 28, 10)), DateTime(2027, 2, 28, 9));
    expect(Recurrence.next(start, Recurrence.yearly, from: DateTime(2027, 2, 28, 10)), DateTime(2028, 2, 29, 9));
  });

  test('daily recurrence can jump more than three years', () {
    final start = DateTime(2020, 1, 1, 9);
    expect(Recurrence.next(start, Recurrence.daily, from: DateTime(2026, 1, 1, 10)), DateTime(2026, 1, 2, 9));
    final expanded = Recurrence.expand(
      _event(start, Recurrence.daily),
      DateTime(2026, 1, 1),
      DateTime(2026, 1, 3),
    );
    expect(expanded.map((e) => e.startTime), [DateTime(2026, 1, 1, 9), DateTime(2026, 1, 2, 9)]);
  });

  test('recurring expansion excludes an earlier same-day occurrence when from is mid-day', () {
    final start = DateTime(2026, 10, 5, 9);
    final expanded = Recurrence.expand(
      _event(start, Recurrence.daily),
      DateTime(2026, 10, 5, 12),
      DateTime(2026, 10, 7),
    );
    expect(expanded.map((e) => e.startTime), [
      DateTime(2026, 10, 6, 9),
    ]);
  });

  test('recurring expansion uses an exclusive upper bound', () {
    final start = DateTime(2026, 10, 5, 9);
    final expanded = Recurrence.expand(_event(start, Recurrence.daily), start, DateTime(2026, 10, 6, 9));
    expect(expanded, hasLength(1));
  });

  test('reminder skips an occurrence whose alert time has passed', () {
    final start = DateTime(2026, 10, 5, 9);
    expect(
      Recurrence.nextRemindableStart(
        start: start,
        rule: Recurrence.daily,
        reminderMinutes: 10,
        now: DateTime(2026, 10, 5, 8, 55),
      ),
      DateTime(2026, 10, 6, 9),
    );
    expect(
      Recurrence.nextRemindableStart(
        start: start,
        rule: Recurrence.daily,
        reminderMinutes: 10,
        now: DateTime(2026, 10, 5, 8, 40),
      ),
      DateTime(2026, 10, 5, 9),
    );
  });

  test('non-recurring reminder is dropped once its alert time has passed', () {
    final start = DateTime(2026, 10, 5, 9);
    expect(
      Recurrence.nextRemindableStart(
        start: start,
        rule: null,
        reminderMinutes: 10,
        now: DateTime(2026, 10, 5, 8, 55),
      ),
      isNull,
    );
  });

  test('maps planner rules to ICS RRULE values', () {
    expect(Recurrence.toRRule(Recurrence.weekdays), 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR');
    expect(Recurrence.toRRule(Recurrence.biweekly), 'FREQ=WEEKLY;INTERVAL=2');
    expect(Recurrence.toRRule(null), isNull);
  });
}
