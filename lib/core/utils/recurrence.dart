import 'package:drift/drift.dart';
import '../db/app_database.dart';

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
        final delta = occurrence.difference(event.startTime);
        result.add(
          event.copyWith(
            startTime: occurrence,
            endTime: event.endTime == null
                ? const Value(null)
                : Value(event.endTime!.add(delta)),
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
        return value.add(const Duration(days: 1));
      case weekdays:
        var next = value.add(const Duration(days: 1));
        while (next.weekday == DateTime.saturday ||
            next.weekday == DateTime.sunday) {
          next = next.add(const Duration(days: 1));
        }
        return next;
      case weekly:
        return value.add(const Duration(days: 7));
      case biweekly:
        return value.add(const Duration(days: 14));
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
        return value.add(const Duration(days: 36500));
    }
  }

  static int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}
