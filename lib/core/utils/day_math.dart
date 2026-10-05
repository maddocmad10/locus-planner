/// Calendar-day arithmetic that is safe across daylight-saving changes.
///
/// `DateTime.subtract(Duration(days: 1))` removes exactly 24 hours. On a
/// local DST-change day that lands on 23:00 or 01:00 instead of midnight, so
/// equality checks against "local midnight" values silently fail. Everything
/// here works on calendar fields (year/month/day) instead.
class DayMath {
  const DayMath._();

  /// Local midnight of [d].
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// [d] moved by [days] calendar days, keeping the wall-clock time.
  /// Negative values go back in time.
  static DateTime addDays(DateTime d, int days) => DateTime(
    d.year,
    d.month,
    d.day + days,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
    d.microsecond,
  );

  /// Number of calendar days from [from] to [to] (negative if [to] is earlier).
  /// Time of day is ignored.
  static int calendarDaysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  /// Local midnight of the Monday of the week containing [d].
  static DateTime startOfWeek(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  /// Length of the run of consecutive calendar days in [dates] that ends today
  /// (or yesterday, if today has no entry yet). A single missing day ends the
  /// run. Duplicates and time-of-day are ignored.
  static int consecutiveDayStreak(Iterable<DateTime> dates, {DateTime? now}) {
    final days = dates.map(dateOnly).toSet();
    if (days.isEmpty) return 0;

    var cursor = dateOnly(now ?? DateTime.now());
    if (!days.contains(cursor)) cursor = addDays(cursor, -1);

    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = addDays(cursor, -1);
    }
    return streak;
  }
}
