import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../events/data/reminder_inbox_service.dart';
import 'task_metadata.dart';

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final repository = TaskRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
    ref.watch(notificationServiceProvider),
  );
  repository.onLateTaskReminder = (taskId, title, reminderAt) {
    // Read lazily: the inbox itself depends on tasks only through the
    // dialog's Mark done action, so there is no construction cycle.
    unawaited(
      ref
          .read(reminderInboxServiceProvider)
          .rememberMissedTask(
            taskId: taskId,
            title: title,
            reminderAt: reminderAt,
          ),
    );
  };
  return repository;
});

final tasksStreamProvider = StreamProvider<List<TodoItem>>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll();
});

/// Application-facing task API. Keeping database details here makes it
/// possible to add project filters, ordering, sync, or conflict handling
/// without coupling the Tasks screen to Drift.
class TaskRepository {
  /// [notifications] is optional so tests and headless callers can construct a
  /// repository without the native notifier.
  TaskRepository(this._db, this._undo, [this._notifications]);

  final AppDatabase _db;
  final UndoService _undo;
  final NotificationService? _notifications;
  void Function(String taskId, String title, DateTime reminderAt)?
  onLateTaskReminder;

  Stream<List<TodoItem>> watchAll() => _db.watchAllTodoItems();

  /// Completion history, newest first, for the task editor and My Day.
  Future<List<TodoCompletion>> completionsFor(String todoId) =>
      _db.todoCompletionsFor(todoId);

  /// Creates a to-do and returns its id. Callers that only need the side
  /// effect can ignore the result; My Day uses it to plan the new task.
  Future<String> add({
    required String title,
    String? notes,
    String notesFormat = 'plain',
    DateTime? startDate,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    Iterable<String> tags = const [],
    String? recurrenceRule,
    String? parentId,
    String? projectId,
    DateTime? reminderAt,
  }) async {
    final id = await _db.addTodoItem(
      title,
      dueDate,
      notes: notes,
      notesFormat: notesFormat,
      startDate: startDate,
      priority: priority.value,
      tags: TaskTags.encode(tags),
      recurrenceRule: recurrenceRule,
      parentId: parentId,
      projectId: projectId,
      reminderAt: reminderAt,
    );
    final created = await _db.getTodoItem(id);
    if (created != null) await _scheduleReminder(created);
    return id;
  }

  Future<void> update({
    required String id,
    required String title,
    String? notes,
    String notesFormat = 'plain',
    DateTime? startDate,
    DateTime? dueDate,
    TaskPriority priority = TaskPriority.none,
    Iterable<String> tags = const [],
    String? recurrenceRule,
    String? parentId,
    String? projectId,
    DateTime? reminderAt,
  }) async {
    final cycle = await _db.wouldCreateTodoCycle(id, parentId);
    if (cycle) {
      throw ArgumentError('A task cannot be nested inside its own subtask.');
    }
    await _db.updateTodoItem(
      id: id,
      title: title,
      notes: notes,
      notesFormat: notesFormat,
      startDate: startDate,
      dueDate: dueDate,
      priority: priority.value,
      tags: TaskTags.encode(tags),
      recurrenceRule: recurrenceRule,
      parentId: parentId,
      projectId: projectId,
      reminderAt: reminderAt,
    );
    final updated = await _db.getTodoItem(id);
    if (updated != null) await _scheduleReminder(updated);
  }

