import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';
import 'task_metadata.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

final tasksStreamProvider = StreamProvider<List<TodoItem>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});

/// Application-facing task API. Keeping database details here makes it
/// possible to add project filters, ordering, sync, or conflict handling
/// without coupling the Tasks screen to Drift.
class TaskRepository {
  TaskRepository(this._db, this._undo);
  final AppDatabase _db;
  final UndoService _undo;

  Stream<List<TodoItem>> watchAll() => _db.watchAllTodoItems();

  Future<void> add({
    required String title,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    Iterable<String> tags = const [],
    String? recurrenceRule,
  }) => _db.addTodoItem(
    title,
    dueDate,
    priority: priority.value,
    tags: TaskTags.encode(tags),
    recurrenceRule: recurrenceRule,
  );

  Future<void> update({
    required String id,
    required String title,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    Iterable<String> tags = const [],
    String? recurrenceRule,
  }) => _db.updateTodoItem(
    id: id,
    title: title,
    dueDate: dueDate,
    priority: priority.value,
    tags: TaskTags.encode(tags),
    recurrenceRule: recurrenceRule,
  );

  /// Completes a plain task, or advances a repeating one to its next due date.
  /// The returned date is the new due date when the task repeated.
  Future<DateTime?> toggle(String id, bool completed) async {
    if (!completed) {
      await _db.toggleTodoItem(id, false);
      return null;
    }

    final task = await _db.getTodoItem(id);
    if (task == null) return null;
    final nextDue = nextTodoDueDate(
      dueDate: task.dueDate,
      recurrenceRule: task.recurrenceRule,
      now: AppClock.now(),
    );
    if (nextDue == null) {
      await _db.toggleTodoItem(id, true);
      return null;
    }

    await _db.updateTodoItem(
      id: task.id,
      title: task.title,
      dueDate: nextDue,
      priority: task.priority,
      tags: task.tags,
      recurrenceRule: task.recurrenceRule,
    );
    return nextDue;
  }

  Future<void> delete(String id) => _db.deleteTodoItem(id);

  Future<void> deleteWithUndo(TodoItem task) async {
    await delete(task.id);
    _undo.offer(label: 'task', restore: () => restore(task));
  }

  Future<void> restore(TodoItem task) => _db.into(_db.todoItems).insert(task);
}
