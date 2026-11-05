import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/planning/capacity_service.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_engine.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_models.dart';

PlanningTaskSnapshot task({
  required String id,
  String? title,
  bool completed = false,
  int priority = 0,
  DateTime? dueDate,
  DateTime? startDate,
  int? estimatedMinutes,
  bool isImportant = false,
  bool? urgencyOverride,
  PlanningTaskSource source = PlanningTaskSource.todo,
}) {
  return PlanningTaskSnapshot(
    key: PlanningTaskKey(source, id),
    title: title ?? id,
    completed: completed,
    priority: priority,
    dueDate: dueDate,
    startDate: startDate,
    estimatedMinutes: estimatedMinutes,
    isImportant: isImportant,
    urgencyOverride: urgencyOverride,
  );
}

PlanningBlockSnapshot block({
  required String id,
  required String taskId,
  required DateTime start,
  required DateTime end,
  PlanningTaskSource source = PlanningTaskSource.todo,
}) {
  return PlanningBlockSnapshot(
    id: id,
    taskKey: PlanningTaskKey(source, taskId),
    start: start,
    end: end,
  );
}

PlanningDaySnapshot day(
  DateTime date, {
  List<ClockWindow> workingHours = const [ClockWindow(9 * 60, 12 * 60)],
  List<ClockWindow> breaks = const [],
  List<({DateTime start, DateTime end})> busyEvents = const [],
  List<PlanningBlockSnapshot> blocks = const [],
  Map<String, int> plannedMinutesByTask = const {},
}) {
  return PlanningDaySnapshot(
    day: date,
    workingHours: workingHours,
    breaks: breaks,
    busyEvents: busyEvents,
    blocks: blocks,
    plannedMinutesByTask: plannedMinutesByTask,
  );
}

