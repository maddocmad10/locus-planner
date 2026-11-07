import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/features/calendar/data/calendar_projection.dart';

Event event({
  required String id,
  required String title,
  required DateTime start,
  DateTime? end,
  String? rule,
  bool allDay = false,
}) {
  return Event(
    id: id,
    title: title,
    descriptionFormat: 'plain',
    startTime: start,
    endTime: end,
    category: 'general',
    hasReminder: false,
    reminderMinutes: 10,
    recurrenceRule: rule,
    allDay: allDay,
    recurrenceExceptions: '[]',
  );
}

TaskScheduleBlock block({
  required String id,
  required DateTime start,
  required DateTime end,
  String? todoId,
  String? projectTaskId,
}) {
  return TaskScheduleBlock(
    id: id,
    todoItemId: todoId,
    projectTaskId: projectTaskId,
    startAt: start,
    endAt: end,
    blockKind: 'work',
    createdAt: start,
    updatedAt: start,
    sortOrder: 0,
  );
}

void main() {
  test('projects events and sorted blocks into one list', () {
    final entries = buildCalendarEntries(
      events: [
        event(
          id: 'e1',
          title: 'Standup',
          start: DateTime(2026, 5, 20, 10),
          end: DateTime(2026, 5, 20, 10, 30),
        ),
        event(
          id: 'e2',
          title: 'Holiday',
          start: DateTime(2026, 5, 20),
          allDay: true,
        ),
      ],
      blocks: [
        block(
          id: 'b1',
          todoId: 't1',
          start: DateTime(2026, 5, 20, 9),
          end: DateTime(2026, 5, 20, 9, 45),
        ),
        block(
          id: 'b2',
          projectTaskId: 'p1',
          start: DateTime(2026, 5, 20, 10, 15),
          end: DateTime(2026, 5, 20, 11),
        ),
      ],
      from: DateTime(2026, 5, 20),
      to: DateTime(2026, 5, 20),
      titleForBlock: (value) => value.todoItemId == null ? 'Project' : 'To-do',
    );

    expect(entries.map((entry) => entry.title), [
      'Holiday',
      'To-do',
      'Standup',
      'Project',
    ]);
    expect(entries.first.allDay, isTrue);
    expect(entries[1].key, 'block:b1');
    expect(entries[1].taskKey, 'todo:t1');
    expect(entries[3].taskKey, 'task:p1');
    expect(entries[2].isRecurring, isFalse);
  });

  test('expands recurring events with the shared recurrence engine', () {
    final entries = buildCalendarEntries(
      events: [
        event(
          id: 'daily',
          title: 'Daily',
          start: DateTime(2026, 5, 20, 9),
          end: DateTime(2026, 5, 20, 9, 30),
          rule: Recurrence.daily,
        ),
      ],
      blocks: const [],
      from: DateTime(2026, 5, 20),
      to: DateTime(2026, 5, 21),
      titleForBlock: (_) => '',
    );

    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.start.day), [20, 21]);
    expect(entries.every((entry) => entry.isRecurring), isTrue);
    expect(entries[1].end, DateTime(2026, 5, 21, 9, 30));
  });

  test('entriesForDay clips to the requested day', () {
    final entries = buildCalendarEntries(
      events: [
        event(id: 'e1', title: 'Today', start: DateTime(2026, 5, 20, 9)),
        event(id: 'e2', title: 'Tomorrow', start: DateTime(2026, 5, 21, 9)),
      ],
      blocks: [
        block(
          id: 'b1',
          todoId: 't1',
          start: DateTime(2026, 5, 19, 23),
          end: DateTime(2026, 5, 20, 1),
        ),
      ],
      from: DateTime(2026, 5, 20),
      to: DateTime(2026, 5, 21),
      titleForBlock: (_) => 'Late',
    );

    final day = entriesForDay(entries, DateTime(2026, 5, 20));
    expect(day.map((entry) => entry.title), ['Late', 'Today']);
  });

  test('conflicts are advisory and ignore all-day entries', () {
    final entries = buildCalendarEntries(
      events: [
        event(
          id: 'e1',
          title: 'A',
          start: DateTime(2026, 5, 20, 9),
          end: DateTime(2026, 5, 20, 10),
        ),
        event(
          id: 'e2',
          title: 'B',
          start: DateTime(2026, 5, 20, 9, 30),
          end: DateTime(2026, 5, 20, 10, 30),
        ),
        event(
          id: 'e3',
          title: 'All day',
          start: DateTime(2026, 5, 20),
          allDay: true,
        ),
      ],
      blocks: [
        block(
          id: 'b1',
          todoId: 't1',
          start: DateTime(2026, 5, 20, 12),
          end: DateTime(2026, 5, 20, 13),
        ),
      ],
      from: DateTime(2026, 5, 20),
      to: DateTime(2026, 5, 20),
      titleForBlock: (_) => 'C',
    );

    final conflicts = conflictingEntryKeys(entries);
    expect(
      conflicts,
      containsAll([
        'event:e1:${DateTime(2026, 5, 20, 9).millisecondsSinceEpoch}',
        'event:e2:${DateTime(2026, 5, 20, 9, 30).millisecondsSinceEpoch}',
      ]),
    );
    expect(conflicts, isNot(contains('block:b1')));
    expect(conflicts, hasLength(2));
  });

  test('day heading is deterministic', () {
    expect(dayHeading(DateTime(2026, 5, 20)), 'Wednesday 20 May 2026');
  });
}
