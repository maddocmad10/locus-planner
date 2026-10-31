import '../utils/recurrence.dart';

/// One VEVENT read from an iCalendar file, before it is written to the
/// database. Times are local [DateTime] values, matching the planner's model.
class IcsEvent {
  const IcsEvent({
    this.uid,
    required this.summary,
    this.description,
    required this.start,
    this.end,
    this.category = 'general',
    this.recurrenceRule,
    this.reminderMinutes,
  });

  final String? uid;
  final String summary;
  final String? description;
  final DateTime start;
  final DateTime? end;
  final String category;
  final String? recurrenceRule;
  final int? reminderMinutes;
}

class IcsParseResult {
  const IcsParseResult({required this.events, this.skipped = 0});

  final List<IcsEvent> events;

  /// VEVENT blocks without a usable summary or start time.
  final int skipped;
}

/// Minimal RFC 5545 reader for the event fields Locus understands.
///
/// Unsupported recurrence rules are imported as single events rather than
/// guessed: showing a series on the wrong days is worse than showing one
/// occurrence. Unfolding, text escapes and the common DTSTART forms are
/// handled, so files from Outlook, Google Calendar and Apple Calendar import
/// without preprocessing.
class IcsParser {
  static IcsParseResult parse(String source) {
    final lines = _unfold(source);
    final events = <IcsEvent>[];
    var skipped = 0;
    var inEvent = false;
    var inAlarm = false;
    Map<String, String>? current;

    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VEVENT') {
        inEvent = true;
        inAlarm = false;
        current = <String, String>{};
        continue;
      }
      if (upper == 'END:VEVENT') {
        if (inEvent && current != null) {
          final event = _toEvent(current);
          if (event == null) {
            skipped++;
          } else {
            events.add(event);
          }
        }
        inEvent = false;
        inAlarm = false;
        current = null;
        continue;
      }
      if (!inEvent || current == null) continue;

