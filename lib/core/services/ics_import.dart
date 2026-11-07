import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
    this.isAllDay = false,
    this.tzid,
    this.tzResolved = true,
    this.recurrenceId,
    this.recurrenceIdRaw,
    this.exdates = const [],
    this.rdates = const [],
    this.rawRrule,
    this.recurrenceRule,
    this.recurrenceEnd,
    this.seriesSimplified = false,
    this.reminderMinutes,
  });

  final String? uid;
  final String summary;
  final String? description;
  final DateTime start;
  final DateTime? end;
  final String category;

  /// Date-only event (`VALUE=DATE`). It imports at local midnight with no
  /// reminder.
  final bool isAllDay;

  /// TZID exactly as written in the file, if any.
  final String? tzid;

  /// False when a TZID could not be resolved and floating local time was used.
  final bool tzResolved;

  /// Present on a modified occurrence (RECURRENCE-ID).
  final DateTime? recurrenceId;

  /// RECURRENCE-ID exactly as written, used for a timezone-independent id.
  final String? recurrenceIdRaw;

  /// EXDATE occurrences removed from the series.
  final List<DateTime> exdates;

  /// RDATE occurrences added to the series.
  final List<DateTime> rdates;

  final String? rawRrule;

  /// Mapped rule, or null when the series cannot be represented exactly.
  final String? recurrenceRule;

  /// Last allowed start, generated from UNTIL or COUNT.
  final DateTime? recurrenceEnd;

  /// True when [rawRrule] exists but [recurrenceRule] is null.
  final bool seriesSimplified;

  final int? reminderMinutes;
}

class IcsParseResult {
  const IcsParseResult({
    required this.events,
    this.skipped = 0,
    this.timezoneFallbacks = 0,
    this.exdatesIgnored = 0,
    this.attachmentsIgnored = 0,
  });

  final List<IcsEvent> events;

  /// VEVENT blocks without a usable summary or start time.
  final int skipped;

  /// Start/end times whose TZID was not recognized.
  final int timezoneFallbacks;

  /// EXDATE values that could not be parsed.
  final int exdatesIgnored;

  /// ATTACH properties ignored because Locus never imports remote files.
  final int attachmentsIgnored;

  List<String> get simplifiedSeries => [
    for (final event in events)
      if (event.seriesSimplified) event.summary,
  ];
}

/// Minimal RFC 5545 reader for the event fields Locus understands.
///
/// Unsupported recurrence rules are imported as single events rather than
/// guessed, and the caller is told which ones were simplified. UNTIL and COUNT
/// are converted to the event's [IcsEvent.recurrenceEnd], TZID is resolved with
/// the IANA database, and EXDATE/RECURRENCE-ID are preserved.
class IcsParser {
  static bool _timeZonesReady = false;

  static void _ensureTimeZones() {
    if (_timeZonesReady) return;
    tzdata.initializeTimeZones();
    _timeZonesReady = true;
  }

