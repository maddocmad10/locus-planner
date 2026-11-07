import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/features/tasks/data/task_metadata.dart';

TodoItem task(
  String id, {
  String title = 'Task',
  bool completed = false,
  DateTime? startDate,
  DateTime? dueDate,
  int priority = 0,
  String? parentId,
  DateTime? reminderAt,
}) => TodoItem(
  id: id,
  title: title,
  notesFormat: 'plain',
  completed: completed,
  createdAt: DateTime(2026, 1, 1),
  startDate: startDate,
  dueDate: dueDate,
  priority: priority,
  tags: '[]',
  parentId: parentId,
  reminderAt: reminderAt,
  isImportant: false,
);

void main() {
  group('TaskPriority', () {
    test('maps stable storage values', () {
      expect(TaskPriority.fromStorage(3), TaskPriority.high);
      expect(TaskPriority.fromStorage(2), TaskPriority.medium);
      expect(TaskPriority.fromStorage(1), TaskPriority.low);
      expect(TaskPriority.fromStorage(0), TaskPriority.none);
    });

    test('clamps values from hand-edited backups', () {
      expect(TaskPriority.fromStorage(-4), TaskPriority.none);
      expect(TaskPriority.fromStorage(99), TaskPriority.high);
      expect(TaskPriority.fromStorage(null), TaskPriority.none);
    });
  });

  group('TaskTags', () {
    test('round-trips a JSON tag array', () {
      final encoded = TaskTags.encode(['work', 'deep work']);
      expect(encoded, '["work","deep work"]');
      expect(TaskTags.decode(encoded), ['work', 'deep work']);
    });

    test('accepts a comma-separated value', () {
      expect(TaskTags.decode('errand, home ,, errand'), ['errand', 'home']);
    });

    test('ignores malformed JSON instead of throwing', () {
      expect(TaskTags.decode('{not json'), isEmpty);
      expect(TaskTags.decode('[1,2,3]'), isEmpty);
    });

    test('normalises input and caps tag count and length', () {
      final tags = TaskTags.fromInput(
        '  home, HOME, work, ${'x' * 40}, '
        'a,b,c,d,e,f,g,h,i,j,k',
      );
      expect(tags.take(3), ['home', 'work', 'x' * 32]);
      expect(tags, hasLength(TaskTags.maxTags));
      expect(tags.toSet(), hasLength(tags.length));
    });

    test('formats tags for the edit field', () {
      expect(TaskTags.toInput(['work', 'home']), 'work, home');
    });
  });

  group('nextTodoDueDate', () {
    test('advances a future due date from that date', () {
      expect(
        nextTodoDueDate(
          dueDate: DateTime(2026, 10, 29, 9),
          recurrenceRule: Recurrence.weekly,
          now: DateTime(2026, 10, 28, 8),
        ),
        DateTime(2026, 11, 5, 9),
      );
    });

    test('does not return an occurrence in the past', () {
      expect(
        nextTodoDueDate(
          dueDate: DateTime(2026, 10, 20, 9),
          recurrenceRule: Recurrence.daily,
          now: DateTime(2026, 10, 28, 8),
        ),
        DateTime(2026, 10, 28, 9),
      );
    });

    test('returns null for plain or undated tasks', () {
      expect(
        nextTodoDueDate(
          dueDate: DateTime(2026, 10, 29),
          recurrenceRule: null,
          now: DateTime(2026, 10, 28),
        ),
        isNull,
      );
      expect(
        nextTodoDueDate(
          dueDate: null,
          recurrenceRule: Recurrence.daily,
          now: DateTime(2026, 10, 28),
        ),
        isNull,
      );
    });
  });

  group('TaskSchedule', () {
    final now = DateTime(2026, 11, 1, 12);

    test('treats start or due date as scheduled', () {
      expect(TaskSchedule.isScheduled(task('a')), isFalse);
      expect(
        TaskSchedule.isScheduled(task('a', startDate: DateTime(2026, 11, 1))),
        isTrue,
      );
      expect(
        TaskSchedule.isScheduled(task('a', dueDate: DateTime(2026, 11, 1))),
        isTrue,
      );
    });

    test('classifies overdue, today and upcoming by calendar day', () {
      expect(
        TaskSchedule.isOverdue(
          task('a', dueDate: DateTime(2026, 10, 31, 23)),
          now,
        ),
        isTrue,
      );
      expect(
        TaskSchedule.isOverdue(
          task('a', dueDate: DateTime(2026, 11, 1, 8)),
          now,
        ),
        isFalse,
      );
      expect(
        TaskSchedule.isToday(
          task('a', dueDate: DateTime(2026, 11, 1, 23, 59)),
          now,
        ),
        isTrue,
      );
      expect(
        TaskSchedule.isToday(
          task('a', startDate: DateTime(2026, 11, 1, 8)),
          now,
        ),
        isTrue,
      );
      expect(
        TaskSchedule.isUpcoming(task('a', dueDate: DateTime(2026, 11, 4)), now),
        isTrue,
      );
      expect(
        TaskSchedule.isUpcoming(
          task('a', dueDate: DateTime(2026, 11, 20)),
          now,
        ),
        isFalse,
      );
    });

    test('completed tasks are never overdue, today or upcoming', () {
      final completed = task(
        'a',
        completed: true,
        dueDate: DateTime(2026, 10, 30),
      );
      expect(TaskSchedule.isOverdue(completed, now), isFalse);
      expect(TaskSchedule.isToday(completed, now), isFalse);
      expect(TaskSchedule.isUpcoming(completed, now), isFalse);
    });

    test('pending reminders must be in the future and incomplete', () {
      final future = DateTime(2026, 11, 1, 14);
      expect(
        TaskSchedule.pendingReminder(task('a', reminderAt: future), now),
        future,
      );
      expect(
        TaskSchedule.pendingReminder(
          task('a', reminderAt: DateTime(2026, 10, 31)),
          now,
        ),
        isNull,
      );
      expect(
        TaskSchedule.pendingReminder(
          task('a', completed: true, reminderAt: future),
          now,
        ),
        isNull,
      );
    });
  });

  group('TaskFilter', () {
    final now = DateTime(2026, 11, 1, 12);

    test('matches each built-in view', () {
      final unscheduled = task('a');
      final today = task('b', dueDate: DateTime(2026, 11, 1, 18));
      final overdue = task('c', dueDate: DateTime(2026, 10, 30));
      final upcoming = task('d', dueDate: DateTime(2026, 11, 3));
      final high = task('e', priority: TaskPriority.high.value);
      final done = task('f', completed: true, dueDate: DateTime(2026, 10, 30));

      expect(TaskFilter.all.matches(unscheduled, now), isTrue);
      expect(TaskFilter.today.matches(today, now), isTrue);
      expect(TaskFilter.overdue.matches(overdue, now), isTrue);
      expect(TaskFilter.upcoming.matches(upcoming, now), isTrue);
      expect(TaskFilter.highPriority.matches(high, now), isTrue);
      expect(TaskFilter.completed.matches(done, now), isTrue);
      expect(TaskFilter.unscheduled.matches(unscheduled, now), isTrue);
      expect(TaskFilter.unscheduled.matches(today, now), isFalse);
      expect(TaskFilter.overdue.matches(done, now), isFalse);
    });
  });

  group('buildTaskTree', () {
    test('nests children under their parent in input order', () {
      final roots = buildTaskTree([
        task('parent'),
        task('child-a', parentId: 'parent'),
        task('child-b', parentId: 'parent'),
        task('grandchild', parentId: 'child-a'),
      ]);

      expect(roots.map((node) => node.task.id), ['parent']);
      expect(roots.single.children.map((node) => node.task.id), [
        'child-a',
        'child-b',
      ]);
      expect(roots.single.children.first.children.single.task.id, 'grandchild');
    });

    test('promotes orphans and breaks cycles instead of losing rows', () {
      final roots = buildTaskTree([
        task('orphan', parentId: 'missing'),
        task('a', parentId: 'b'),
        task('b', parentId: 'a'),
      ]);

      final ids = <String>{};
      void collect(TaskNode node) {
        ids.add(node.task.id);
        for (final child in node.children) {
          collect(child);
        }
      }

      for (final root in roots) {
        collect(root);
      }
      expect(ids, {'orphan', 'a', 'b'});
      expect(roots.length, lessThanOrEqualTo(2));
    });

    test('keeps the path to a matching subtask', () {
      final roots = buildTaskTree([
        task('parent'),
        task('child', parentId: 'parent', priority: 3),
        task('other'),
      ], include: (item) => item.id == 'child');

      expect(roots.map((node) => node.task.id), ['parent']);
      expect(roots.single.children.single.task.id, 'child');
    });

    test('drops branches with no match', () {
      final roots = buildTaskTree([
        task('parent'),
        task('child', parentId: 'parent'),
      ], include: (item) => item.id == 'other');

      expect(roots, isEmpty);
    });
  });
}
