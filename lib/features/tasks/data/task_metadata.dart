import 'dart:convert';

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
