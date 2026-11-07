import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/ics_import.dart';

void main() {
  Event event({String? description}) => Event(
    id: 'e1',
    title: 'Meeting',
    description: description,
    descriptionFormat: 'md1',
    startTime: DateTime(2026, 11, 7, 9),
    category: 'general',
    hasReminder: false,
    reminderMinutes: 10,
    allDay: false,
    recurrenceExceptions: '[]',
  );

  test('ICS export says how many attachments are omitted', () {
    final ics = DataExportService.buildIcsCalendar(
      [event(description: 'Agenda')],
      attachmentCounts: const {'e1': 3},
    );
    expect(ics, contains('DESCRIPTION:Agenda'));
    expect(ics, contains('3 attachments omitted'));
  });

  test('ICS import counts ATTACH properties and never fetches them', () {
    final parsed = IcsParser.parse(
      'BEGIN:VCALENDAR\r\n'
      'VERSION:2.0\r\n'
      'BEGIN:VEVENT\r\n'
      'UID:remote-1@example.com\r\n'
      'DTSTART:20261107T090000Z\r\n'
      'SUMMARY:Remote\r\n'
      'ATTACH:https://example.com/secret.pdf\r\n'
      'END:VEVENT\r\n'
      'END:VCALENDAR\r\n',
    );
    expect(parsed.events, hasLength(1));
    expect(parsed.attachmentsIgnored, 1);
  });
}
