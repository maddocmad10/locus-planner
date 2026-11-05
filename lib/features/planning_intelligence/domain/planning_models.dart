import '../../../core/planning/capacity_service.dart';

/// Where a planning task comes from. Personal to-dos and project checklist
/// tasks keep separate tables and separate repositories; the planner only
/// needs a stable key.
enum PlanningTaskSource { todo, project }

class PlanningTaskKey {
  const PlanningTaskKey(this.source, this.id);

  final PlanningTaskSource source;
  final String id;

  String get value =>
      source == PlanningTaskSource.todo ? 'todo:$id' : 'task:$id';

  static PlanningTaskKey? parse(String value) {
    if (value.startsWith('todo:')) {
      return PlanningTaskKey(PlanningTaskSource.todo, value.substring(5));
    }
    if (value.startsWith('task:')) {
      return PlanningTaskKey(PlanningTaskSource.project, value.substring(5));
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PlanningTaskKey && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => value;
}

class PlanningTaskSnapshot {
  const PlanningTaskSnapshot({
    required this.key,
    required this.title,
    required this.completed,
    required this.priority,
    this.dueDate,
    this.startDate,
    this.estimatedMinutes,
    this.isImportant = false,
    this.urgencyOverride,
    this.projectId,
    this.projectName,
  });

  final PlanningTaskKey key;
  final String title;
  final bool completed;
  final int priority;
  final DateTime? dueDate;
  final DateTime? startDate;
  final int? estimatedMinutes;
  final bool isImportant;
  final bool? urgencyOverride;
  final String? projectId;
  final String? projectName;
}

class PlanningPlanItemSnapshot {
  const PlanningPlanItemSnapshot({
    required this.id,
    required this.taskKey,
    required this.day,
    this.plannedMinutes,
  });

  final String id;
  final PlanningTaskKey taskKey;
  final DateTime day;
  final int? plannedMinutes;
}

class PlanningBlockSnapshot {
  const PlanningBlockSnapshot({
    required this.id,
    required this.taskKey,
    required this.start,
    required this.end,
    this.kind = 'work',
  });

  final String id;
  final PlanningTaskKey taskKey;
  final DateTime start;
  final DateTime end;
  final String kind;

  int get minutes => end.difference(start).inMinutes;
}

class PlanningDaySnapshot {
  const PlanningDaySnapshot({
    required this.day,
    this.workingHours = const [],
    this.breaks = const [],
    this.busyEvents = const [],
    this.blocks = const [],
    this.plannedMinutesByTask = const {},
  });

  final DateTime day;
  final List<ClockWindow> workingHours;
  final List<ClockWindow> breaks;
  final List<({DateTime start, DateTime end})> busyEvents;
  final List<PlanningBlockSnapshot> blocks;
  final Map<String, int> plannedMinutesByTask;
}

class PlanningDependencySnapshot {
  const PlanningDependencySnapshot({
    required this.predecessorTaskKey,
    required this.successorTaskKey,
  });

  final PlanningTaskKey predecessorTaskKey;
  final PlanningTaskKey successorTaskKey;
}

class WeeklyReviewInput {
  const WeeklyReviewInput({
    required this.from,
    required this.to,
    this.completedOccurrences = 0,
    this.completedDistinctTasks = 0,
    this.projectTasksCompleted = 0,
    this.carriedTasks = 0,
    this.overdueTasks = 0,
    this.focusMinutes = 0,
    this.focusSessions = 0,
    this.habitCompletions = 0,
    this.habitPossible = 0,
    this.milestonesCompleted = 0,
    this.milestonesDue = 0,
  });

  final DateTime from;
  final DateTime to;
  final int completedOccurrences;
  final int completedDistinctTasks;
  final int projectTasksCompleted;
  final int carriedTasks;
  final int overdueTasks;
  final int focusMinutes;
  final int focusSessions;
  final int habitCompletions;
  final int habitPossible;
  final int milestonesCompleted;
  final int milestonesDue;

  int get completedTasks => completedOccurrences + projectTasksCompleted;
}

class PlanningSnapshot {
  const PlanningSnapshot({
    required this.now,
    required this.tasks,
    required this.days,
    this.planItems = const [],
    this.dependencies = const [],
    this.weeklyReview,
    this.bufferMinutes = 0,
    this.overcommitThresholdPercent = 100,
    this.urgencyWindowDays = 3,
    this.defaultSlotMinutes = 30,
  });

  final DateTime now;
  final List<PlanningTaskSnapshot> tasks;
  final List<PlanningDaySnapshot> days;
  final List<PlanningPlanItemSnapshot> planItems;
  final List<PlanningDependencySnapshot> dependencies;
  final WeeklyReviewInput? weeklyReview;
  final int bufferMinutes;
  final int overcommitThresholdPercent;
  final int urgencyWindowDays;
  final int defaultSlotMinutes;
}

enum PlanningSuggestionType {
  overcommittedDay,
  carryForward,
  deadlineRisk,
  unscheduledPriority,
  focusWindow,
  weeklyReview,
}

enum EisenhowerQuadrant { doFirst, schedule, delegate, eliminate }

class PlanningReason {
  const PlanningReason(this.code, this.message);
  final String code;
  final String message;
}

class PlanningReference {
  const PlanningReference({
    required this.kind,
    required this.id,
    required this.label,
  });

  final String kind;
  final String id;
  final String label;
}

/// A concrete proposed mutation. The engine produces these; only the
/// repository executes them, inside one transaction, after the user applies
/// the suggestion.
sealed class PlanningOperation {
  const PlanningOperation();
}

class MoveBlockOperation extends PlanningOperation {
  const MoveBlockOperation({
    required this.blockId,
    required this.previousStart,
    required this.previousEnd,
    required this.newStart,
    required this.newEnd,
  });
  final String blockId;
  final DateTime previousStart;
  final DateTime previousEnd;
  final DateTime newStart;
  final DateTime newEnd;
}

class CreateBlockOperation extends PlanningOperation {
  const CreateBlockOperation({
    required this.taskKey,
    required this.start,
    required this.end,
  });
  final PlanningTaskKey taskKey;
  final DateTime start;
  final DateTime end;
}

class MovePlanItemOperation extends PlanningOperation {
  const MovePlanItemOperation({
    required this.planItemId,
    required this.fromDay,
    required this.toDay,
  });
  final String planItemId;
  final DateTime fromDay;
  final DateTime toDay;
}

class UpdateTaskFlagsOperation extends PlanningOperation {
  const UpdateTaskFlagsOperation({
    required this.taskKey,
    required this.previousImportant,
    required this.previousUrgencyOverride,
    this.isImportant,
    this.urgencyOverride,
    this.clearUrgencyOverride = false,
  });
  final PlanningTaskKey taskKey;
  final bool previousImportant;
  final bool? previousUrgencyOverride;
  final bool? isImportant;
  final bool? urgencyOverride;
  final bool clearUrgencyOverride;
}

class UpdateTaskPriorityOperation extends PlanningOperation {
  const UpdateTaskPriorityOperation({
    required this.taskKey,
    required this.previousPriority,
    required this.priority,
  });
  final PlanningTaskKey taskKey;
  final int previousPriority;
  final int priority;
}

class PlanningSuggestion {
  const PlanningSuggestion({
    required this.id,
    required this.type,
    required this.title,
    required this.explanation,
    required this.reasons,
    required this.references,
    this.operations = const [],
    this.targetDate,
    this.actionable = true,
  });

  final String id;
  final PlanningSuggestionType type;
  final String title;
  final String explanation;
  final List<PlanningReason> reasons;
  final List<PlanningReference> references;
  final List<PlanningOperation> operations;
  final DateTime? targetDate;
  final bool actionable;

  bool get hasMutations => operations.isNotEmpty;
}

class EisenhowerItem {
  const EisenhowerItem({
    required this.task,
    required this.quadrant,
    required this.urgent,
    required this.important,
    required this.urgencyReason,
    required this.urgencyIsOverride,
  });

  final PlanningTaskSnapshot task;
  final EisenhowerQuadrant quadrant;
  final bool urgent;
  final bool important;
  final String urgencyReason;
  final bool urgencyIsOverride;
}

class EisenhowerResult {
  const EisenhowerResult({
    required this.doFirst,
    required this.schedule,
    required this.delegate,
    required this.eliminate,
    required this.urgencyWindowDays,
  });

  final List<EisenhowerItem> doFirst;
  final List<EisenhowerItem> schedule;
  final List<EisenhowerItem> delegate;
  final List<EisenhowerItem> eliminate;
  final int urgencyWindowDays;

  List<EisenhowerItem> forQuadrant(EisenhowerQuadrant quadrant) =>
      switch (quadrant) {
        EisenhowerQuadrant.doFirst => doFirst,
        EisenhowerQuadrant.schedule => schedule,
        EisenhowerQuadrant.delegate => delegate,
        EisenhowerQuadrant.eliminate => eliminate,
      };
}

class WeeklyReviewResult {
  const WeeklyReviewResult({
    required this.from,
    required this.to,
    required this.completedTasks,
    required this.completedOccurrences,
    required this.projectTasksCompleted,
    required this.carriedTasks,
    required this.overdueTasks,
    required this.focusMinutes,
    required this.focusSessions,
    required this.habitCompletions,
    required this.habitPossible,
    required this.milestonesCompleted,
    required this.milestonesDue,
  });

  final DateTime from;
  final DateTime to;
  final int completedTasks;
  final int completedOccurrences;
  final int projectTasksCompleted;
  final int carriedTasks;
  final int overdueTasks;
  final int focusMinutes;
  final int focusSessions;
  final int habitCompletions;
  final int habitPossible;
  final int milestonesCompleted;
  final int milestonesDue;

  double? get habitRate =>
      habitPossible == 0 ? null : habitCompletions / habitPossible;

  bool get hasData =>
      completedTasks > 0 ||
      carriedTasks > 0 ||
      overdueTasks > 0 ||
      focusMinutes > 0 ||
      habitCompletions > 0 ||
      milestonesCompleted > 0 ||
      milestonesDue > 0;
}

class PlanningResult {
  const PlanningResult({
    required this.suggestions,
    required this.matrix,
    required this.weeklyReview,
  });

  final List<PlanningSuggestion> suggestions;
  final EisenhowerResult matrix;
  final WeeklyReviewResult? weeklyReview;
}
