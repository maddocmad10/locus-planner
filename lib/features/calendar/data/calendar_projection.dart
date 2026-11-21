import '../../../core/db/app_database.dart';
import '../../../core/services/calendar_subscription_service.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/recurrence.dart';

enum CalendarEntryKind { event, block, subscription }

/// One occurrence rendered on the calendar. It is a projection: events and
/// tasks stay the canonical rows; nothing here is persisted.
class CalendarEntry {
  const CalendarEntry({
    required this.key,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.isRecurring = false,
    this.event,
    this.block,
    this.sourceId,
    this.sourceLabel,
  });

  final String key;
  final CalendarEntryKind kind;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool isRecurring;
  final Event? event;
  final TaskScheduleBlock? block;

  /// Set for a read-only external calendar occurrence.
  final String? sourceId;
  final String? sourceLabel;

  bool get isReadOnly => kind == CalendarEntryKind.subscription;

  String get taskKey {
    final block = this.block;
    if (block == null) return '';
    if (block.todoItemId != null) return 'todo:${block.todoItemId}';
    return 'task:${block.projectTaskId}';
  }
}

/// Expands stored events and schedule blocks over [from]..[to].
///
/// Recurring events use the same [Recurrence.expand] as My Day, so exception
/// dates and clamped month/year series agree across screens.
List<CalendarEntry> buildCalendarEntries({
  required Iterable<Event> events,
  required Iterable<TaskScheduleBlock> blocks,
  required DateTime from,
  required DateTime to,
  required String Function(TaskScheduleBlock block) titleForBlock,
}) {
  final start = DayMath.dateOnly(from);
  final end = DayMath.addDays(DayMath.dateOnly(to), 1);
  final entries = <CalendarEntry>[];

  for (final event in events) {
    for (final occurrence in Recurrence.expand(event, start, end)) {
      final shift = occurrence.startTime.difference(event.startTime);
      final eventEnd = event.endTime?.add(shift);
      final defaultEnd = event.allDay
          ? DayMath.addDays(occurrence.startTime, 1)
          : occurrence.startTime.add(const Duration(minutes: 30));
      entries.add(
        CalendarEntry(
          key:
              'event:${event.id}:${occurrence.startTime.millisecondsSinceEpoch}',
          kind: CalendarEntryKind.event,
          title: event.title,
          start: occurrence.startTime,
          end: eventEnd ?? defaultEnd,
          allDay: event.allDay,
          isRecurring: Recurrence.isRecurring(event.recurrenceRule),
          event: event,
        ),
      );
    }
  }

  for (final block in blocks) {
    if (!block.startAt.isBefore(end) || !block.endAt.isAfter(start)) continue;
    entries.add(
      CalendarEntry(
        key: 'block:${block.id}',
        kind: CalendarEntryKind.block,
        title: titleForBlock(block),
        start: block.startAt,
        end: block.endAt,
        block: block,
      ),
    );
  }

  entries.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.title.compareTo(b.title);
  });
  return entries;
}

/// Read-only feed occurrences, projected like local events but identified by
/// their source so the UI can label them and never offer an editor.
List<CalendarEntry> buildSubscriptionEntries({
  required Iterable<CalendarFeedOccurrence> occurrences,
  required Map<String, String> sourceLabels,
}) {
  final entries = <CalendarEntry>[];
  for (final occurrence in occurrences) {
    final DateTime start;
    final DateTime end;
    if (occurrence.allDay) {
      start = _parseDate(occurrence.startDate!);
      end = _parseDate(occurrence.endDate!);
    } else {
      start = occurrence.start!;
      end = occurrence.end ?? start.add(const Duration(minutes: 30));
    }
    entries.add(
      CalendarEntry(
        key:
            'feed:${occurrence.sourceId}:${occurrence.uid}:'
            '${occurrence.recurrenceKey}:${occurrence.occurrenceStartKey}',
        kind: CalendarEntryKind.subscription,
        title: occurrence.title,
        start: start,
        end: end,
        allDay: occurrence.allDay,
        sourceId: occurrence.sourceId,
        sourceLabel: sourceLabels[occurrence.sourceId],
      ),
    );
  }
  entries.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.title.compareTo(b.title);
  });
  return entries;
}

DateTime _parseDate(String value) {
  final parts = value.split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

/// Entries that overlap [day], clipped to the day's boundaries.
List<CalendarEntry> entriesForDay(List<CalendarEntry> entries, DateTime day) {
  final start = DayMath.dateOnly(day);
  final end = DayMath.addDays(start, 1);
  final result = <CalendarEntry>[];
  for (final entry in entries) {
    if (entry.allDay) {
      if (!entry.start.isBefore(end) || !entry.end.isAfter(start)) continue;
      result.add(entry);
      continue;
    }
    if (entry.start.isBefore(end) && entry.end.isAfter(start)) {
      result.add(entry);
    }
  }
  result.sort((a, b) {
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.start.compareTo(b.start);
  });
  return result;
}

/// Keys of entries that overlap another entry on the same day. Advisory only:
/// Locus never prevents overlapping plans.
Set<String> conflictingEntryKeys(List<CalendarEntry> entries) {
  final timed = entries.where((entry) => !entry.allDay).toList();
  final conflicts = <String>{};
  for (var i = 0; i < timed.length; i++) {
    for (var j = i + 1; j < timed.length; j++) {
      final a = timed[i];
      final b = timed[j];
      if (a.start.isBefore(b.end) && b.start.isBefore(a.end)) {
        conflicts
          ..add(a.key)
          ..add(b.key);
      }
    }
  }
  return conflicts;
}

String dayHeading(DateTime day) =>
    '${_weekdayName(day.weekday)} ${day.day} ${_monthName(day.month)} ${day.year}';

String _weekdayName(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

String _monthName(int month) => const [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
][month - 1];
