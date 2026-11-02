import '../../../core/utils/day_agenda.dart';
import '../../../core/utils/day_math.dart';

/// A local calendar day rendered as the stable `YYYY-MM-DD` key stored in
/// `daily_plans.day_key`. Time of day and time zone are deliberately ignored.
String myDayKey(DateTime day) {
  final date = DayMath.dateOnly(day);
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final dayOfMonth = date.day.toString().padLeft(2, '0');
  return '$year-$month-$dayOfMonth';
}

/// Which existing task table a planned or suggested task comes from.
enum PlannedTaskSource { todo, projectTask }

/// Why a task appears in the suggestion list.
enum SuggestedReason {
  overdue('Overdue'),
  dueToday('Due today'),
  highPriority('High priority'),
  noDate('No date');

  const SuggestedReason(this.label);

  final String label;
}

/// One task explicitly planned for a day, joined with its original task row.
///
/// The plan stores only the association, ordering and optional estimate; the
/// title, completion flag, priority and due date always come from the task.
class PlannedTaskView {
  const PlannedTaskView({
    required this.planItemId,
    required this.taskId,
    required this.title,
    required this.source,
    required this.completed,
    required this.sortOrder,
    required this.priority,
    this.doneToday = false,
    this.plannedMinutes,
    this.dueDate,
    this.projectId,
    this.projectName,
  });

  final String planItemId;
  final String taskId;
  final String title;
  final PlannedTaskSource source;
  final bool completed;

  /// A recurring task completed on this plan's day. The task row itself stays
  /// incomplete because its due date moved on.
  final bool doneToday;
  final int sortOrder;
  final int priority;
  final int? plannedMinutes;
  final DateTime? dueDate;
  final String? projectId;
  final String? projectName;
}

/// A task that is not planned yet but might be worth adding to the day.
class SuggestedTaskView {
  const SuggestedTaskView({
    required this.taskId,
    required this.title,
    required this.source,
    required this.reason,
    required this.priority,
    this.dueDate,
    this.projectId,
    this.projectName,
  });

  final String taskId;
  final String title;
  final PlannedTaskSource source;
  final SuggestedReason reason;
  final int priority;
  final DateTime? dueDate;
  final String? projectId;
  final String? projectName;
}

/// A task shown in the searchable picker. [alreadyPlanned] lets the picker
/// disable rows that are already on the selected day without hiding them.
class PlannableTaskView {
  const PlannableTaskView({
    required this.taskId,
    required this.title,
    required this.source,
    required this.alreadyPlanned,
    required this.priority,
    this.dueDate,
    this.projectId,
    this.projectName,
  });

  final String taskId;
  final String title;
  final PlannedTaskSource source;
  final bool alreadyPlanned;
  final int priority;
  final DateTime? dueDate;
  final String? projectId;
  final String? projectName;
}

/// Everything the My Day UI renders for one calendar day.
class DailyPlanView {
  const DailyPlanView({
    required this.day,
    required this.intention,
    required this.items,
    required this.suggestions,
    required this.events,
    this.planId,
  });

  final DateTime day;

  /// Null until the first edit creates the plan row.
  final String? planId;
  final String intention;
  final List<PlannedTaskView> items;
  final List<SuggestedTaskView> suggestions;
  final List<AgendaEntry> events;

  int get completedCount =>
      items.where((item) => item.completed || item.doneToday).length;

  int get unfinishedCount => items.length - completedCount;

  /// Sum of the estimates the user actually provided. Unknown durations are
  /// never treated as zero; they are counted separately.
  int get knownMinutes =>
      items.fold<int>(0, (total, item) => total + (item.plannedMinutes ?? 0));

  int get unknownEstimateCount =>
      items.where((item) => item.plannedMinutes == null).length;

  int get completedMinutes => items
      .where((item) => item.completed || item.doneToday)
      .fold<int>(0, (total, item) => total + (item.plannedMinutes ?? 0));

  bool get isEmpty => planId == null && intention.isEmpty && items.isEmpty;
}
