import '../utils/day_math.dart';

/// A local wall-clock interval expressed as minutes after midnight.
class ClockWindow {
  const ClockWindow(this.startMinute, this.endMinute);

  final int startMinute;
  final int endMinute;

  int get minutes => endMinute - startMinute;

  bool get isValid =>
      startMinute >= 0 && endMinute <= 1440 && endMinute > startMinute;

  /// The interval as concrete instants on [day], using local calendar fields so
  /// a DST change cannot shift the requested wall-clock time.
  ({DateTime start, DateTime end}) on(DateTime day) => (
    start: DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: startMinute)),
    end: DateTime(
      day.year,
      day.month,
      day.day,
    ).add(Duration(minutes: endMinute)),
  );
}

/// One scheduled task block, identified by the task it belongs to.
class BookedInterval {
  const BookedInterval({
    required this.taskKey,
    required this.start,
    required this.end,
  });

  final String taskKey;
  final DateTime start;
  final DateTime end;

  int get minutes => end.difference(start).inMinutes;
}

/// Everything the capacity calculation needs for one local day. The service is
/// pure: it never reads the database or the clock itself.
class CapacityInput {
  const CapacityInput({
    required this.day,
    this.workingHours = const [],
    this.breaks = const [],
    this.busyEvents = const [],
    this.blocks = const [],
    this.plannedMinutesByTask = const {},
    this.bufferMinutes = 0,
    this.overcommitThresholdPercent = 100,
  });

  final DateTime day;
  final List<ClockWindow> workingHours;
  final List<ClockWindow> breaks;
  final List<({DateTime start, DateTime end})> busyEvents;
  final List<BookedInterval> blocks;
  final Map<String, int> plannedMinutesByTask;
  final int bufferMinutes;
  final int overcommitThresholdPercent;
}

enum CapacityReason {
  overcommitted,
  noWorkingHours,
  bufferApplied,
  myDayEstimateFallback,
}

class CapacityReasonDetail {
  const CapacityReasonDetail(this.reason, this.message);
  final CapacityReason reason;
  final String message;
}

/// Deterministic day capacity: working intervals minus breaks, timed busy
/// events, a per-block buffer and the effort already planned for tasks.
///
/// A task is counted once. Its schedule blocks define real booked time and
/// always win; `daily_plan_items.planned_minutes` is only a fallback for a task
/// that has no block that day. That keeps an estimate from being added twice.
class CapacitySummary {
  const CapacitySummary({
    required this.day,
    required this.workingMinutes,
    required this.breakMinutes,
    required this.busyMinutes,
    required this.bufferMinutes,
    required this.bookedMinutes,
    required this.plannedMinutes,
    required this.taskMinutes,
    required this.reasons,
  });

  final DateTime day;
  final int workingMinutes;
  final int breakMinutes;
  final int busyMinutes;
  final int bufferMinutes;

  /// Minutes covered by actual calendar blocks. Overlapping blocks are counted
  /// separately because each one is real work the user planned.
  final int bookedMinutes;

  /// Total planned effort: calendar blocks plus the My Day estimate fallback
  /// for tasks that have no block that day. A task is counted once.
  final int plannedMinutes;

  final Map<String, int> taskMinutes;
  final List<CapacityReasonDetail> reasons;

  int get availableMinutes {
    final value = workingMinutes - breakMinutes - busyMinutes - bufferMinutes;
    return value < 0 ? 0 : value;
  }

  int get remainingMinutes => availableMinutes - plannedMinutes;

  int get overcommittedBy => remainingMinutes < 0 ? -remainingMinutes : 0;

  bool get isOvercommitted => remainingMinutes < 0;

  bool get hasWorkingHours => workingMinutes > 0;

  double get utilization => availableMinutes == 0
      ? (plannedMinutes > 0 ? double.infinity : 0)
      : plannedMinutes / availableMinutes;
}

