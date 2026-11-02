import 'package:uuid/uuid.dart';

import 'day_math.dart';

/// Deterministic row ids for facts whose natural key is shared by every device.
///
/// Two devices that create the same habit log, daily plan or plan item while
/// offline must end up with the same primary key; otherwise a unique index
/// turns the second row into a permanently rejected sync change. UUIDv5 derives
/// the id from the natural key with one namespace shared by the whole app, so
/// every device computes the same value without coordination.
class SyncIds {
  const SyncIds._();

  /// Fixed namespace for every deterministic Locus id. Never change it: doing
  /// so would make existing rows look like new ones after an upgrade.
  static const namespace = 'd1f22a2e-3c4a-5b96-9e0f-1a2b3c4d5e6f';

  static final Uuid _uuid = const Uuid();

  static String _dayKey(DateTime day) {
    final local = DayMath.dateOnly(day);
    final year = local.year.toString().padLeft(4, '0');
    final month = local.month.toString().padLeft(2, '0');
    final dayOfMonth = local.day.toString().padLeft(2, '0');
    return '$year-$month-$dayOfMonth';
  }

  /// One habit log row per (habit, local calendar day).
  static String habitLogId(String habitId, DateTime day) =>
      _uuid.v5(namespace, 'habit_log:$habitId:${_dayKey(day)}');

  /// One daily plan row per local calendar day.
  static String dailyPlanId(DateTime day) =>
      _uuid.v5(namespace, 'daily_plan:${_dayKey(day)}');

  /// One plan item per planned task inside a plan. Exactly one of [todoItemId]
  /// and [projectTaskId] must be set, matching the table's CHECK constraint.
  static String dailyPlanItemId({
    required String planId,
    String? todoItemId,
    String? projectTaskId,
  }) {
    if ((todoItemId == null) == (projectTaskId == null)) {
      throw ArgumentError('Exactly one plan item task reference is required.');
    }
    final seed = todoItemId != null
        ? 'daily_plan_item:$planId:todo:$todoItemId'
        : 'daily_plan_item:$planId:task:$projectTaskId';
    return _uuid.v5(namespace, seed);
  }
}
