import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return TaskRepository(ref.watch(databaseProvider));
});

/// Application-facing task API. Keeping database details here makes it
/// possible to add project filters, ordering, sync, or conflict handling
/// without coupling the Tasks screen to Drift.
class TaskRepository {
  TaskRepository(this._db);
  final AppDatabase _db;

  Stream<List<TodoItem>> watchAll() => _db.watchAllTodoItems();

  Future<void> add({required String title, DateTime? dueDate}) =>
      _db.addTodoItem(title, dueDate);

  Future<void> toggle(String id, bool completed) =>
      _db.toggleTodoItem(id, completed);

  Future<void> delete(String id) => _db.deleteTodoItem(id);
}
