import 'day_math.dart';

/// The three dates `showDatePicker` needs.
class DatePickerRange {
  const DatePickerRange({
    required this.initial,
    required this.first,
    required this.last,
  });

  final DateTime initial;
  final DateTime first;
  final DateTime last;
}

/// Bounds for a date picker that always contain the value being edited.
///
/// `showDatePicker` asserts `initialDate` lies within `firstDate..lastDate`.
/// Allowing only "today or later" therefore crashes when editing something
/// already dated in the past (an overdue project, say), or later than the
/// default upper bound (an imported date). Widen the range to include it.
DatePickerRange datePickerRange({
  DateTime? current,
  required DateTime today,
  int lastYear = 2035,
}) {
  final todayDate = DayMath.dateOnly(today);
  final currentDate = current == null ? null : DayMath.dateOnly(current);
  final defaultLast = DateTime(lastYear, 12, 31);

  return DatePickerRange(
    initial: currentDate ?? todayDate,
    first: currentDate != null && currentDate.isBefore(todayDate)
        ? currentDate
        : todayDate,
    last: currentDate != null && currentDate.isAfter(defaultLast)
        ? currentDate
        : defaultLast,
  );
}
