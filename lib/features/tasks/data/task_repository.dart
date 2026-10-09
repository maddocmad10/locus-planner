import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';

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

  Future<void> add({required String title, DateTime? dueDate}) =>
      _db.addTodoItem(title, dueDate);

  Future<void> toggle(String id, bool completed) =>
      _db.toggleTodoItem(id, completed);

  Future<void> delete(String id) => _db.deleteTodoItem(id);

  Future<void> deleteWithUndo(TodoItem task) async {
    await delete(task.id);
    _undo.offer(label: 'task', restore: () => restore(task));
  }

  Future<void> restore(TodoItem task) => _db.into(_db.todoItems).insert(task);
}
