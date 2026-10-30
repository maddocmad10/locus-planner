import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/features/mobile/data/today_agenda.dart';

Event _event({
  required String id,
  required DateTime start,
  String? rule,
  String title = 'Event',
}) => Event(
  id: id,
  title: title,
  startTime: start,
  category: 'general',
  hasReminder: false,
  reminderMinutes: 10,
  recurrenceRule: rule,
);

void main() {
  final today = DateTime(2026, 10, 28);

  test('a recurring event appears on every occurrence, not just its start', () {
    final event = _event(
      id: 'standup',
      title: 'Standup',
      start: DateTime(2026, 10, 26, 9),
      rule: Recurrence.daily,
    );

    final entries = agendaForDay([event], today);

    expect(entries, hasLength(1));
    expect(entries.single.start, DateTime(2026, 10, 28, 9));
    expect(entries.single.event.id, 'standup');
    expect(entries.single.isRecurring, isTrue);
  });

  test('a weekly event only appears on its weekday', () {
    // Tuesday 27 October 2026.
    final event = _event(
      id: 'weekly',
      start: DateTime(2026, 10, 27, 18),
      rule: Recurrence.weekly,
    );

    expect(agendaForDay([event], today), isEmpty);
    final tuesday = agendaForDay([event], DateTime(2026, 11, 3));
    expect(tuesday.single.start, DateTime(2026, 11, 3, 18));
  });

  test('a one-off event is only shown on its stored day', () {
    final event = _event(id: 'one', start: DateTime(2026, 10, 27, 9));

    expect(agendaForDay([event], today), isEmpty);
    expect(agendaForDay([event], DateTime(2026, 10, 27)), hasLength(1));
  });

  test('entries are sorted by the occurrence time', () {
    final entries = agendaForDay([
      _event(id: 'late', start: DateTime(2026, 10, 28, 16)),
      _event(
        id: 'repeat',
        start: DateTime(2026, 10, 20, 8),
        rule: Recurrence.daily,
      ),
      _event(id: 'early', start: DateTime(2026, 10, 28, 7)),
    ], today);

    expect(entries.map((entry) => entry.event.id), ['early', 'repeat', 'late']);
    expect(entries[1].start, DateTime(2026, 10, 28, 8));
  });

  test('an unknown recurrence rule falls back to the stored day', () {
    final event = _event(
      id: 'future-rule',
      start: DateTime(2026, 10, 28, 11),
      rule: 'every-second-blue-moon',
    );

    final entries = agendaForDay([event], today);

    expect(entries, hasLength(1));
    expect(entries.single.isRecurring, isFalse);
  });

  test('a series that starts tomorrow does not appear today', () {
    final event = _event(
      id: 'tomorrow',
      start: DateTime(2026, 10, 29, 9),
      rule: Recurrence.daily,
    );

    expect(agendaForDay([event], today), isEmpty);
  });
}
