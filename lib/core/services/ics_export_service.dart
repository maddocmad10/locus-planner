import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../utils/recurrence.dart';
import '../utils/recurrence_spec.dart';
import 'error_log_service.dart';

/// RFC 5545 export for events, kept separate from the JSON backup service.
class IcsExportService {
  const IcsExportService();

  Future<bool> export(AppDatabase db) async {
    try {
      final events = await db.watchAllEvents().first;
      final attachmentRows = await db.select(db.attachments).get();
      final attachmentCounts = <String, int>{};
      for (final row in attachmentRows) {
        final eventId = row.eventId;
        if (eventId != null) {
          attachmentCounts.update(
            eventId,
            (value) => value + 1,
            ifAbsent: () => 1,
          );
        }
      }

      final ics = buildIcsCalendar(events, attachmentCounts: attachmentCounts);
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Events to Outlook',
        fileName:
            'locus_events_${DateFormat('yyyy-MM-dd').format(AppClock.now())}.ics',
      );
      if (outputFile == null) return false;
      await File(outputFile).writeAsString(ics);
      return true;
    } catch (e, st) {
      await ErrorLogService.log(e, st);
      rethrow;
    }
  }

  /// Builds an RFC 5545 calendar for [events] (CRLF line endings, escaped text,
  /// folded long lines, DTSTAMP on every event). Pure, so it can be unit tested.
  static DateTime _icsStart(Event event) {
    // RFC 5545 treats DTSTART as the first instance. Locus weekday series
    // intentionally move weekend starts to the following Monday. Export the
    // first actual Locus occurrence so external calendars agree.
    if (event.recurrenceRule == Recurrence.weekdays &&
        event.startTime.weekday >= DateTime.saturday) {
      return Recurrence.next(
            event.startTime,
            event.recurrenceRule,
            from: event.startTime.subtract(const Duration(seconds: 1)),
          ) ??
          event.startTime;
    }
    return event.startTime;
  }

  static String buildIcsCalendar(
    List<Event> events, {
    DateTime? now,
    Map<String, int> attachmentCounts = const {},
  }) {
    final stamp = _formatDateTime(now ?? AppClock.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Locus Planner//EN',
      'CALSCALE:GREGORIAN',
    ];

    for (final event in events) {
      final start = _icsStart(event);
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${event.id}@locusplanner')
        ..add('DTSTAMP:$stamp')
        ..add(
          'DTSTART${event.allDay ? ';VALUE=DATE' : ''}:'
          '${_formatEventDateTime(start, event.recurrenceRule, allDay: event.allDay)}',
        );
      final end = event.endTime;
      if (end != null) {
        final startShift = start.difference(event.startTime);
        lines.add(
          'DTEND${event.allDay ? ';VALUE=DATE' : ''}:'
          '${_formatEventDateTime(end.add(startShift), event.recurrenceRule, allDay: event.allDay)}',
        );
      }
      lines.add('SUMMARY:${_escapeIcsText(event.title)}');
      final specRule = RecurrenceSpec.tryParse(event.recurrenceSpec)?.toRRule();
      final rrule = specRule ?? Recurrence.toRRule(event.recurrenceRule);
      if (rrule != null) {
        final until = event.recurrenceEnd;
        lines.add(
          until == null
              ? 'RRULE:$rrule'
              : 'RRULE:$rrule;UNTIL=${_formatUntil(until, event.allDay)}',
        );
      }
      final exceptions = Recurrence.exceptionDayKeys(
        event.recurrenceExceptions,
      );
      if (exceptions.isNotEmpty) {
        lines.add(
          'EXDATE:${_formatExceptions(exceptions, start, event.allDay)}',
        );
      }
      if (event.recurrenceRule == Recurrence.monthly && specRule == null) {
        final rdates = _monthlyClampedRdates(event.startTime);
        if (rdates.isNotEmpty) {
          lines.add('RDATE:${rdates.join(',')}');
        }
      }
      if (event.recurrenceRule == Recurrence.yearly) {
        final rdates = _yearlyClampedRdates(event.startTime);
        if (rdates.isNotEmpty) {
          lines.add('RDATE:${rdates.join(',')}');
        }
      }
      var description = event.description;
      final omittedAttachments = attachmentCounts[event.id] ?? 0;
      if (omittedAttachments > 0) {
        // ICS cannot carry the sealed blobs. Say so in the description so a
        // reader on another calendar does not assume the attachments vanished.
        final note =
            '$omittedAttachments attachment'
            '${omittedAttachments == 1 ? '' : 's'} omitted: '
            'Locus stores files outside calendar exports.';
        description = description == null || description.isEmpty
            ? note
            : '$description\n\n$note';
      }
      if (description != null && description.isNotEmpty) {
        lines.add('DESCRIPTION:${_escapeIcsText(description)}');
      }
      if (!event.allDay && event.hasReminder && event.reminderMinutes >= 0) {
        lines
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add('DESCRIPTION:${_escapeIcsText(event.title)}')
          ..add('TRIGGER:-PT${event.reminderMinutes}M')
          ..add('END:VALARM');
      }
      lines
        ..add('CATEGORIES:${_escapeIcsText(event.category.toUpperCase())}')
        ..add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');
    return '${lines.map(_foldIcsLine).join('\r\n')}\r\n';
  }

  /// iCalendar's FREQ=MONTHLY;BYMONTHDAY rule skips February and 30-day
  /// months when the original series starts on the 29th, 30th or 31st.
  /// Locus intentionally clamps those occurrences, so add explicit RDATEs for
  /// the next 50 years while retaining the RRULE for the normal months.
  static List<String> _monthlyClampedRdates(DateTime start) {
    if (start.day <= 28) return const [];
    final dates = <String>[];
    for (var offset = 1; offset <= 50 * 12; offset++) {
      final totalMonths = start.year * 12 + start.month - 1 + offset;
      final year = totalMonths ~/ 12;
      final month = totalMonths % 12 + 1;
      final lastDay = DateTime(year, month + 1, 0).day;
      if (start.day > lastDay) {
        dates.add(
          DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(
              year,
              month,
              lastDay,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
              start.microsecond,
            ),
          ),
        );
      }
    }
    return dates;
  }

  /// A series that starts on Feb 29 moves to Feb 28 in non-leap years in the
  /// app, but an RRULE alone would skip those years in other calendars.
  static List<String> _yearlyClampedRdates(DateTime start) {
    if (start.month != 2 || start.day != 29) return const [];
    final dates = <String>[];
    for (var offset = 1; offset <= 50; offset++) {
      final year = start.year + offset;
      final isLeap = DateTime(year, 3, 0).day == 29;
      if (!isLeap) {
        dates.add(
          DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(year, 2, 28, start.hour, start.minute, start.second),
          ),
        );
      }
    }
    return dates;
  }

  /// Escapes backslashes, semicolons, commas and line breaks in TEXT values.
  static String _escapeIcsText(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\n');

  /// Folds a content line so no physical line exceeds 75 octets; continuation
  /// lines start with a single space (which counts toward the limit).
  static String _foldIcsLine(String line) {
    const limit = 75;
    if (utf8.encode(line).length <= limit) return line;

    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (octets + size > limit) {
        out.write('\r\n ');
        octets = 1;
      }
      out.write(ch);
      octets += size;
    }
    return out.toString();
  }

  static String _formatDateTime(DateTime dt) {
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());
  }

  static String _formatEventDateTime(
    DateTime dt,
    String? recurrenceRule, {
    bool allDay = false,
  }) {
    if (allDay) return DateFormat('yyyyMMdd').format(dt);
    if (Recurrence.isRecurring(recurrenceRule)) {
      return DateFormat("yyyyMMdd'T'HHmmss").format(dt);
    }
    return _formatDateTime(dt);
  }

  static String _formatUntil(DateTime dt, bool allDay) {
    if (allDay) return DateFormat('yyyyMMdd').format(dt);
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());
  }

  static String _formatExceptions(
    Set<String> days,
    DateTime start,
    bool allDay,
  ) {
    final sorted = days.toList()..sort();
    return sorted
        .map((key) {
          final day = DateTime.parse(key);
          if (allDay) return DateFormat('yyyyMMdd').format(day);
          return DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(
              day.year,
              day.month,
              day.day,
              start.hour,
              start.minute,
              start.second,
            ),
          );
        })
        .join(',');
  }
}