  static IcsParseResult parse(String source) {
    _ensureTimeZones();
    final lines = _unfold(source);
    final events = <IcsEvent>[];
    var skipped = 0;
    var timezoneFallbacks = 0;
    var exdatesIgnored = 0;
    var attachmentsIgnored = 0;
    var inEvent = false;
    var inAlarm = false;
    Map<String, List<_IcsProperty>>? current;

    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper == 'BEGIN:VEVENT') {
        inEvent = true;
        inAlarm = false;
        current = <String, List<_IcsProperty>>{};
        continue;
      }
      if (upper == 'END:VEVENT') {
        if (inEvent && current != null) {
          final parsed = _toEvent(current);
          if (parsed == null) {
            skipped++;
          } else {
            events.add(parsed.event);
            timezoneFallbacks += parsed.timezoneFallbacks;
            exdatesIgnored += parsed.exdatesIgnored;
            attachmentsIgnored += parsed.attachmentsIgnored;
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

      final property = _parseProperty(line);
      if (property == null) continue;
      if (inAlarm && property.name != 'TRIGGER') continue;
      current.putIfAbsent(property.name, () => []).add(property);
    }

    return IcsParseResult(
      events: events,
      skipped: skipped,
      timezoneFallbacks: timezoneFallbacks,
      exdatesIgnored: exdatesIgnored,
      attachmentsIgnored: attachmentsIgnored,
    );
  }

  static ({
    IcsEvent event,
    int timezoneFallbacks,
    int exdatesIgnored,
    int attachmentsIgnored,
  })?
  _toEvent(Map<String, List<_IcsProperty>> values) {
    final startProperty = _first(values, 'DTSTART');
    if (startProperty == null) return null;
    final start = _parseDate(startProperty);
    if (start == null) return null;

    final summary = _first(values, 'SUMMARY');
    final title = summary == null ? '' : _unescapeIcsText(summary.value).trim();
    if (title.isEmpty) return null;

    var timezoneFallbacks = 0;
    if (!start.tzResolved) timezoneFallbacks++;

    final endProperty = _first(values, 'DTEND');
    DateTime? end;
    if (endProperty != null) {
      final parsedEnd = _parseDate(endProperty);
      if (parsedEnd != null) {
        if (!parsedEnd.tzResolved) timezoneFallbacks++;
        if (parsedEnd.value.isAfter(start.value)) end = parsedEnd.value;
      }
    }

    final description = _first(values, 'DESCRIPTION');
    final category = _category(_first(values, 'CATEGORIES')?.value);
    final reminder = start.isAllDay
        ? null
        : _parseTrigger(_first(values, 'TRIGGER')?.value);
    final uid = _first(values, 'UID')?.value.trim();
    final tzid = startProperty.parameters['TZID'];
    final recurrenceIdProperty = _first(values, 'RECURRENCE-ID');
    final recurrenceId = recurrenceIdProperty == null
        ? null
        : _parseDate(recurrenceIdProperty)?.value;

    final exdates = <DateTime>[];
    var exdatesIgnored = 0;
    for (final property in values['EXDATE'] ?? const <_IcsProperty>[]) {
      for (final raw in property.value.split(',')) {
        final parsed = _parseDate(
          _IcsProperty(
            name: property.name,
            parameters: property.parameters,
            value: raw,
          ),
        );
        if (parsed == null) {
          exdatesIgnored++;
        } else {
          exdates.add(parsed.value);
        }
      }
    }

    final rdates = <DateTime>[];
    for (final property in values['RDATE'] ?? const <_IcsProperty>[]) {
      for (final raw in property.value.split(',')) {
        final parsed = _parseDate(
          _IcsProperty(
            name: property.name,
            parameters: property.parameters,
            value: raw,
          ),
        );
        if (parsed != null) rdates.add(parsed.value);
      }
    }

    final rrule = _parseRule(
      _first(values, 'RRULE')?.value,
      start.value,
      start.isAllDay,
    );

    return (
      event: IcsEvent(
        uid: uid == null || uid.isEmpty ? null : uid,
        summary: title,
        description: description == null
            ? null
            : _unescapeIcsText(description.value),
        start: start.value,
        end: end,
        category: category,
        isAllDay: start.isAllDay,
        tzid: tzid,
        tzResolved: start.tzResolved,
        recurrenceId: recurrenceId,
        recurrenceIdRaw: recurrenceIdProperty?.value.trim(),
        exdates: exdates,
        rdates: rdates,
        rawRrule: _first(values, 'RRULE')?.value,
        recurrenceRule: rrule.rule,
        recurrenceEnd: rrule.end,
        seriesSimplified: rrule.simplified,
        reminderMinutes: reminder,
      ),
      timezoneFallbacks: timezoneFallbacks,
      exdatesIgnored: exdatesIgnored,
      // Locus never fetches ATTACH URIs. Counting them makes the import
      // report honest without opening a network connection.
      attachmentsIgnored: (values['ATTACH'] ?? const []).length,
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

  /// Splits a content line into name, parameters and value. Quoted parameter
  /// values may contain `;`, `:` and `,`; the value starts after the first
  /// colon outside quotes.
  static _IcsProperty? _parseProperty(String line) {
    var quoted = false;
    var colon = -1;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') quoted = !quoted;
      if (!quoted && char == ':') {
        colon = i;
        break;
      }
    }
    if (colon <= 0) return null;

    final header = line.substring(0, colon);
    final value = line.substring(colon + 1);
    final parts = _splitOutsideQuotes(header, ';');
    if (parts.isEmpty || parts.first.isEmpty) return null;
    final name = parts.first.toUpperCase();
    final parameters = <String, String>{};
    for (final part in parts.skip(1)) {
      final equals = part.indexOf('=');
      if (equals <= 0) continue;
      final key = part.substring(0, equals).toUpperCase();
      final rawValue = part.substring(equals + 1);
      parameters[key] = rawValue.startsWith('"') && rawValue.endsWith('"')
          ? rawValue.substring(1, rawValue.length - 1)
          : rawValue;
    }
    return _IcsProperty(name: name, parameters: parameters, value: value);
  }

  static List<String> _splitOutsideQuotes(String input, String separator) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '"') quoted = !quoted;
      if (!quoted && char == separator) {
        parts.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    parts.add(buffer.toString());
    return parts;
  }

  static _IcsProperty? _first(
    Map<String, List<_IcsProperty>> values,
    String name,
  ) {
    final list = values[name];
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  static ({DateTime value, bool tzResolved, bool isAllDay})? _parseDate(
    _IcsProperty property,
  ) {
    final value = property.value.trim();
    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return (
        value: DateTime(
          int.parse(dateOnly.group(1)!),
          int.parse(dateOnly.group(2)!),
          int.parse(dateOnly.group(3)!),
        ),
        tzResolved: true,
        isAllDay: true,
      );
    }

    final utc = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$',
    ).firstMatch(value);
    if (utc != null) {
      return (
        value: DateTime.utc(
          int.parse(utc.group(1)!),
          int.parse(utc.group(2)!),
          int.parse(utc.group(3)!),
          int.parse(utc.group(4)!),
          int.parse(utc.group(5)!),
          int.parse(utc.group(6)!),
        ).toLocal(),
        tzResolved: true,
        isAllDay: false,
      );
    }

    final local = RegExp(
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?$',
    ).firstMatch(value);
    if (local != null) {
      final year = int.parse(local.group(1)!);
      final month = int.parse(local.group(2)!);
      final day = int.parse(local.group(3)!);
      final hour = int.parse(local.group(4)!);
      final minute = int.parse(local.group(5)!);
      final second = int.tryParse(local.group(6) ?? '') ?? 0;
      final tzid = property.parameters['TZID'];
      if (tzid != null && tzid.isNotEmpty) {
        final location = _locationFor(tzid);
        if (location != null) {
          return (
            value: tz.TZDateTime(
              location,
              year,
              month,
              day,
              hour,
              minute,
              second,
            ).toLocal(),
            tzResolved: true,
            isAllDay: false,
          );
        }
        return (
          value: DateTime(year, month, day, hour, minute, second),
          tzResolved: false,
          isAllDay: false,
        );
      }
      return (
        value: DateTime(year, month, day, hour, minute, second),
        tzResolved: true,
        isAllDay: false,
      );
    }

    final parsed = DateTime.tryParse(value);
    if (parsed == null) return null;
    return (
      value: parsed.toLocal(),
      tzResolved: true,
      isAllDay: value.length == 8,
    );
  }

