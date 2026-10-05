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

  static const values = <String>[
    none,
    daily,
    weekdays,
    weekly,
    biweekly,
    monthly,
    yearly,
  ];

  static String label(String? rule) {
    switch (rule) {
      case daily:
        return 'Daily';
      case weekdays:
        return 'Weekdays';
      case weekly:
        return 'Weekly';
      case biweekly:
        return 'Every 2 weeks';
      case monthly:
        return 'Monthly';
      case yearly:
        return 'Yearly';
      default:
        return 'Does not repeat';
    }
  }

  /// RFC 5545 RRULE for [rule], or null when the event does not repeat.
  static String? toRRule(String? rule) {
    switch (rule) {
      case daily:
        return 'FREQ=DAILY';
      case weekdays:
        return 'FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR';
      case weekly:
        return 'FREQ=WEEKLY';
      case biweekly:
        return 'FREQ=WEEKLY;INTERVAL=2';
      case monthly:
        return 'FREQ=MONTHLY';
      case yearly:
        return 'FREQ=YEARLY';
      default:
        return null;
    }
  }

  static bool isRecurring(String? rule) =>
      rule != null && rule.isNotEmpty && rule != none;

  /// Returns the next occurrence strictly after [from].
  static DateTime? next(DateTime start, String? rule, {DateTime? from}) {
    if (!isRecurring(rule)) return null;
    final pivot = from ?? DateTime.now();
    var candidate = start;

    for (var i = 0; i < 500; i++) {
      if (candidate.isAfter(pivot)) return candidate;
      candidate = _advance(candidate, rule!);
    }
    return null;
  }

  /// Next start whose reminder instant is still in the future.
  ///
  /// Opening the app after today's reminder time but before the event must not
  /// drop the chain: the following occurrence is armed instead.
  static DateTime? nextRemindableStart({
    required DateTime start,
    required String? rule,
    required int reminderMinutes,
    required DateTime now,
  }) {
    DateTime? occurrence;
    if (isRecurring(rule)) {
      occurrence = next(
        start,
        rule,
        from: now.subtract(const Duration(microseconds: 1)),
      );
    } else if (start.isAfter(now)) {
      occurrence = start;
    }

    for (var i = 0; i < 500 && occurrence != null; i++) {
      final reminderAt = occurrence.subtract(Duration(minutes: reminderMinutes));
      if (reminderAt.isAfter(now)) return occurrence;
      if (!isRecurring(rule)) return null;
      occurrence = next(start, rule, from: occurrence);
    }
    return null;
  }

  static List<Event> expand(Event event, DateTime from, DateTime to) {
    if (!isRecurring(event.recurrenceRule)) {
      return event.startTime.isBefore(to) && !event.startTime.isBefore(from)
          ? [event]
          : <Event>[];
    }

    final result = <Event>[];
    var occurrence = event.startTime;
    for (var i = 0; i < 1000 && !occurrence.isAfter(to); i++) {
      if (!occurrence.isBefore(from)) {
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
      }
      occurrence = _advance(occurrence, event.recurrenceRule!);
    }
    return result;
  }

  static DateTime _advance(DateTime value, String rule) {
    switch (rule) {
      case daily:
        return DayMath.addDays(value, 1);
      case weekdays:
        var next = DayMath.addDays(value, 1);
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = DayMath.addDays(next, 1);
        }
        return next;
      case weekly:
        return DayMath.addDays(value, 7);
      case biweekly:
        return DayMath.addDays(value, 14);
      case monthly:
        final nextMonth = value.month == 12 ? 1 : value.month + 1;
        final nextYear = value.month == 12 ? value.year + 1 : value.year;
        final day = value.day
            .clamp(1, _daysInMonth(nextYear, nextMonth))
            .toInt();
        return DateTime(
          nextYear,
          nextMonth,
          day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
      case yearly:
        final day = value.day
            .clamp(1, _daysInMonth(value.year + 1, value.month))
            .toInt();
        return DateTime(
          value.year + 1,
          value.month,
          day,
          value.hour,
          value.minute,
          value.second,
          value.millisecond,
          value.microsecond,
        );
      default:
        return DayMath.addDays(value, 36500);
    }
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}
