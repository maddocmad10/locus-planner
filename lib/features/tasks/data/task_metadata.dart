import 'dart:convert';

import '../../../core/db/app_database.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/recurrence.dart';

/// Visual and ordering importance of a to-do. The stored value is stable for
/// backups and sync, so it must not depend on enum declaration order.
enum TaskPriority {
  none(0, 'None'),
  low(1, 'Low'),
  medium(2, 'Medium'),
  high(3, 'High');

  const TaskPriority(this.value, this.label);

  final int value;
  final String label;

  static TaskPriority fromValue(int? value) => values.firstWhere(
    (priority) => priority.value == value,
    orElse: () => TaskPriority.none,
  );

  static TaskPriority fromStorage(int? value) {
    if (value == null) return TaskPriority.none;
    final clamped = value.clamp(0, 3).toInt();
    return fromValue(clamped);
  }
}

/// Helpers for the free-form tag set stored in `todo_items.tags`.
///
/// The canonical form is a JSON array so names containing commas survive. A
/// plain comma-separated string is still accepted when reading, which keeps
/// hand-edited and older values usable.
class TaskTags {
  static const empty = '[]';
  static const maxTagLength = 32;
  static const maxTags = 12;

  static List<String> decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      try {
        final value = jsonDecode(trimmed);
        if (value is! List) return const [];
        return normalize(value.whereType<String>());
      } catch (_) {
        return const [];
      }
    }
    return normalize(trimmed.split(','));
  }

  static String encode(Iterable<String> tags) => jsonEncode(normalize(tags));

  /// Normalises user input: trims, drops empties, removes case-insensitive
  /// duplicates and caps both the number and the length of tags.
  static List<String> normalize(Iterable<String> tags) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in tags) {
      var tag = raw.trim();
      if (tag.isEmpty) continue;
      if (tag.length > maxTagLength) {
        tag = tag.substring(0, maxTagLength).trimRight();
      }
      if (tag.isEmpty || !seen.add(tag.toLowerCase())) continue;
      result.add(tag);
      if (result.length == maxTags) break;
    }
    return result;
  }

  static List<String> fromInput(String input) => normalize(input.split(','));

  static String toInput(Iterable<String> tags) => tags.join(', ');
}

/// Next due date after completing a repeating to-do.
///
/// [now] prevents an overdue daily task from reappearing in the past: the next
/// occurrence is calculated after the later of the current due date and now.
/// Returns null when the task does not repeat or has no due date to advance.
DateTime? nextTodoDueDate({
  required DateTime? dueDate,
  required String? recurrenceRule,
  required DateTime now,
}) {
  if (dueDate == null || !Recurrence.isRecurring(recurrenceRule)) return null;
  final pivot = dueDate.isAfter(now) ? dueDate : now;
  return Recurrence.next(dueDate, recurrenceRule, from: pivot);
}

/// Scheduling semantics shared by the Tasks screen, filters and reminders.
///
/// A task is "scheduled" as soon as it has a start date, a due date or both.
/// With neither it is explicitly unscheduled, which is what the Unscheduled
/// filter and the All view's grouping surface.
class TaskSchedule {
  const TaskSchedule._();

  static bool isScheduled(TodoItem task) =>
      task.startDate != null || task.dueDate != null;

  static bool isOverdue(TodoItem task, DateTime now) {
    final due = task.dueDate;
    if (task.completed || due == null) return false;
    return DayMath.calendarDaysBetween(now, due) < 0;
  }

  static bool isToday(TodoItem task, DateTime now) {
    if (task.completed) return false;
    final start = task.startDate;
    final due = task.dueDate;
    return (start != null && DayMath.calendarDaysBetween(start, now) == 0) ||
        (due != null && DayMath.calendarDaysBetween(due, now) == 0);
  }

  /// Later this week, not counting today and never for an overdue task.
  static bool isUpcoming(TodoItem task, DateTime now) {
    if (task.completed) return false;
    final due = task.dueDate;
    if (due != null) {
      final days = DayMath.calendarDaysBetween(now, due);
      return days >= 1 && days <= 7;
    }
    final start = task.startDate;
    if (start == null) return false;
    final days = DayMath.calendarDaysBetween(now, start);
    return days >= 1 && days <= 7;
  }

  /// A moment to show a reminder, or null when it is in the past or absent.
  static DateTime? pendingReminder(TodoItem task, DateTime now) {
    final reminder = task.reminderAt;
    if (task.completed || reminder == null || !reminder.isAfter(now)) {
      return null;
    }
    return reminder;
  }
}

/// The filter strip above the task list.
enum TaskFilter {
  all('All'),
  today('Today'),
  overdue('Overdue'),
  upcoming('Upcoming'),
  highPriority('High Priority'),
  completed('Completed'),
  unscheduled('Unscheduled');

  const TaskFilter(this.label);

  final String label;

  bool matches(TodoItem task, DateTime now) {
    switch (this) {
      case TaskFilter.all:
        return true;
      case TaskFilter.completed:
        return task.completed;
      case TaskFilter.highPriority:
        return !task.completed &&
            TaskPriority.fromStorage(task.priority) == TaskPriority.high;
      case TaskFilter.unscheduled:
        return !TaskSchedule.isScheduled(task);
      case TaskFilter.today:
        return TaskSchedule.isToday(task, now);
      case TaskFilter.overdue:
        return TaskSchedule.isOverdue(task, now);
      case TaskFilter.upcoming:
        return TaskSchedule.isUpcoming(task, now);
    }
  }
}

/// A task plus its nested subtasks, ready for indented rendering.
class TaskNode {
  const TaskNode({required this.task, required this.children});

  final TodoItem task;
  final List<TaskNode> children;

  bool get hasChildren => children.isNotEmpty;
}

/// Builds the parent/child tree in the order [tasks] arrived (the database
/// already orders by completion, priority and age).
///
/// Tasks whose parent is missing become roots instead of disappearing, and a
/// malformed cycle is broken by promoting the first revisited task to a root.
/// When [include] is supplied, a node is kept only if it or one of its
/// descendants matches, so filtered views still show the path to a match.
List<TaskNode> buildTaskTree(
  List<TodoItem> tasks, {
  bool Function(TodoItem task)? include,
}) {
  final byId = <String, TodoItem>{for (final task in tasks) task.id: task};
  final children = <String, List<TodoItem>>{};
  final rootIds = <String>[];

  for (final task in tasks) {
    final parentId = task.parentId;
    if (parentId == null || !byId.containsKey(parentId)) {
      rootIds.add(task.id);
    } else {
      children.putIfAbsent(parentId, () => []).add(task);
    }
  }

  final visited = <String>{};
  TaskNode? visit(TodoItem task) {
    if (!visited.add(task.id)) return null;
    final nested = <TaskNode>[];
    for (final child in children[task.id] ?? const <TodoItem>[]) {
      final node = visit(child);
      if (node != null) nested.add(node);
    }
    if (include != null && !include(task) && nested.isEmpty) {
      return null;
    }
    return TaskNode(task: task, children: nested);
  }

  final roots = <TaskNode>[];
  for (final id in rootIds) {
    final node = visit(byId[id]!);
    if (node != null) roots.add(node);
  }

  // Any task not reached from a declared root sits inside a cycle. Promote it
  // so the user can still see and fix it.
  for (final task in tasks) {
    if (visited.contains(task.id)) continue;
    final node = visit(task);
    if (node != null) roots.add(node);
  }
  return roots;
}
