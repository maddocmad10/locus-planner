import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/completion_slot.dart';
import 'package:locus_planner/core/utils/recurrence_spec.dart';
import 'package:locus_planner/features/tasks/data/task_repository.dart';

void main() {
  late AppDatabase db;
  late TaskRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TaskRepository(db, UndoService());
  });
  tearDown(() => db.close());

  test(
    'a date-only slot survives completion and advances as a civil date',
    () async {
      final id = await repository.add(
        title: 'Civil',
        dueDate: DateTime(2026, 12, 1),
        recurrenceRule: 'daily',
      );
      final before = await db.getTodoItem(id);
      expect(before!.dueKind, CompletionSlot.dateOnly);
      expect(before.dueDateKey, '2026-12-01');

      await repository.toggle(id, true);
      final completion = (await db.todoCompletionsFor(id)).single;
      expect(completion.slotKind, CompletionSlot.dateOnly);
      expect(completion.slotDate, '2026-12-01');
      expect(completion.occurrenceKey, 'due:2026-12-01');
      expect(
        completion.id,
        CompletionSlot.completionIdFor(id, 'due:2026-12-01'),
      );

      final after = await db.getTodoItem(id);
      expect(after!.dueKind, CompletionSlot.dateOnly);
      expect(after.dueDateKey, '2026-12-02');
      expect(after.dueDate, DateTime(2026, 12, 2));
    },
  );

  test('a timed midnight is an instant slot, not a civil date', () async {
    final id = await repository.add(
      title: 'Timed',
      dueDate: DateTime.utc(2026, 5, 1),
      dueKind: CompletionSlot.instant,
      recurrenceRule: 'daily',
    );
    await repository.toggle(id, true);
    final completion = (await db.todoCompletionsFor(id)).single;
    expect(completion.slotKind, CompletionSlot.instant);
    expect(completion.slotDate, isNull);
    expect(completion.occurrenceKey, 'due:2026-05-01T00:00:00.000Z');
  });

  test(
    'an undated series advances its generation and does not collide',
    () async {
      final id = await repository.add(
        title: 'Undated',
        dueDate: null,
        recurrenceSpec: RecurrenceSpec.encodeAfterCompletion(10),
        dueKind: CompletionSlot.undated,
      );
      final first = await db.getTodoItem(id);
      expect(first!.undatedGeneration, isNotNull);

      await repository.toggle(id, true);
      final firstCompletion = (await db.todoCompletionsFor(id)).single;
      expect(firstCompletion.slotKind, CompletionSlot.undated);
      expect(firstCompletion.slotGeneration, first.undatedGeneration);
      expect(firstCompletion.occurrenceKey, contains(first.undatedGeneration!));

      final second = await db.getTodoItem(id);
      expect(second!.undatedGeneration, isNot(first.undatedGeneration));
      await repository.toggle(id, true);
      final completions = await db.todoCompletionsFor(id);
      expect(completions, hasLength(2));
      expect(completions.map((row) => row.occurrenceKey).toSet(), hasLength(2));
    },
  );
}
