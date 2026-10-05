import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

Event _event({
  String id = 'e1',
  String title = 'Meeting',
  String? description,
  DateTime? start,
  DateTime? end,
  String category = 'work',
  String? recurrenceRule,
}) {
  return Event(
    id: id,
    title: title,
    description: description,
    startTime: start ?? DateTime.utc(2026, 10, 5, 16, 30),
    endTime: end,
    category: category,
    hasReminder: false,
    reminderMinutes: 10,
    recurrenceRule: recurrenceRule,
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 5, 12);

  test('produces a well-formed calendar with CRLF line endings', () {
    final ics = DataExportService.buildIcsCalendar([_event()], now: now);

    expect(ics, startsWith('BEGIN:VCALENDAR\r\n'));
    expect(ics, endsWith('END:VCALENDAR\r\n'));
    expect(
      RegExp(r'(?<!\r)\n').hasMatch(ics),
      isFalse,
      reason: 'bare LF found',
    );
    expect(ics, contains('UID:e1@locusplanner\r\n'));
  });

  test('writes DTSTAMP and UTC start/end times', () {
    final ics = DataExportService.buildIcsCalendar([
      _event(end: DateTime.utc(2026, 10, 5, 17, 30)),
    ], now: now);
    expect(ics, contains('DTSTAMP:20261005T120000Z\r\n'));
    expect(ics, contains('DTSTART:20261005T163000Z\r\n'));
    expect(ics, contains('DTEND:20261005T173000Z\r\n'));
  });

  test('omits DTEND when the event has no end time', () {
    final ics = DataExportService.buildIcsCalendar([_event()], now: now);
    expect(ics, isNot(contains('DTEND')));
  });

  test('escapes backslashes, semicolons, commas and newlines', () {
    final ics = DataExportService.buildIcsCalendar([
      _event(title: r'A, B; C\D', description: 'line1\nline2'),
    ], now: now);
    expect(ics, contains(r'SUMMARY:A\, B\; C\\D'));
    expect(ics, contains(r'DESCRIPTION:line1\nline2'));
  });

  test('folds long lines to 75 octets and unfolds back to the original', () {
    final title = 'x' * 200;
    final ics = DataExportService.buildIcsCalendar([
      _event(title: title),
    ], now: now);

    for (final line in ics.split('\r\n')) {
      expect(line.codeUnits.length, lessThanOrEqualTo(75));
    }
    expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:$title'));
  });

  test('folding never splits a multi-byte character', () {
    final title = 'é' * 100; // 2 bytes each in UTF-8
    final ics = DataExportService.buildIcsCalendar([
      _event(title: title),
    ], now: now);

    expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:$title'));
    for (final line in ics.split('\r\n')) {
      // 'é' is a single UTF-16 unit, so octets = units + count('é').
      final octets = line.codeUnits.length + 'é'.allMatches(line).length;
      expect(octets, lessThanOrEqualTo(75));
    }
  });

  test('writes an RRULE for recurring events and omits it otherwise', () {
    final ics = DataExportService.buildIcsCalendar([
      _event(recurrenceRule: 'weekdays'),
    ], now: now);
    expect(ics, contains('RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR\r\n'));
    expect(
      DataExportService.buildIcsCalendar([_event()], now: now),
      isNot(contains('RRULE')),
    );
  });
}
