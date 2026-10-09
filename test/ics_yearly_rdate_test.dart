import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

Event _event(DateTime start, String rule) => Event(
  id: 'e1',
  title: 'Leap day',
  description: null,
  startTime: start,
  endTime: null,
  category: 'general',
  hasReminder: false,
  reminderMinutes: 10,
  recurrenceRule: rule,
);

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);

  String unfolded(List<Event> events) => DataExportService.buildIcsCalendar(
    events,
    now: now,
  ).replaceAll('\r\n ', '');

  test('a Feb 29 yearly series gets Feb 28 dates for non-leap years', () {
    final ics = unfolded([_event(DateTime(2028, 2, 29, 9), 'yearly')]);

    expect(ics, contains('RRULE:FREQ=YEARLY'));
    expect(
      ics,
      contains(
        'RDATE:20290228T090000,20300228T090000,20310228T090000,20330228T090000',
      ),
    );
    expect(ics, isNot(contains('20320228')), reason: '2032 is a leap year');
  });

  test('ordinary yearly series need no extra dates', () {
    expect(
      unfolded([_event(DateTime(2028, 3, 1, 9), 'yearly')]),
      isNot(contains('RDATE')),
    );
  });
}