  static tz.Location? _locationFor(String tzid) {
    final iana = _windowsZones[tzid.toLowerCase()] ?? tzid;
    try {
      return tz.getLocation(iana);
    } catch (_) {
      return null;
    }
  }

  static const _windowsZones = <String, String>{
    'utc': 'UTC',
    'gmt standard time': 'Europe/London',
    'eastern standard time': 'America/New_York',
    'central standard time': 'America/Chicago',
    'mountain standard time': 'America/Denver',
    'pacific standard time': 'America/Los_Angeles',
    'romance standard time': 'Europe/Paris',
    'w. europe standard time': 'Europe/Berlin',
    'central europe standard time': 'Europe/Budapest',
    'india standard time': 'Asia/Kolkata',
    'china standard time': 'Asia/Shanghai',
    'tokyo standard time': 'Asia/Tokyo',
    'aus eastern standard time': 'Australia/Sydney',
  };

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

  static ({String? rule, DateTime? end, bool simplified}) _parseRule(
    String? raw,
    DateTime start,
    bool allDay,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return (rule: null, end: null, simplified: false);
    }
    final parts = <String, String>{};
    for (final part in raw.split(';')) {
      final equals = part.indexOf('=');
      if (equals <= 0) continue;
      parts[part.substring(0, equals).toUpperCase()] = part
          .substring(equals + 1)
          .toUpperCase();
    }

    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    String? rule;
    switch (parts['FREQ']) {
      case 'DAILY':
        if (interval == 1) rule = Recurrence.daily;
      case 'WEEKLY':
        final byDay = parts['BYDAY'];
        if (byDay == null) {
          if (interval == 1) rule = Recurrence.weekly;
          if (interval == 2) rule = Recurrence.biweekly;
        } else {
          final days = byDay
              .split(',')
              .map((day) => day.trim())
              .where((day) => day.isNotEmpty)
              .toSet();
          if (interval == 1 &&
              days.length == 5 &&
              days.containsAll(const ['MO', 'TU', 'WE', 'TH', 'FR'])) {
            rule = Recurrence.weekdays;
          } else if (days.length == 1 &&
              days.first == _weekdayCode(start.weekday)) {
            if (interval == 1) rule = Recurrence.weekly;
            if (interval == 2) rule = Recurrence.biweekly;
          }
        }
      case 'MONTHLY':
        if (!parts.containsKey('BYDAY') && !parts.containsKey('BYSETPOS')) {
          final byMonthDay = int.tryParse(parts['BYMONTHDAY'] ?? '');
          if ((byMonthDay == null || byMonthDay == start.day) &&
              interval == 1) {
            rule = Recurrence.monthly;
          }
        }
      case 'YEARLY':
        if (!parts.containsKey('BYDAY') &&
            !parts.containsKey('BYSETPOS') &&
            !parts.containsKey('BYMONTH')) {
          final byMonthDay = int.tryParse(parts['BYMONTHDAY'] ?? '');
          if ((byMonthDay == null || byMonthDay == start.day) &&
              interval == 1) {
            rule = Recurrence.yearly;
          }
        }
    }

