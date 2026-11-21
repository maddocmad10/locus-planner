import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../db/app_database.dart';
import '../utils/day_math.dart';

/// Versioned richer recurrence. The legacy `recurrenceRule` remains valid for
/// every existing row; a spec is only written by an explicit richer choice.
class RecurrenceSpec {
  const RecurrenceSpec._({
    required this.version,
    required this.type,
    this.days,
    this.ordinal,
    this.weekday,
  });

  static const maxAfterCompletionDays = 3650;

  final int version;
  final String type;
  final int? days;
  final int? ordinal;
  final int? weekday;

  static const afterCompletion = 'after_completion';
  static const monthlyWeekday = 'monthly_weekday';

  bool get isAfterCompletion =>
      type == afterCompletion && days != null && days! >= 1;

  bool get isMonthlyWeekday =>
      type == monthlyWeekday &&
      ordinal != null &&
      (ordinal == -1 || (ordinal! >= 1 && ordinal! <= 5)) &&
      weekday != null &&
      weekday! >= 1 &&
      weekday! <= 7;

  static RecurrenceSpec? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final version = decoded['v'];
      final type = decoded['type'];
      if (version != 1 || type is! String) return null;
      if (type == afterCompletion) {
        final days = decoded['days'];
        if (days is! int || days < 1 || days > maxAfterCompletionDays) {
          return null;
        }
        return RecurrenceSpec._(version: 1, type: afterCompletion, days: days);
      }
      if (type == monthlyWeekday) {
        final ordinal = decoded['ordinal'];
        final weekday = decoded['weekday'];
        if (ordinal is! int ||
            weekday is! int ||
            (ordinal != -1 && (ordinal < 1 || ordinal > 5)) ||
            weekday < 1 ||
            weekday > 7) {
          return null;
        }
        return RecurrenceSpec._(
          version: 1,
          type: monthlyWeekday,
          ordinal: ordinal,
          weekday: weekday,
        );
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  static String encodeAfterCompletion(int days) {
    if (days < 1 || days > maxAfterCompletionDays) {
      throw FormatException(
        'Choose between 1 and $maxAfterCompletionDays days.',
      );
    }
    return jsonEncode({'v': 1, 'type': afterCompletion, 'days': days});
  }

  static String encodeMonthlyWeekday({
    required int ordinal,
    required int weekday,
  }) {
    if ((ordinal != -1 && (ordinal < 1 || ordinal > 5)) ||
        weekday < 1 ||
        weekday > 7) {
      throw const FormatException('Invalid monthly weekday rule.');
    }
    return jsonEncode({
      'v': 1,
      'type': monthlyWeekday,
      'ordinal': ordinal,
      'weekday': weekday,
    });
  }

  /// Task due date after completing an occurrence. [due] supplies the local
  /// wall-clock time; [completedAt] is the local completion date.
  DateTime nextAfterCompletion(DateTime? due, DateTime completedAt) {
    final days = this.days;
    if (days == null) throw StateError('Not an after-completion spec.');
    final base = DayMath.dateOnly(completedAt);
    final time = due ?? DateTime(base.year, base.month, base.day, 9);
    return DateTime(
      base.year,
      base.month,
      base.day + days,
      time.hour,
      time.minute,
      time.second,
      time.millisecond,
      time.microsecond,
    );
  }

  /// Three upcoming occurrences for a preview, preserving the local time and
  /// duration of [start].
  List<DateTime> previewMonthlyWeekday(DateTime start, {int count = 3}) {
    final result = <DateTime>[];
    var month = DateTime(start.year, start.month);
    while (result.length < count) {
      final occurrence = _monthlyOccurrence(month, start);
      if (occurrence != null && !occurrence.isBefore(start)) {
        result.add(occurrence);
      }
      month = DateTime(month.year, month.month + 1);
    }
    return result;
  }

  /// Expands a monthly-weekday event over [from]..[to]. The wall-clock time is
  /// preserved across DST; Dart's local constructor selects the first valid
  /// instant after a missing hour and the first occurrence of a repeated hour.
  List<Event> expandEvent(Event event, DateTime from, DateTime to) {
    final result = <Event>[];
    final exceptions = _exceptionKeys(event.recurrenceExceptions);
    var month = DateTime(from.year, from.month);
    final lastMonth = DateTime(to.year, to.month);
    while (!month.isAfter(lastMonth)) {
      final occurrence = _monthlyOccurrence(month, event.startTime);
      if (occurrence != null &&
          !occurrence.isBefore(event.startTime) &&
          !occurrence.isBefore(from) &&
          occurrence.isBefore(to) &&
          (event.recurrenceEnd == null ||
              !occurrence.isAfter(event.recurrenceEnd!)) &&
          !exceptions.contains(_dayKey(occurrence))) {
        final delta = DayMath.calendarDaysBetween(event.startTime, occurrence);
        result.add(
          event.copyWith(
            startTime: occurrence,
            endTime: event.endTime == null
                ? const Value(null)
                : Value(DayMath.addDays(event.endTime!, delta)),
          ),
        );
      }
      month = DateTime(month.year, month.month + 1);
    }
    return result;
  }

  static Set<String> _exceptionKeys(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      return {for (final value in decoded.whereType<String>()) value};
    } catch (_) {
      return const {};
    }
  }

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  DateTime? _monthlyOccurrence(DateTime month, DateTime start) {
    final ordinal = this.ordinal;
    final weekday = this.weekday;
    if (ordinal == null || weekday == null) return null;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    if (ordinal == -1) {
      for (var day = daysInMonth; day >= 1; day--) {
        final candidate = DateTime(
          month.year,
          month.month,
          day,
          start.hour,
          start.minute,
          start.second,
          start.millisecond,
        );
        if (candidate.weekday == weekday) return candidate;
      }
      return null;
    }
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final offset = (weekday - firstWeekday + 7) % 7;
    final day = 1 + offset + (ordinal - 1) * 7;
    if (day > daysInMonth) return null;
    return DateTime(
      month.year,
      month.month,
      day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
    );
  }

  /// RRULE fragment for ICS export. Completion-relative task rules have no
  /// event-series equivalent and are not exported as an event rule.
  String? toRRule() {
    if (!isMonthlyWeekday) return null;
    const names = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final byDay = ordinal == -1
        ? '-1${names[weekday! - 1]}'
        : '$ordinal${names[weekday! - 1]}';
    return 'FREQ=MONTHLY;BYDAY=$byDay';
  }

  String get readableLabel {
    if (isAfterCompletion) return 'Every $days days after completion';
    if (isMonthlyWeekday) {
      const names = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      final position = ordinal == -1 ? 'last' : '$ordinal';
      return '$position ${names[weekday! - 1]} of each month';
    }
    return 'Update required';
  }
}
