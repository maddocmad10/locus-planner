import 'package:flutter_test/flutter_test.dart';

import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/features/tasks/data/task_metadata.dart';

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
}
