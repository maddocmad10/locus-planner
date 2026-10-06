import 'package:drift/drift.dart';
import '../db/app_database.dart';
import 'day_math.dart';

/// Lightweight recurrence support for planner events.
///
/// Supported values are intentionally human-readable and stable for backups:
/// none, daily, weekdays, weekly, biweekly, monthly, yearly.
class Recurrence {
  static const none = 'none';
  static const daily = 'daily';
  static const weekdays = 'weekdays';
  static const weekly = 'weekly';
  static const biweekly = 'biweekly';
  static const monthly = 'monthly';
  static const yearly = 'yearly';

  static const values = <String>[none, daily, weekdays, weekly, biweekly, monthly, yearly];

  static String label(String? rule) {
    switch (rule) {
      case daily: return 'Daily';
      case weekdays: return 'Weekdays';
      case weekly: return 'Weekly';
      case biweekly: return 'Every 2 weeks';
      case monthly: return 'Monthly';
      case yearly: return 'Yearly';
      default: return 'Does not repeat';
    }
  }

  static String? toRRule(String? rule) {
    switch (rule) {
      case daily: return 'FREQ=DAILY';
      case weekdays: return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR';
      case weekly: return 'FREQ=WEEKLY';
      case biweekly: return 'FREQ=WEEKLY;INTERVAL=2';
      case monthly: return 'FREQ=MONTHLY';
      case yearly: return 'FREQ=YEARLY';
      default: return null;
    }
  }

  static bool isRecurring(String? rule) => rule != null && rule.isNotEmpty && rule != none;

  /// Returns the next occurrence strictly after [from].
  ///
  /// The occurrence is calculated from the original [start], never from a
  /// previously clamped occurrence. Thus Jan 31 -> Feb 28 -> Mar 31.
  static DateTime? next(DateTime start, String? rule, {DateTime? from}) {
    if (!isRecurring(rule)) return null;
    final pivot = from ?? DateTime.now();
    var index = _firstIndexAtOrAfter(start, rule!, pivot);
    var candidate = _occurrenceAt(start, rule, index);
    if (!candidate.isAfter(pivot)) {
      index++;
      candidate = _occurrenceAt(start, rule, index);
    }
    return candidate;
  }

  static DateTime? nextRemindableStart({
    required DateTime start,
    required String? rule,
    required int reminderMinutes,
    required DateTime now,
  }) {
    if (!isRecurring(rule)) {
      return start.isAfter(now) && start.subtract(Duration(minutes: reminderMinutes)).isAfter(now)
          ? start
          : null;
    }

    var occurrence = _occurrenceAt(start, rule!, _firstIndexAtOrAfter(start, rule, now));
    while (true) {
      final reminderAt = occurrence.subtract(Duration(minutes: reminderMinutes));
      if (reminderAt.isAfter(now)) return occurrence;
      occurrence = _occurrenceAt(start, rule, _indexAfter(start, rule, occurrence));
    }
  }

  static List<Event> expand(Event event, DateTime from, DateTime to) {
    if (!isRecurring(event.recurrenceRule)) {
      return event.startTime.isBefore(to) && !event.startTime.isBefore(from)
          ? [event]
          : <Event>[];
    }
    if (!from.isBefore(to)) return const [];

    final rule = event.recurrenceRule!;
    var index = _firstIndexAtOrAfter(event.startTime, rule, from);
    var occurrence = _occurrenceAt(event.startTime, rule, index);
    final result = <Event>[];

    while (occurrence.isBefore(to)) {
      final dayDelta = DayMath.calendarDaysBetween(event.startTime, occurrence);
      final end = event.endTime;
      result.add(
        event.copyWith(
          startTime: occurrence,
          endTime: end == null
              ? const Value(null)
              : Value(DayMath.addDays(end, dayDelta)),
        ),
      );
      index++;
      occurrence = _occurrenceAt(event.startTime, rule, index);
    }
    return result;
  }

  static int _firstIndexAtOrAfter(DateTime start, String rule, DateTime pivot) {
    if (pivot.isBefore(start)) return 0;
    switch (rule) {
      case daily:
        return _calendarDayDistance(start, pivot);
      case weekly:
        return _calendarDayDistance(start, pivot) ~/ 7;
      case biweekly:
        return _calendarDayDistance(start, pivot) ~/ 14;
      case monthly:
        return (pivot.year - start.year) * 12 + pivot.month - start.month;
      case yearly:
        return pivot.year - start.year;
      case weekdays:
        return _weekdayIndexAtOrAfter(start, pivot);
      default:
        return 0;
    }
  }

  static int _indexAfter(DateTime start, String rule, DateTime occurrence) {
    switch (rule) {
      case daily: return _calendarDayDistance(start, occurrence) + 1;
      case weekly: return _calendarDayDistance(start, occurrence) ~/ 7 + 1;
      case biweekly: return _calendarDayDistance(start, occurrence) ~/ 14 + 1;
      case monthly: return (occurrence.year - start.year) * 12 + occurrence.month - start.month + 1;
      case yearly: return occurrence.year - start.year + 1;
      case weekdays: return _weekdayIndexAtOrAfter(start, occurrence) + 1;
      default: return 1;
    }
  }

  static DateTime _occurrenceAt(DateTime start, String rule, int index) {
    if (index <= 0) return start;
    switch (rule) {
      case daily:
        return DayMath.addDays(start, index);
      case weekly:
        return DayMath.addDays(start, index * 7);
      case biweekly:
        return DayMath.addDays(start, index * 14);
      case weekdays:
        return _weekdayOccurrenceAt(start, index);
      case monthly:
        final totalMonths = start.year * 12 + start.month - 1 + index;
        final year = totalMonths ~/ 12;
        final month = totalMonths % 12 + 1;
        final day = start.day.clamp(1, _daysInMonth(year, month)).toInt();
        return _withDate(start, year, month, day);
      case yearly:
        final year = start.year + index;
        final day = start.day.clamp(1, _daysInMonth(year, start.month)).toInt();
        return _withDate(start, year, start.month, day);
      default:
        return start;
    }
  }

  static DateTime _weekdayOccurrenceAt(DateTime start, int index) {
    if (start.weekday >= DateTime.monday && start.weekday <= DateTime.friday) {
      final offset = start.weekday - 1;
      final target = offset + index;
      final weeks = target ~/ 5;
      final weekdayOffset = target % 5;
      return DayMath.addDays(start, weeks * 7 + weekdayOffset - offset);
    }
    final daysToMonday = DateTime.monday - start.weekday + (start.weekday >= DateTime.saturday ? 7 : 0);
    final firstMonday = DayMath.addDays(start, daysToMonday);
    return DayMath.addDays(firstMonday, (index - 1) ~/ 5 * 7 + (index - 1) % 5);
  }

  static int _weekdayIndexAtOrAfter(DateTime start, DateTime pivot) {
    if (pivot.isBefore(start)) return 0;
    var low = 0;
    var high = _calendarDayDistance(start, pivot) + 2;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_occurrenceAt(start, weekdays, mid).isBefore(pivot)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  static int _calendarDayDistance(DateTime a, DateTime b) =>
      DayMath.calendarDaysBetween(a, b);

  static DateTime _withDate(DateTime source, int year, int month, int day) => DateTime(
        year,
        month,
        day,
        source.hour,
        source.minute,
        source.second,
        source.millisecond,
        source.microsecond,
      );

  static int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;
}
