import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/ics_import.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/recurrence.dart';

String fixture(String name) =>
    File('test/fixtures/ics/$name').readAsStringSync();

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
        'FREQ=DAILY;COUNT=5': Recurrence.daily,
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
        descriptionFormat: 'plain',
        startTime: DateTime(2026, 10, 5, 9),
        endTime: DateTime(2026, 10, 5, 10),
        category: 'work',
        hasReminder: true,
        reminderMinutes: 15,
        recurrenceRule: Recurrence.daily,
        allDay: false,
        recurrenceExceptions: '[]',
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

    test('maps UNTIL to recurrence_end instead of simplifying the series', () {
      final result = IcsParser.parse(fixture('google_weekly_until.ics'));

      expect(result.simplifiedSeries, isEmpty);
      final event = result.events.single;
      expect(event.recurrenceRule, Recurrence.weekly);
      expect(event.recurrenceEnd!.toUtc(), DateTime.utc(2026, 12, 28, 9));
      expect(event.seriesSimplified, isFalse);
    });

    test('resolves an IANA TZID and a Windows zone name to one instant', () {
      final iana = IcsParser.parse(fixture('quoted_param.ics')).events.single;
      final windows = IcsParser.parse(
        fixture('outlook_tzid.ics'),
      ).events.single;

      // 09:00 America/New_York on 2026-10-05 is 13:00 UTC.
      expect(iana.start.toUtc(), DateTime.utc(2026, 10, 5, 13));
      expect(windows.start.toUtc(), iana.start.toUtc());
      expect(windows.tzid, 'Eastern Standard Time');
      expect(windows.tzResolved, isTrue);
      expect(iana.summary, 'Quoted parameter');
    });

    test('counts an unknown TZID as a fallback', () {
      final result = IcsParser.parse(
        'BEGIN:VEVENT\n'
        'UID:unknown-zone\n'
        'SUMMARY:Local time\n'
        'DTSTART;TZID=Not/AZone:20261005T090000\n'
        'END:VEVENT\n',
      );

      expect(result.timezoneFallbacks, 1);
      expect(result.events.single.tzResolved, isFalse);
      expect(result.events.single.start, DateTime(2026, 10, 5, 9));
    });

    test('all-day events keep COUNT and EXDATE and drop the alarm', () {
      final event = IcsParser.parse(
        fixture('apple_allday_exdate.ics'),
      ).events.single;

      expect(event.isAllDay, isTrue);
      expect(event.start, DateTime(2026, 10, 5));
      expect(event.reminderMinutes, isNull);
      expect(event.recurrenceRule, Recurrence.daily);
      expect(event.recurrenceEnd, DateTime(2026, 10, 7));
      expect(event.exdates, [DateTime(2026, 10, 6)]);
    });

    test('keeps a modified occurrence separate from its master', () {
      final result = IcsParser.parse(fixture('override.ics'));

      expect(result.events, hasLength(2));
      final master = result.events.firstWhere(
        (event) => event.recurrenceId == null,
      );
      final override = result.events.firstWhere(
        (event) => event.recurrenceId != null,
      );
      expect(master.summary, 'Daily standup');
      expect(master.recurrenceEnd!.toUtc(), DateTime.utc(2026, 10, 9, 9));
      expect(override.summary, 'Daily standup (moved)');
      expect(override.recurrenceId!.toUtc(), DateTime.utc(2026, 10, 7, 9));
      expect(override.start.toUtc(), DateTime.utc(2026, 10, 7, 11));
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
      expect(second.imported, 0);
      expect(second.updated, 1);
      expect(second.total, 1);
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

    test('re-importing a Locus export changes nothing', () async {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'e1',
              title: 'Morning focus',
              startTime: DateTime(2026, 10, 5, 9),
              endTime: Value(DateTime(2026, 10, 5, 10)),
            ),
          );
      final ics = DataExportService.buildIcsCalendar(
        await db.select(db.events).get(),
        now: DateTime(2026, 10, 4, 12),
      );

      final report = await DataExportService(db).importEventsFromIcsText(ics);
      expect(report.imported, 0);
      expect(report.updated, 1);
      final events = await db.select(db.events).get();
      expect(events, hasLength(1));
      expect(events.single.id, 'e1');
      expect(events.single.title, 'Morning focus');
    });

    test(
      'imports an all-day event without a reminder and with EXDATE',
      () async {
        final report = await DataExportService(
          db,
        ).importEventsFromIcsText(fixture('apple_allday_exdate.ics'));

        expect(report.allDayImported, 1);
        final event = (await db.select(db.events).get()).single;
        expect(event.allDay, isTrue);
        expect(event.hasReminder, isFalse);
        expect(event.recurrenceExceptions, contains('2026-10-06'));
      },
    );

    test(
      'imports overrides separately and adds the date to the master',
      () async {
        final report = await DataExportService(
          db,
        ).importEventsFromIcsText(fixture('override.ics'));

        expect(report.overridesImported, 1);
        final events = await db.select(db.events).get();
        expect(events, hasLength(2));
        final master = events.firstWhere(
          (event) => event.title == 'Daily standup',
        );
        final override = events.firstWhere(
          (event) => event.title == 'Daily standup (moved)',
        );
        expect(master.id, isNot(override.id));
        expect(master.recurrenceRule, Recurrence.daily);
        expect(master.recurrenceExceptions, contains('2026-10-07'));
        expect(override.recurrenceRule, isNull);
        expect(override.startTime.toUtc(), DateTime.utc(2026, 10, 7, 11));
      },
    );

    test('can skip series that cannot be represented exactly', () async {
      const calendar =
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:odd-series\n'
          'SUMMARY:Odd series\n'
          'DTSTART:20261005T090000\n'
          'RRULE:FREQ=WEEKLY;BYDAY=MO,WE\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n';
      final service = DataExportService(db);
      final preview = await service.previewIcs(calendar);
      expect(preview.simplifiedSeries, ['Odd series']);

      final skipped = await service.importIcs(preview, keepSimplified: false);
      expect(skipped.simplifiedSkipped, 1);
      expect(await db.select(db.events).get(), isEmpty);

      final imported = await service.importIcs(preview, keepSimplified: true);
      expect(imported.imported, 1);
      final event = (await db.select(db.events).get()).single;
      expect(event.recurrenceRule, isNull);
    });

    test('imports extra RDATE occurrences as one-off events', () async {
      const calendar =
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:rdate-series@example.com\n'
          'SUMMARY:Month end\n'
          'DTSTART:20260131T090000\n'
          'RRULE:FREQ=MONTHLY\n'
          'RDATE:20260228T090000,20260315T090000\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n';
      final report = await DataExportService(
        db,
      ).importEventsFromIcsText(calendar);

      expect(report.imported, 2);
      final events = await db.select(db.events).get();
      expect(events, hasLength(2));
      expect(
        events.where((event) => event.recurrenceRule == null).single.startTime,
        DateTime(2026, 3, 15, 9),
      );
    });

    test(
      'a Locus month-end export does not gain duplicate RDATE events',
      () async {
        final original = Event(
          id: 'month-end',
          title: 'Month end',
          description: null,
          descriptionFormat: 'plain',
          startTime: DateTime(2026, 1, 31, 9),
          endTime: null,
          category: 'general',
          hasReminder: false,
          reminderMinutes: 10,
          recurrenceRule: Recurrence.monthly,
          allDay: false,
          recurrenceExceptions: '[]',
        );
        final ics = DataExportService.buildIcsCalendar([
          original,
        ], now: DateTime(2026, 1, 1));

        await DataExportService(db).importEventsFromIcsText(ics);
        expect(await db.select(db.events).get(), hasLength(1));
      },
    );

    test('undo removes new events and restores overwritten rows', () async {
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'e1',
              title: 'Original title',
              startTime: DateTime(2026, 10, 5, 9),
            ),
          );
      final undo = UndoService();
      final service = DataExportService(db, undo: undo);
      const calendar =
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:e1@locusplanner\n'
          'SUMMARY:Replacement title\n'
          'DTSTART:20261005T090000\n'
          'END:VEVENT\n'
          'BEGIN:VEVENT\n'
          'UID:new-event@example.com\n'
          'SUMMARY:Brand new\n'
          'DTSTART:20261006T090000\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n';

      final report = await service.importEventsFromIcsText(calendar);
      expect(report.updated, 1);
      expect(report.imported, 1);
      expect(await db.select(db.events).get(), hasLength(2));

      expect(await undo.undo(), isTrue);
      final restored = await db.select(db.events).get();
      expect(restored, hasLength(1));
      expect(restored.single.id, 'e1');
      expect(restored.single.title, 'Original title');
    });
  });
}