void main() {
  final today = DateTime(2026, 5, 20);
  final tomorrow = DateTime(2026, 5, 21);

  test('identical snapshots produce identical suggestions', () {
    final snapshot = PlanningSnapshot(
      now: today,
      tasks: [task(id: 'a', title: 'A', priority: 0)],
      days: [
        day(
          today,
          workingHours: const [ClockWindow(9 * 60, 10 * 60)],
          blocks: [
            block(
              id: 'b1',
              taskId: 'a',
              start: DateTime(2026, 5, 20, 9),
              end: DateTime(2026, 5, 20, 11),
            ),
          ],
        ),
        day(tomorrow),
      ],
    );

    final first = PlanningEngine.build(snapshot);
    final second = PlanningEngine.build(snapshot);

    expect(
      first.suggestions.map((suggestion) => suggestion.id),
      second.suggestions.map((suggestion) => suggestion.id),
    );
    expect(
      first.suggestions.map(
        (suggestion) => suggestion.reasons.map((r) => r.code),
      ),
      second.suggestions.map(
        (suggestion) => suggestion.reasons.map((r) => r.code),
      ),
    );
    final overcommit = first.suggestions.firstWhere(
      (suggestion) =>
          suggestion.type == PlanningSuggestionType.overcommittedDay,
    );
    expect(overcommit.targetDate, tomorrow);
    expect(
      overcommit.operations
          .whereType<MoveBlockOperation>()
          .single
          .previousStart,
      DateTime(2026, 5, 20, 9),
    );
    expect(
      overcommit.operations.whereType<MoveBlockOperation>().single.newStart,
      DateTime(2026, 5, 21, 9),
    );
    expect(
      overcommit.reasons.map((r) => r.code),
      contains('capacity.overcommitted'),
    );
  });

  test(
    'a task is not double-counted when it has a block and a My Day estimate',
    () {
      final snapshot = PlanningSnapshot(
        now: today,
        tasks: [task(id: 'a', title: 'A')],
        days: [
          day(
            today,
            workingHours: const [ClockWindow(9 * 60, 11 * 60)],
            blocks: [
              block(
                id: 'b1',
                taskId: 'a',
                start: DateTime(2026, 5, 20, 9),
                end: DateTime(2026, 5, 20, 11),
              ),
            ],
            plannedMinutesByTask: const {'todo:a': 120},
          ),
        ],
      );

      final result = PlanningEngine.build(snapshot);
      expect(
        result.suggestions.where(
          (suggestion) =>
              suggestion.type == PlanningSuggestionType.overcommittedDay,
        ),
        isEmpty,
      );
    },
  );

  test('breaks and busy events reduce available capacity', () {
    final snapshot = PlanningSnapshot(
      now: today,
      tasks: [task(id: 'a', title: 'A')],
      days: [
        day(
          today,
          workingHours: const [ClockWindow(9 * 60, 12 * 60)],
          breaks: const [ClockWindow(10 * 60, 10 * 60 + 30)],
          busyEvents: [
            (
              start: DateTime(2026, 5, 20, 11),
              end: DateTime(2026, 5, 20, 11, 30),
            ),
          ],
          blocks: [
            block(
              id: 'b1',
              taskId: 'a',
              start: DateTime(2026, 5, 20, 11),
              end: DateTime(2026, 5, 20, 11, 30),
            ),
          ],
        ),
      ],
    );

    final result = PlanningEngine.build(snapshot);
    // 180 working - 30 break - 30 busy - 30 planned = 90 remaining; no
    // overcommit suggestion should be generated.
    expect(
      result.suggestions.where(
        (suggestion) =>
            suggestion.type == PlanningSuggestionType.overcommittedDay,
      ),
      isEmpty,
    );
  });

  test('carry-forward proposes a date and avoids an existing today item', () {
    final yesterday = DateTime(2026, 5, 19);
    final items = [
      PlanningPlanItemSnapshot(
        id: 'item-1',
        taskKey: const PlanningTaskKey(PlanningTaskSource.todo, 'a'),
        day: yesterday,
        plannedMinutes: 30,
      ),
    ];
    final tasks = [task(id: 'a', title: 'A')];
    final first = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: tasks,
        days: [day(today), day(tomorrow)],
        planItems: items,
      ),
    );
    final carry = first.suggestions.firstWhere(
      (suggestion) => suggestion.type == PlanningSuggestionType.carryForward,
    );
    expect(carry.targetDate, today);
    final operation = carry.operations
        .whereType<MovePlanItemOperation>()
        .single;
    expect(operation.fromDay, yesterday);
    expect(operation.toDay, today);

    final second = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: tasks,
        days: [day(today), day(tomorrow)],
        planItems: [
          ...items,
          PlanningPlanItemSnapshot(
            id: 'item-2',
            taskKey: const PlanningTaskKey(PlanningTaskSource.todo, 'a'),
            day: today,
          ),
        ],
      ),
    );
    expect(
      second.suggestions.where(
        (suggestion) => suggestion.type == PlanningSuggestionType.carryForward,
      ),
      isEmpty,
    );
  });

  test('deadline risk schedules or raises priority without moving dates', () {
    final dueTomorrow = task(
      id: 'a',
      title: 'Due soon',
      dueDate: tomorrow,
      estimatedMinutes: 60,
    );
    final result = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: [dueTomorrow],
        days: [day(today), day(tomorrow)],
      ),
    );
    final deadline = result.suggestions.firstWhere(
      (suggestion) => suggestion.type == PlanningSuggestionType.deadlineRisk,
    );
    expect(deadline.operations.whereType<CreateBlockOperation>(), hasLength(1));
    expect(deadline.reasons.map((r) => r.code), contains('deadline.due'));

    final blocked = task(
      id: 'b',
      title: 'Blocked',
      dueDate: tomorrow,
      estimatedMinutes: 30,
    );
    final blocker = task(id: 'c', title: 'Blocker', priority: 3);
    final blockedResult = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: [blocked, blocker],
        days: [day(today)],
        dependencies: [
          const PlanningDependencySnapshot(
            predecessorTaskKey: PlanningTaskKey(PlanningTaskSource.todo, 'c'),
            successorTaskKey: PlanningTaskKey(PlanningTaskSource.todo, 'b'),
          ),
        ],
      ),
    );
    final blockedSuggestion = blockedResult.suggestions.firstWhere(
      (suggestion) => suggestion.id == 'deadline-priority:todo:b',
    );
    expect(
      blockedSuggestion.operations
          .whereType<UpdateTaskPriorityOperation>()
          .single
          .priority,
      3,
    );
    expect(
      blockedSuggestion.reasons.map((r) => r.code),
      contains('deadline.blocked'),
    );
  });

  test('unscheduled priority uses a fitting free window', () {
    final result = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: [
          task(id: 'a', title: 'Important', priority: 3, estimatedMinutes: 45),
        ],
        days: [day(today)],
      ),
    );
    final suggestion = result.suggestions.firstWhere(
      (suggestion) =>
          suggestion.type == PlanningSuggestionType.unscheduledPriority,
    );
    final operation = suggestion.operations
        .whereType<CreateBlockOperation>()
        .single;
    expect(operation.start, DateTime(2026, 5, 20, 9));
    expect(operation.end, DateTime(2026, 5, 20, 9, 45));
    expect(
      suggestion.reasons.map((r) => r.code),
      contains('priority.unscheduled'),
    );
  });

  test('focus window suggests a candidate for contiguous free time', () {
    final result = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: [task(id: 'a', title: 'Focus task', estimatedMinutes: 30)],
        days: [
          day(
            today,
            workingHours: const [ClockWindow(9 * 60, 12 * 60)],
            busyEvents: [
              (start: DateTime(2026, 5, 20, 9), end: DateTime(2026, 5, 20, 11)),
            ],
          ),
        ],
      ),
    );
    final suggestion = result.suggestions.firstWhere(
      (suggestion) => suggestion.type == PlanningSuggestionType.focusWindow,
    );
    final operation = suggestion.operations
        .whereType<CreateBlockOperation>()
        .single;
    expect(operation.start, DateTime(2026, 5, 20, 11));
    expect(operation.end, DateTime(2026, 5, 20, 11, 30));
    expect(suggestion.reasons.map((r) => r.code), contains('focus.window'));
  });

  test(
    'Eisenhower importance is user-controlled and urgency is explainable',
    () {
      final result = PlanningEngine.build(
        PlanningSnapshot(
          now: today,
          urgencyWindowDays: 3,
          tasks: [
            task(
              id: 'first',
              title: 'Do first',
              dueDate: tomorrow,
              isImportant: true,
            ),
            task(
              id: 'schedule',
              title: 'Schedule',
              dueDate: today.add(const Duration(days: 10)),
              isImportant: true,
            ),
            task(id: 'delegate', title: 'Delegate', dueDate: tomorrow),
            task(id: 'eliminate', title: 'Eliminate'),
            task(
              id: 'override',
              title: 'Override',
              dueDate: today.add(const Duration(days: 10)),
              isImportant: true,
              urgencyOverride: true,
            ),
          ],
          days: [day(today)],
        ),
      );
      final matrix = result.matrix;
      expect(matrix.urgencyWindowDays, 3);
      expect(
        matrix.doFirst.map((item) => item.task.title),
        contains('Do first'),
      );
      expect(
        matrix.schedule.map((item) => item.task.title),
        contains('Schedule'),
      );
      expect(
        matrix.delegate.map((item) => item.task.title),
        contains('Delegate'),
      );
      expect(
        matrix.eliminate.map((item) => item.task.title),
        contains('Eliminate'),
      );
      expect(
        matrix.doFirst
            .firstWhere((item) => item.task.title == 'Do first')
            .urgencyReason,
        contains('Due in 1 day'),
      );
      final override = matrix.doFirst.firstWhere(
        (item) => item.task.title == 'Override',
      );
      expect(override.urgencyIsOverride, isTrue);
      expect(override.urgencyReason, contains('Manually marked'));
    },
  );

  test('weekly review preserves denominators and date range', () {
    final result = PlanningEngine.build(
      PlanningSnapshot(
        now: today,
        tasks: const [],
        days: const [],
        weeklyReview: WeeklyReviewInput(
          from: DateTime(2026, 5, 18),
          to: today,
          completedOccurrences: 5,
          completedDistinctTasks: 3,
          projectTasksCompleted: 2,
          carriedTasks: 4,
          overdueTasks: 2,
          focusMinutes: 150,
          focusSessions: 3,
          habitCompletions: 8,
          habitPossible: 20,
          milestonesCompleted: 1,
          milestonesDue: 3,
        ),
      ),
    );
    final review = result.weeklyReview!;
    expect(review.completedTasks, 7);
    expect(review.habitRate, 0.4);
    expect(review.from, DateTime(2026, 5, 18));
    expect(review.to, today);
    expect(
      result.suggestions.map((suggestion) => suggestion.type),
      contains(PlanningSuggestionType.weeklyReview),
    );
  });
}