      if (upper == 'BEGIN:VALARM') {
        inAlarm = true;
        continue;
      }
      if (upper == 'END:VALARM') {
        inAlarm = false;
        continue;
      }

      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      final header = line.substring(0, colon);
      final name = header.split(';').first.toUpperCase();
      if (inAlarm && name != 'TRIGGER') continue;
      current[name] = line.substring(colon + 1);
    }

    return IcsParseResult(events: events, skipped: skipped);
  }

  static IcsEvent? _toEvent(Map<String, String> values) {
    final start = _parseDateTime(values['DTSTART']);
    if (start == null) return null;

    final rawSummary = values['SUMMARY'];
    final summary = rawSummary == null
        ? ''
        : _unescapeIcsText(rawSummary).trim();
    if (summary.isEmpty) return null;

    final end = _parseDateTime(values['DTEND']);
    final description = values['DESCRIPTION'];
    final category = _category(values['CATEGORIES']);
    final reminder = _parseTrigger(values['TRIGGER']);

    return IcsEvent(
      uid: values['UID']?.trim(),
      summary: summary,
      description: description == null ? null : _unescapeIcsText(description),
      start: start,
      end: end != null && end.isAfter(start) ? end : null,
      category: category,
      recurrenceRule: _parseRRule(values['RRULE'], start),
      reminderMinutes: reminder,
    );
  }

  static List<String> _unfold(String source) {
    final physical = source
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final lines = <String>[];
    for (final line in physical) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && lines.isNotEmpty) {
        lines[lines.length - 1] += line.substring(1);
      } else {
        lines.add(line);
      }
    }
    return lines;
  }

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();

    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return DateTime(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
      );
    }

    final utc = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
    ).firstMatch(value);
    if (utc != null) {
      return DateTime.utc(
        int.parse(utc.group(1)!),
        int.parse(utc.group(2)!),
        int.parse(utc.group(3)!),
        int.parse(utc.group(4)!),
        int.parse(utc.group(5)!),
        int.parse(utc.group(6)!),
      ).toLocal();
    }

    final local = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$',
    ).firstMatch(value);
    if (local != null) {
      return DateTime(
        int.parse(local.group(1)!),
        int.parse(local.group(2)!),
        int.parse(local.group(3)!),
        int.parse(local.group(4)!),
        int.parse(local.group(5)!),
        int.parse(local.group(6)!),
      );
    }

    return DateTime.tryParse(value);
  }

  static String _category(String? raw) {
    if (raw == null) return 'general';
    final first = _unescapeIcsText(raw).split(',').first.trim();
    return first.isEmpty ? 'general' : first.toLowerCase();
  }

  static int? _parseTrigger(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toUpperCase();
    final match = RegExp(
      r'^-P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$',
    ).firstMatch(value);
    if (match == null) return null;

    final days = int.tryParse(match.group(1) ?? '') ?? 0;
    final hours = int.tryParse(match.group(2) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
    final totalSeconds = ((days * 24 + hours) * 60 + minutes) * 60 + seconds;
    if (totalSeconds <= 0) return null;
    return (totalSeconds / 60).ceil();
  }

  static String? _parseRRule(String? raw, DateTime start) {
    if (raw == null) return null;
    final parts = <String, String>{};
    for (final part in raw.split(';')) {
      final equals = part.indexOf('=');
      if (equals <= 0) continue;
      parts[part.substring(0, equals).toUpperCase()] = part
          .substring(equals + 1)
          .toUpperCase();
    }

    // A bounded series cannot be represented by Locus's open-ended rules.
    if (parts.containsKey('COUNT') || parts.containsKey('UNTIL')) return null;
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;

    switch (parts['FREQ']) {
      case 'DAILY':
        return interval == 1 ? Recurrence.daily : null;
      case 'WEEKLY':
        final byDay = parts['BYDAY'];
        if (byDay == null) {
          if (interval == 1) return Recurrence.weekly;
          if (interval == 2) return Recurrence.biweekly;
          return null;
        }
        final days = byDay
            .split(',')
            .map((day) => day.trim())
            .where((day) => day.isNotEmpty)
            .toSet();
        if (interval == 1 &&
            days.length == 5 &&
            days.containsAll(const ['MO', 'TU', 'WE', 'TH', 'FR'])) {
          return Recurrence.weekdays;
        }
        if (days.length == 1 && days.first == _weekdayCode(start.weekday)) {
          if (interval == 1) return Recurrence.weekly;
          if (interval == 2) return Recurrence.biweekly;
        }
        return null;
      case 'MONTHLY':
        if (parts.containsKey('BYDAY') || parts.containsKey('BYSETPOS')) {
          return null;
        }
        final byMonthDay = int.tryParse(parts['BYMONTHDAY'] ?? '');
        if (byMonthDay != null && byMonthDay != start.day) return null;
        return interval == 1 ? Recurrence.monthly : null;
      case 'YEARLY':
        if (parts.containsKey('BYDAY') ||
            parts.containsKey('BYSETPOS') ||
            parts.containsKey('BYMONTH')) {
          return null;
        }
        final byMonthDay = int.tryParse(parts['BYMONTHDAY'] ?? '');
        if (byMonthDay != null && byMonthDay != start.day) return null;
        return interval == 1 ? Recurrence.yearly : null;
    }
    return null;
  }

  static String _weekdayCode(int weekday) => switch (weekday) {
    DateTime.monday => 'MO',
    DateTime.tuesday => 'TU',
    DateTime.wednesday => 'WE',
    DateTime.thursday => 'TH',
    DateTime.friday => 'FR',
    DateTime.saturday => 'SA',
    _ => 'SU',
  };

  static String _unescapeIcsText(String value) {
    final out = StringBuffer();
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (char != '\\' || i + 1 >= value.length) {
        out.write(char);
        continue;
      }
      final next = value[++i];
      switch (next) {
        case 'n':
        case 'N':
          out.write('\n');
          break;
        case ',':
          out.write(',');
          break;
        case ';':
          out.write(';');
          break;
        case '\\':
          out.write('\\');
          break;
        default:
          out.write(next);
      }
    }
    return out.toString();
  }
}