  /// Completes a plain task, or advances a repeating one to its next due date.
  /// The returned date is the new due date when the task repeated.
  Future<DateTime?> toggle(String id, bool completed) async {
    final task = await _db.getTodoItem(id);
    if (task == null) return null;

    if (!completed) {
      await _db.toggleTodoItem(id, false);
      await _scheduleReminder(task.copyWith(completed: false));
      return null;
    }

    final nextDue = nextTodoDueDate(
      dueDate: task.dueDate,
      recurrenceRule: task.recurrenceRule,
      now: AppClock.now(),
    );
    if (nextDue == null) {
      await _db.toggleTodoItem(id, true);
      _notifications?.cancelTaskReminder(id);
      return null;
    }

    // Move the reminder with the due date so a repeating task keeps its lead
    // time instead of firing at the previous occurrence's moment.
    final shift = task.dueDate == null
        ? Duration.zero
        : nextDue.difference(task.dueDate!);
    final reminderAt = task.reminderAt?.add(shift);
    final completedAt = AppClock.now();
    // The due-date advance and its history row must commit together: a crash
    // between them would either lose the completion or show the task as done
    // twice.
    late final String completionId;
    await _db.transaction(() async {
      await _db.updateTodoItem(
        id: task.id,
        title: task.title,
        notes: task.notes,
        notesFormat: task.notesFormat,
        startDate: task.startDate,
        dueDate: nextDue,
        priority: task.priority,
        tags: task.tags,
        recurrenceRule: task.recurrenceRule,
        parentId: task.parentId,
        projectId: task.projectId,
        reminderAt: reminderAt,
      );
      completionId = await _db.addTodoCompletion(
        todoId: task.id,
        occurrenceDue: task.dueDate,
        completedAt: completedAt,
      );
    });
    _undo.offer(
      label: 'to-do completion',
      restore: () async {
        await _db.transaction(() async {
          await _db.deleteTodoCompletion(completionId);
          await _db.updateTodoItem(
            id: task.id,
            title: task.title,
            notes: task.notes,
            notesFormat: task.notesFormat,
            startDate: task.startDate,
            dueDate: task.dueDate,
            priority: task.priority,
            tags: task.tags,
            recurrenceRule: task.recurrenceRule,
            parentId: task.parentId,
            projectId: task.projectId,
            reminderAt: task.reminderAt,
          );
        });
        await _scheduleReminder(task);
      },
    );
    final updated = await _db.getTodoItem(id);
    if (updated != null) await _scheduleReminder(updated);
    return nextDue;
  }

  Future<void> delete(String id) async {
    final descendants = await _db.getTodoDescendants(id);
    await _db.deleteTodoItem(id);
    _notifications?.cancelTaskReminder(id);
    for (final task in descendants) {
      _notifications?.cancelTaskReminder(task.id);
    }
  }

  /// Deletes a task and its nested subtasks, returning the removed subtree so a
  /// caller can offer undo. Rows are ordered parent-first for [restoreSubtree].
  Future<List<TodoItem>> deleteCascade(TodoItem task) async {
    final descendants = await _db.getTodoDescendants(task.id);
    final subtree = <TodoItem>[task, ...descendants];
    await delete(task.id);
    return subtree;
  }

  /// Deleting a parent cascades in SQLite; undo restores the whole subtree so
  /// nested subtasks do not silently vanish.
  Future<void> deleteWithUndo(TodoItem task) async {
    final subtree = await deleteCascade(task);
    _undo.offer(label: 'task', restore: () => restoreSubtree(subtree));
  }

  Future<void> restore(TodoItem task) async {
    await _db.into(_db.todoItems).insert(task);
    await _scheduleReminder(task);
  }

  Future<void> restoreSubtree(List<TodoItem> subtree) async {
    // The descendant query walks breadth-first, so every parent is inserted
    // before the children that reference it.
    await _db.transaction(() async {
      for (final task in subtree) {
        await _db.into(_db.todoItems).insert(task);
      }
    });
    for (final task in subtree) {
      await _scheduleReminder(task);
    }
  }

  /// Rebuilds in-memory task reminders after startup, import or a sync batch.
  Future<void> restoreAllReminders() async {
    final notifications = _notifications;
    if (notifications == null) return;
    notifications.cancelAllTaskReminders();
    final tasks = await _db.watchAllTodoItems().first;
    for (final task in tasks) {
      await _scheduleReminder(task);
    }
  }

  /// Re-arms only the to-dos named by a sync batch. The desktop can receive
  /// large batches; cancelling and rebuilding every task reminder makes the
  /// sync wait on work that did not change.
  Future<void> rescheduleReminders(Iterable<String> taskIds) async {
    final notifications = _notifications;
    if (notifications == null) return;
    for (final id in taskIds) {
      final task = await _db.getTodoItem(id);
      if (task == null) {
        notifications.cancelTaskReminder(id);
      } else {
        await _scheduleReminder(task);
      }
    }
  }

  Future<void> _scheduleReminder(TodoItem task) async {
    final notifications = _notifications;
    if (notifications == null) return;
    final reminder = TaskSchedule.pendingReminder(task, AppClock.now());
    if (reminder == null) {
      notifications.cancelTaskReminder(task.id);
      return;
    }
    await notifications.scheduleTaskReminder(
      taskId: task.id,
      title: task.title,
      scheduledTime: reminder,
      onSkippedLate: onLateTaskReminder == null
          ? null
          : () async {
              onLateTaskReminder!(task.id, task.title, reminder);
            },
    );
  }
}