/// Pure capacity calculation shared by the calendar, weekly review and the
/// later suggestion engine.
abstract final class CapacityService {
  static CapacitySummary summarize(CapacityInput input) {
    final dayStart = DayMath.dateOnly(input.day);
    final dayEnd = DayMath.addDays(dayStart, 1);

    final working = _unionMinutes(
      [
        for (final window in input.workingHours)
          if (window.isValid) window.on(dayStart),
      ],
      dayStart,
      dayEnd,
    );

    final breakMinutes = _unionMinutes(
      [
        for (final window in input.breaks)
          if (window.isValid) window.on(dayStart),
      ],
      dayStart,
      dayEnd,
    );

    final busy = _unionMinutes(input.busyEvents, dayStart, dayEnd);

    // Sum of every block's clipped duration. Overlapping blocks are counted
    // separately because each one is real work the user planned, while busy
    // events are unioned because they block the same wall-clock time once.
    final booked = _sumMinutes(
      [for (final block in input.blocks) (start: block.start, end: block.end)],
      dayStart,
      dayEnd,
    );

    final taskMinutes = <String, int>{};
    for (final block in input.blocks) {
      if (block.minutes <= 0) continue;
      taskMinutes[block.taskKey] =
          (taskMinutes[block.taskKey] ?? 0) + block.minutes;
    }

    final reasons = <CapacityReasonDetail>[];
    var fallbackUsed = false;
    var fallbackMinutes = 0;
    input.plannedMinutesByTask.forEach((taskKey, minutes) {
      if (minutes <= 0 || taskMinutes.containsKey(taskKey)) return;
      taskMinutes[taskKey] = minutes;
      fallbackMinutes += minutes;
      fallbackUsed = true;
    });
    if (fallbackUsed) {
      reasons.add(
        const CapacityReasonDetail(
          CapacityReason.myDayEstimateFallback,
          'Some tasks use their My Day estimate because they have no calendar '
          'block.',
        ),
      );
    }

    final buffer = input.blocks.isEmpty
        ? 0
        : input.bufferMinutes * input.blocks.length;

    final workingMinutes = working;
    final availableRaw = workingMinutes - breakMinutes - busy - buffer;
    final available = availableRaw < 0 ? 0 : availableRaw;
    final threshold =
        available * (input.overcommitThresholdPercent.clamp(1, 100) / 100);

    // Total planned effort: real blocks plus the estimate fallback for tasks
    // that have no block today. Each task contributes once.
    final plannedMinutes = booked + fallbackMinutes;

    if (workingMinutes <= 0) {
      reasons.add(
        const CapacityReasonDetail(
          CapacityReason.noWorkingHours,
          'No working hours are configured for this day.',
        ),
      );
    }
    if (plannedMinutes > availableRaw) {
      reasons.add(
        CapacityReasonDetail(
          CapacityReason.overcommitted,
          'Planned work exceeds available capacity by '
          '${plannedMinutes - availableRaw} minutes.',
        ),
      );
    } else if (threshold > 0 && plannedMinutes > threshold) {
      reasons.add(
        CapacityReasonDetail(
          CapacityReason.overcommitted,
          'Planned work is above the configured '
          '${input.overcommitThresholdPercent}% threshold.',
        ),
      );
    }
    if (buffer > 0) {
      reasons.add(
        CapacityReasonDetail(
          CapacityReason.bufferApplied,
          '$buffer minutes reserved as transition buffer.',
        ),
      );
    }

    return CapacitySummary(
      day: dayStart,
      workingMinutes: workingMinutes,
      breakMinutes: breakMinutes,
      busyMinutes: busy,
      bufferMinutes: buffer,
      bookedMinutes: booked,
      plannedMinutes: plannedMinutes,
      taskMinutes: taskMinutes,
      reasons: reasons,
    );
  }

  /// Total minutes covered by [intervals] after merging overlaps and clipping
  /// to [start]..[end].
  static int _unionMinutes(
    List<({DateTime start, DateTime end})> intervals,
    DateTime start,
    DateTime end,
  ) {
    final clipped = <({DateTime start, DateTime end})>[];
    for (final interval in intervals) {
      final from = interval.start.isBefore(start) ? start : interval.start;
      final to = interval.end.isAfter(end) ? end : interval.end;
      if (to.isAfter(from)) clipped.add((start: from, end: to));
    }
    if (clipped.isEmpty) return 0;
    clipped.sort((a, b) => a.start.compareTo(b.start));

    var total = 0;
    var cursorStart = clipped.first.start;
    var cursorEnd = clipped.first.end;
    for (final interval in clipped.skip(1)) {
      if (interval.start.isAfter(cursorEnd)) {
        total += cursorEnd.difference(cursorStart).inMinutes;
        cursorStart = interval.start;
        cursorEnd = interval.end;
      } else if (interval.end.isAfter(cursorEnd)) {
        cursorEnd = interval.end;
      }
    }
    total += cursorEnd.difference(cursorStart).inMinutes;
    return total;
  }

  /// Sum of each interval's duration after clipping to [start]..[end], without
  /// merging overlaps.
  static int _sumMinutes(
    List<({DateTime start, DateTime end})> intervals,
    DateTime start,
    DateTime end,
  ) {
    var total = 0;
    for (final interval in intervals) {
      final from = interval.start.isBefore(start) ? start : interval.start;
      final to = interval.end.isAfter(end) ? end : interval.end;
      if (to.isAfter(from)) total += to.difference(from).inMinutes;
    }
    return total;
  }
}