    if (rule == null) {
      return (rule: null, end: null, simplified: true);
    }

    DateTime? end;
    final until = parts['UNTIL'];
    if (until != null) {
      end = _parseUntil(until);
    }
    final count = int.tryParse(parts['COUNT'] ?? '');
    if (count != null && count > 0) {
      final last = Recurrence.occurrenceAt(start, rule, count - 1);
      if (last != null && (end == null || last.isBefore(end))) end = last;
    }
    return (rule: rule, end: end, simplified: false);
  }

  static DateTime? _parseUntil(String raw) {
    final value = raw.trim();
    final dateOnly = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
    if (dateOnly != null) {
      return DateTime(
        int.parse(dateOnly.group(1)!),
        int.parse(dateOnly.group(2)!),
        int.parse(dateOnly.group(3)!),
        23,
        59,
        59,
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
      r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})?$',
    ).firstMatch(value);
    if (local != null) {
      return DateTime(
        int.parse(local.group(1)!),
        int.parse(local.group(2)!),
        int.parse(local.group(3)!),
        int.parse(local.group(4)!),
        int.parse(local.group(5)!),
        int.tryParse(local.group(6) ?? '') ?? 0,
      );
    }
    return DateTime.tryParse(value)?.toLocal();
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

class _IcsProperty {
  const _IcsProperty({
    required this.name,
    required this.parameters,
    required this.value,
  });

  final String name;
  final Map<String, String> parameters;
  final String value;
}
