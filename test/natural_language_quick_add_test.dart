import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/natural_language_quick_add.dart';
import 'package:locus_planner/core/utils/recurrence.dart';

void main() {
  // Wednesday, 4 November 2026, 10:00 local time.
  final now = DateTime(2026, 11, 4, 10);

  NaturalLanguageCapture parse(String input) =>
      NaturalLanguageQuickAdd.parse(input, now: now);

  test('parses a relative day and an explicit time', () {
    final result = parse('Team standup tomorrow 9am');
    expect(result.title, 'Team standup');
    expect(result.date, DateTime(2026, 11, 5, 9));
    expect(result.allDay, isFalse);
    expect(result.hints, containsAll(<String>['Tomorrow', '09:00']));
  });

  test('parses a weekday repeat and anchors it to the next weekday', () {
    final result = parse('Review draft every Monday');
    expect(result.title, 'Review draft');
    expect(result.recurrenceRule, Recurrence.weekly);
    expect(result.date, DateTime(2026, 11, 9));
    expect(result.allDay, isTrue);
    expect(result.hints, contains('Every Monday'));
  });

  test('parses monthly repeats without an explicit day', () {
    final result = parse('Pay rent every month');
    expect(result.title, 'Pay rent');
    expect(result.recurrenceRule, Recurrence.monthly);
    expect(result.date, DateTime(2026, 11, 4));
    expect(result.allDay, isTrue);
  });

  test('parses in N days', () {
    final result = parse('Submit report in 3 days');
    expect(result.title, 'Submit report');
    expect(result.date, DateTime(2026, 11, 7));
    expect(result.hints, contains('In 3 days'));
  });

  test('parses a 24-hour time later today', () {
    final result = parse('Call mom at 14:30');
    expect(result.title, 'Call mom');
    expect(result.date, DateTime(2026, 11, 4, 14, 30));
    expect(result.allDay, isFalse);
  });

  test('a time that already passed moves to tomorrow', () {
    final result = parse('Call mom at 9am');
    expect(result.title, 'Call mom');
    expect(result.date, DateTime(2026, 11, 5, 9));
  });

  test('plain text stays a plain title', () {
    final result = parse('Buy milk');
    expect(result.title, 'Buy milk');
    expect(result.date, isNull);
    expect(result.recurrenceRule, isNull);
    expect(result.hasDetails, isFalse);
  });

  test('parses tags, priority and a date together', () {
    final result = parse('Write proposal #work !!! tomorrow');
    expect(result.title, 'Write proposal');
    expect(result.tags, <String>['work']);
    expect(result.priority, QuickAddPriority.high);
    expect(result.date, DateTime(2026, 11, 5));
    expect(result.allDay, isTrue);
    expect(result.hints, containsAll(<String>['High priority', '#work']));
  });

  test('parses a project hint', () {
    final result = parse('Lunch @ProjectX tomorrow noon');
    expect(result.title, 'Lunch');
    expect(result.projectHint, 'ProjectX');
    expect(result.date, DateTime(2026, 11, 5, 12));
    expect(result.hints, contains('@ProjectX'));
  });

  test('parses weekday repeats with a time', () {
    final result = parse('Standup weekdays 9am');
    expect(result.title, 'Standup');
    expect(result.recurrenceRule, Recurrence.weekdays);
    expect(result.date, DateTime(2026, 11, 5, 9));
  });

  test('parses every other week', () {
    final result = parse('Retro every other week');
    expect(result.title, 'Retro');
    expect(result.recurrenceRule, Recurrence.biweekly);
  });

  test('parses next Monday', () {
    final result = parse('Plan sprint next Monday');
    expect(result.title, 'Plan sprint');
    expect(result.date, DateTime(2026, 11, 9));
  });

  test('parses next week as a calendar week offset', () {
    final result = parse('Plan sprint next week');
    expect(result.title, 'Plan sprint');
    expect(result.date, DateTime(2026, 11, 11));
  });

  test('combines a weekday with a later time', () {
    final result = parse('Dinner at 7pm on Friday');
    expect(result.title, 'Dinner');
    expect(result.date, DateTime(2026, 11, 6, 19));
  });

  test('med and low priorities are recognised', () {
    expect(parse('Fix typo !!').priority, QuickAddPriority.medium);
    expect(parse('Water plants !').priority, QuickAddPriority.low);
    expect(parse('Fix typo high priority').priority, QuickAddPriority.high);
  });

  test('unsupported every N days is left in the title', () {
    final result = parse('Stretch every 3 days');
    expect(result.title, 'Stretch every 3 days');
    expect(result.recurrenceRule, isNull);
  });
}
