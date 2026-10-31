import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/ics_import.dart';
import 'package:locus_planner/core/utils/recurrence.dart';

const basicCalendar = r'''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Example//EN
BEGIN:VEVENT
UID:abc@example.com
DTSTAMP:20261005T120000Z
DTSTART:20261005T163000Z
DTEND:20261005T173000Z
SUMMARY:Lunch\, team
DESCRIPTION:Line 1\nLine 2
CATEGORIES:Work,Personal
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
BEGIN:VALARM
ACTION:DISPLAY
DESCRIPTION:Alarm text
TRIGGER:-PT10M
END:VALARM
END:VEVENT
END:VCALENDAR
''';

void main() {
  group('IcsParser', () {
    test('reads the fields Locus understands', () {
      final result = IcsParser.parse(basicCalendar);

      expect(result.skipped, 0);
      final event = result.events.single;
      expect(event.uid, 'abc@example.com');
      expect(event.summary, 'Lunch, team');
      expect(event.description, 'Line 1\nLine 2');
      expect(event.category, 'work');
      expect(event.recurrenceRule, Recurrence.weekdays);
      expect(event.reminderMinutes, 10);
      expect(event.start, DateTime.utc(2026, 10, 5, 16, 30).toLocal());
      expect(event.end, DateTime.utc(2026, 10, 5, 17, 30).toLocal());
    });

    test('ignores VALARM descriptions when reading the event', () {
      final event = IcsParser.parse(basicCalendar).events.single;
      expect(event.description, 'Line 1\nLine 2');
    });

    test('unfolds folded content lines', () {
      const folded =
          'BEGIN:VEVENT\n'
          'UID:folded\n'
          'DTSTART:20261005T090000\n'
          'SUMMARY:A very long\n'
          ' title that was folded\n'
          'END:VEVENT\n';

      expect(
        IcsParser.parse(folded).events.single.summary,
        'A very longtitle that was folded',
      );
    });

    test('accepts date-only and floating start times', () {
      final dateOnly = IcsParser.parse(
        'BEGIN:VEVENT\n'
        'SUMMARY:Holiday\n'
        'DTSTART;VALUE=DATE:20261005\n'
        'END:VEVENT\n',
      ).events.single;
      expect(dateOnly.start, DateTime(2026, 10, 5));

      final floating = IcsParser.parse(
        'BEGIN:VEVENT\n'
        'SUMMARY:Standup\n'
        'DTSTART:20261005T093000\n'
        'END:VEVENT\n',
      ).events.single;
      expect(floating.start, DateTime(2026, 10, 5, 9, 30));
    });

    test('skips VEVENTs without a summary or start', () {
      final result = IcsParser.parse(
        'BEGIN:VEVENT\n'
        'DTSTART:20261005T090000\n'
        'END:VEVENT\n'
        'BEGIN:VEVENT\n'
        'SUMMARY:No start\n'
        'END:VEVENT\n'
        'BEGIN:VEVENT\n'
        'SUMMARY:Valid\n'
        'DTSTART:20261005T090000\n'
        'END:VEVENT\n',
      );

      expect(result.events.single.summary, 'Valid');
      expect(result.skipped, 2);
    });

    test('maps supported RRULEs and refuses unsupported ones', () {
      final start = DateTime(2026, 10, 5, 9); // Monday
      final cases = <String, String?>{
        'FREQ=DAILY': Recurrence.daily,
        'FREQ=WEEKLY': Recurrence.weekly,
        'FREQ=WEEKLY;INTERVAL=2': Recurrence.biweekly,
        'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR': Recurrence.weekdays,
        'FREQ=WEEKLY;BYDAY=MO': Recurrence.weekly,
        'FREQ=MONTHLY': Recurrence.monthly,
        'FREQ=YEARLY': Recurrence.yearly,
        'FREQ=DAILY;COUNT=5': null,
        'FREQ=MONTHLY;BYDAY=1MO': null,
        'FREQ=WEEKLY;BYDAY=MO,WE': null,
        'FREQ=HOURLY': null,
      };

      for (final entry in cases.entries) {
        final event = IcsParser.parse(
          'BEGIN:VEVENT\n'
          'SUMMARY:Series\n'
          'DTSTART:20261005T090000\n'
          'RRULE:${entry.key}\n'
          'END:VEVENT\n',
        ).events.single;
        expect(event.recurrenceRule, entry.value, reason: entry.key);
        expect(event.start, start);
      }
    });

    test('round-trips an event exported by Locus', () {
      final original = Event(
        id: 'e1',
        title: 'Morning focus',
        description: 'Deep work',
        startTime: DateTime(2026, 10, 5, 9),
        endTime: DateTime(2026, 10, 5, 10),
        category: 'work',
        hasReminder: true,
        reminderMinutes: 15,
        recurrenceRule: Recurrence.daily,
      );

      final ics = DataExportService.buildIcsCalendar([
        original,
      ], now: DateTime(2026, 10, 4, 12));
      final imported = IcsParser.parse(ics).events.single;

      expect(imported.summary, 'Morning focus');
      expect(imported.description, 'Deep work');
      expect(imported.category, 'work');
      expect(imported.start, original.startTime);
      expect(imported.end, original.endTime);
      expect(imported.recurrenceRule, Recurrence.daily);
      expect(imported.reminderMinutes, 15);
    });
  });

  group('DataExportService ICS import', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('writes imported events and is idempotent by UID', () async {
      final service = DataExportService(db);

      final first = await service.importEventsFromIcsText(basicCalendar);
      expect(first.imported, 1);
      expect(first.skipped, 0);

      final created = await db.select(db.events).getSingle();
      expect(created.title, 'Lunch, team');
      expect(created.category, 'work');
      expect(created.hasReminder, isTrue);
      expect(created.reminderMinutes, 10);
      expect(created.recurrenceRule, Recurrence.weekdays);

      final second = await service.importEventsFromIcsText(basicCalendar);
      expect(second.imported, 1);
      final events = await db.select(db.events).get();
      expect(events, hasLength(1));
      expect(events.single.id, created.id);
    });

    test('reports an empty calendar without touching the database', () async {
      final report = await DataExportService(
        db,
      ).importEventsFromIcsText('BEGIN:VCALENDAR\nEND:VCALENDAR\n');
      expect(report.imported, 0);
      expect(await db.select(db.events).get(), isEmpty);
    });

    test('rejects an oversized file before reading it', () async {
      final dir = await Directory.systemTemp.createTemp('locus-ics-size-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}large.ics');
      final handle = await file.open(mode: FileMode.write);
      await handle.setPosition(DataExportService.maxIcsImportFileBytes);
      await handle.writeByte(0);
      await handle.close();

      await expectLater(
        DataExportService(db).readIcsFile(file),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
