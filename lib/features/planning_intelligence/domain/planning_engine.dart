import '../../../core/planning/capacity_service.dart';
import '../../../core/utils/day_math.dart';
import 'planning_models.dart';

/// Pure, deterministic planning heuristics.
///
/// The engine never reads the database or the clock. It receives an immutable
/// snapshot and returns suggestions plus the Eisenhower matrix and weekly
/// review. Identical snapshots always produce identical output.
abstract final class PlanningEngine {
  static PlanningResult build(PlanningSnapshot snapshot) {
    final today = DayMath.dateOnly(snapshot.now);
    final taskByKey = {for (final task in snapshot.tasks) task.key: task};
    final dayByDate = {
      for (final day in snapshot.days) DayMath.dateOnly(day.day): day,
    };
    final summaries = <DateTime, CapacitySummary>{
      for (final day in snapshot.days)
        DayMath.dateOnly(day.day): _summary(snapshot, day),
    };
    final remainingByDay = <DateTime, int>{
      for (final entry in summaries.entries)
        entry.key: entry.value.remainingMinutes,
    };
    final scheduledKeys = <PlanningTaskKey>{};

    final suggestions = <PlanningSuggestion>[
      ..._carryForward(snapshot, today, taskByKey),
      ..._overcommitted(
        snapshot,
        today,
        taskByKey,
        dayByDate,
        summaries,
        remainingByDay,
        scheduledKeys,
      ),
      ..._deadlineRisk(
        snapshot,
        today,
        taskByKey,
        dayByDate,
        remainingByDay,
        scheduledKeys,
      ),
      ..._unscheduledPriority(
        snapshot,
        today,
        taskByKey,
        dayByDate,
        remainingByDay,
        scheduledKeys,
      ),
      ..._focusWindows(
        snapshot,
        today,
        taskByKey,
        dayByDate,
        remainingByDay,
        scheduledKeys,
      ),
    ];

    final weekly = _weeklyReview(snapshot.weeklyReview);
    if (weekly != null && weekly.hasData) {
      suggestions.add(
        PlanningSuggestion(
          id: 'weekly-review:${_dayKey(weekly.from)}:${_dayKey(weekly.to)}',
          type: PlanningSuggestionType.weeklyReview,
          title: 'Weekly review ready',
          explanation:
              '${weekly.completedTasks} completed, ${weekly.carriedTasks} '
              'carried, ${weekly.overdueTasks} overdue. All metrics are '
              'computed from local rows for '
              '${_dayKey(weekly.from)} to ${_dayKey(weekly.to)}.',
          reasons: const [
            PlanningReason(
              'weekly.summary',
              'Weekly review is informational; opening it changes nothing.',
            ),
          ],
          references: const [],
          actionable: false,
        ),
      );
    }

    suggestions.sort(_compareSuggestions);
    return PlanningResult(
      suggestions: suggestions,
      matrix: _matrix(snapshot, today),
      weeklyReview: weekly,
    );
  }

  static int _compareSuggestions(PlanningSuggestion a, PlanningSuggestion b) {
    final type = _typeRank(a.type).compareTo(_typeRank(b.type));
    if (type != 0) return type;
    final dateA = a.targetDate ?? DateTime(9999);
    final dateB = b.targetDate ?? DateTime(9999);
    final date = dateA.compareTo(dateB);
    if (date != 0) return date;
    return a.id.compareTo(b.id);
  }

  static int _typeRank(PlanningSuggestionType type) => switch (type) {
    PlanningSuggestionType.overcommittedDay => 0,
    PlanningSuggestionType.carryForward => 1,
    PlanningSuggestionType.deadlineRisk => 2,
    PlanningSuggestionType.unscheduledPriority => 3,
    PlanningSuggestionType.focusWindow => 4,
    PlanningSuggestionType.weeklyReview => 5,
  };

  static CapacitySummary _summary(
    PlanningSnapshot snapshot,
    PlanningDaySnapshot day,
  ) {
    return CapacityService.summarize(
      CapacityInput(
        day: day.day,
        workingHours: day.workingHours,
        breaks: day.breaks,
        busyEvents: day.busyEvents,
        blocks: [
          for (final block in day.blocks)
            BookedInterval(
              taskKey: block.taskKey.value,
              start: block.start,
              end: block.end,
            ),
        ],
        plannedMinutesByTask: day.plannedMinutesByTask,
        bufferMinutes: snapshot.bufferMinutes,
        overcommitThresholdPercent: snapshot.overcommitThresholdPercent,
      ),
    );
  }

  // ==================== OVERCOMMITTED DAY ====================

  static List<PlanningSuggestion> _overcommitted(
    PlanningSnapshot snapshot,
    DateTime today,
    Map<PlanningTaskKey, PlanningTaskSnapshot> taskByKey,
    Map<DateTime, PlanningDaySnapshot> dayByDate,
    Map<DateTime, CapacitySummary> summaries,
    Map<DateTime, int> remainingByDay,
    Set<PlanningTaskKey> scheduledKeys,
  ) {
    final suggestions = <PlanningSuggestion>[];
    final days = dayByDate.keys.toList()..sort();
    for (final day in days) {
      final summary = summaries[day]!;
      if (!summary.isOvercommitted) continue;
      var created = 0;
      final candidates = summary.taskMinutes.keys.toList()
        ..sort((a, b) {
          final taskA = taskByKey[PlanningTaskKey.parse(a)];
          final taskB = taskByKey[PlanningTaskKey.parse(b)];
          final priority = (taskA?.priority ?? 0).compareTo(
            taskB?.priority ?? 0,
          );
          if (priority != 0) return priority;
          return a.compareTo(b);
        });

      for (final taskKeyValue in candidates) {
        if (created >= 3) break;
        final taskKey = PlanningTaskKey.parse(taskKeyValue);
        if (taskKey == null) continue;
        final task = taskByKey[taskKey];
        if (task == null || task.completed) continue;

        final block = dayByDate[day]!.blocks
            .where((candidate) => candidate.taskKey == taskKey)
            .firstOrNull;
        final planItem = snapshot.planItems
            .where(
              (item) =>
                  item.taskKey == taskKey && DayMath.dateOnly(item.day) == day,
            )
            .firstOrNull;
        final minutes = block?.minutes ?? planItem?.plannedMinutes ?? 0;
        if (minutes <= 0) continue;

        final target = _firstTargetDay(
          days,
          after: day,
          minutes: minutes,
          dayByDate: dayByDate,
          remainingByDay: remainingByDay,
          notAfter: task.dueDate,
        );
        if (target == null) continue;
        final slot = _firstFreeSlot(dayByDate[target]!, minutes);
        if (slot == null) continue;

        final operations = <PlanningOperation>[];
        if (block != null) {
          operations.add(
            MoveBlockOperation(
              blockId: block.id,
              previousStart: block.start,
              previousEnd: block.end,
              newStart: slot.start,
              newEnd: slot.start.add(Duration(minutes: minutes)),
            ),
          );
        } else if (planItem != null) {
          operations.add(
            MovePlanItemOperation(
              planItemId: planItem.id,
              fromDay: day,
              toDay: target,
            ),
          );
        }
        if (operations.isEmpty) continue;

        scheduledKeys.add(taskKey);
        final left = remainingByDay[target]! - minutes;
        remainingByDay[target] = left;
        created++;
        suggestions.add(
          PlanningSuggestion(
            id: 'overcommitted:${_dayKey(day)}:${taskKey.value}',
            type: PlanningSuggestionType.overcommittedDay,
            title: 'Move "${task.title}" to ${_shortDay(target)}',
            explanation:
                '${_shortDay(day)} has ${summary.plannedMinutes} planned '
                'minutes against ${summary.availableMinutes} available. '
                'Moving this $minutes-minute task to ${_shortDay(target)} '
                'leaves that day with $left minutes free.',
            reasons: [
              PlanningReason(
                'capacity.overcommitted',
                'Planned effort exceeds available capacity on '
                    '${_shortDay(day)}.',
              ),
              PlanningReason(
                'capacity.target',
                '${_shortDay(target)} has room for $minutes minutes.',
              ),
            ],
            references: [
              PlanningReference(
                kind: 'task',
                id: taskKey.value,
                label: task.title,
              ),
              if (block != null)
                PlanningReference(
                  kind: 'schedule_block',
                  id: block.id,
                  label: '${_shortDay(day)} block',
                ),
              if (planItem != null)
                PlanningReference(
                  kind: 'plan_item',
                  id: planItem.id,
                  label: '${_shortDay(day)} My Day item',
                ),
            ],
            operations: operations,
            targetDate: target,
          ),
        );
      }
    }
    return suggestions;
  }

  // ==================== CARRY FORWARD ====================

  static List<PlanningSuggestion> _carryForward(
    PlanningSnapshot snapshot,
    DateTime today,
    Map<PlanningTaskKey, PlanningTaskSnapshot> taskByKey,
  ) {
    final todayItems = snapshot.planItems
        .where((item) => DayMath.dateOnly(item.day) == today)
        .map((item) => item.taskKey)
        .toSet();
    final suggestions = <PlanningSuggestion>[];
    final seen = <PlanningTaskKey>{};
    final earliest = DayMath.addDays(today, -7);
    final items =
        snapshot.planItems
            .where(
              (item) =>
                  DayMath.dateOnly(item.day).isBefore(today) &&
                  !DayMath.dateOnly(item.day).isBefore(earliest),
            )
            .toList()
          ..sort((a, b) {
            final day = a.day.compareTo(b.day);
            return day != 0 ? day : a.id.compareTo(b.id);
          });

    for (final item in items) {
      final task = taskByKey[item.taskKey];
      if (task == null || task.completed) continue;
      if (todayItems.contains(item.taskKey) || !seen.add(item.taskKey)) {
        continue;
      }
      suggestions.add(
        PlanningSuggestion(
          id: 'carry-forward:${item.id}',
          type: PlanningSuggestionType.carryForward,
          title: 'Carry "${task.title}" to today',
          explanation:
              '"${task.title}" was planned for ${_shortDay(item.day)} and is '
              'still open. Move it to today, choose another date, or remove it '
              'from the plan. The task row itself is never duplicated.',
          reasons: const [
            PlanningReason(
              'carry.incomplete',
              'An unfinished My Day item remains from a previous day.',
            ),
          ],
          references: [
            PlanningReference(
              kind: 'plan_item',
              id: item.id,
              label: '${_shortDay(item.day)} plan item',
            ),
            PlanningReference(
              kind: 'task',
              id: task.key.value,
              label: task.title,
            ),
          ],
          operations: [
            MovePlanItemOperation(
              planItemId: item.id,
              fromDay: item.day,
              toDay: today,
            ),
          ],
          targetDate: today,
        ),
      );
      if (suggestions.length >= 8) break;
    }
    return suggestions;
  }

  // ==================== DEADLINE RISK ====================

  static List<PlanningSuggestion> _deadlineRisk(
    PlanningSnapshot snapshot,
    DateTime today,
    Map<PlanningTaskKey, PlanningTaskSnapshot> taskByKey,
    Map<DateTime, PlanningDaySnapshot> dayByDate,
    Map<DateTime, int> remainingByDay,
    Set<PlanningTaskKey> scheduledKeys,
  ) {
    final suggestions = <PlanningSuggestion>[];
    final horizon = DayMath.addDays(today, 7);
    final tasks =
        snapshot.tasks
            .where(
              (task) =>
                  !task.completed &&
                  task.dueDate != null &&
                  !DayMath.dateOnly(task.dueDate!).isAfter(horizon),
            )
            .toList()
          ..sort((a, b) {
            final due = a.dueDate!.compareTo(b.dueDate!);
            if (due != 0) return due;
            final priority = b.priority.compareTo(a.priority);
            return priority != 0
                ? priority
                : a.key.value.compareTo(b.key.value);
          });

    for (final task in tasks) {
      final blockedBy = snapshot.dependencies
          .where((dependency) => dependency.successorTaskKey == task.key)
          .map((dependency) => taskByKey[dependency.predecessorTaskKey])
          .whereType<PlanningTaskSnapshot>()
          .where((predecessor) => !predecessor.completed)
          .toList();
      final hasBlock = snapshot.days
          .expand((day) => day.blocks)
          .any((block) => block.taskKey == task.key);
      if (hasBlock) continue;

      final due = DayMath.dateOnly(task.dueDate!);
      final estimate = task.estimatedMinutes ?? snapshot.defaultSlotMinutes;
      final reasons = <PlanningReason>[
        PlanningReason(
          'deadline.due',
          'Due ${_shortDay(due)}; $estimate minutes of effort estimated.',
        ),
        if (blockedBy.isNotEmpty)
          PlanningReason(
            'deadline.blocked',
            'Blocked by ${blockedBy.map((t) => '"${t.title}"').join(', ')}.',
          ),
      ];
      final references = [
        PlanningReference(kind: 'task', id: task.key.value, label: task.title),
        for (final predecessor in blockedBy)
          PlanningReference(
            kind: 'task',
            id: predecessor.key.value,
            label: predecessor.title,
          ),
      ];

      final target = _firstTargetDay(
        dayByDate.keys.toList()..sort(),
        after: DayMath.addDays(today, -1),
        minutes: estimate,
        dayByDate: dayByDate,
        remainingByDay: remainingByDay,
        notAfter: due,
      );
      if (blockedBy.isEmpty && target != null) {
        final slot = _firstFreeSlot(dayByDate[target]!, estimate);
        if (slot != null) {
          scheduledKeys.add(task.key);
          remainingByDay[target] = remainingByDay[target]! - estimate;
          suggestions.add(
            PlanningSuggestion(
              id: 'deadline:${task.key.value}',
              type: PlanningSuggestionType.deadlineRisk,
              title: 'Schedule "${task.title}" before it is due',
              explanation:
                  '"${task.title}" is due ${_shortDay(due)} and has no '
                  'calendar block. The first fitting window is '
                  '${_shortDay(target)} ${_time(slot.start)}–${_time(slot.end)}.',
              reasons: reasons,
              references: references,
              operations: [
                CreateBlockOperation(
                  taskKey: task.key,
                  start: slot.start,
                  end: slot.start.add(Duration(minutes: estimate)),
                ),
              ],
              targetDate: target,
            ),
          );
          continue;
        }
      }

      if (task.priority < 3) {
        suggestions.add(
          PlanningSuggestion(
            id: 'deadline-priority:${task.key.value}',
            type: PlanningSuggestionType.deadlineRisk,
            title: 'Raise the priority of "${task.title}"',
            explanation: blockedBy.isEmpty
                ? 'No free window fits the estimate before the deadline. '
                      'Raising the priority keeps it visible without changing '
                      'its date.'
                : 'This task is blocked, so the planner does not move any '
                      'date. Raising its priority keeps it visible.',
            reasons: reasons,
            references: references,
            operations: [
              UpdateTaskPriorityOperation(
                taskKey: task.key,
                previousPriority: task.priority,
                priority: 3,
              ),
            ],
            targetDate: due,
          ),
        );
      } else if (blockedBy.isNotEmpty) {
        suggestions.add(
          PlanningSuggestion(
            id: 'deadline-ack:${task.key.value}',
            type: PlanningSuggestionType.deadlineRisk,
            title: 'Review blocked deadline "${task.title}"',
            explanation:
                '"${task.title}" is due ${_shortDay(due)} but depends on an '
                'unfinished task. The planner will not move either task '
                'automatically; this is an acknowledgement only.',
            reasons: reasons,
            references: references,
            targetDate: due,
            actionable: false,
          ),
        );
      }
    }
    return suggestions;
  }

  // ==================== UNSCHEDULED PRIORITY ====================

  static List<PlanningSuggestion> _unscheduledPriority(
    PlanningSnapshot snapshot,
    DateTime today,
    Map<PlanningTaskKey, PlanningTaskSnapshot> taskByKey,
    Map<DateTime, PlanningDaySnapshot> dayByDate,
    Map<DateTime, int> remainingByDay,
    Set<PlanningTaskKey> scheduledKeys,
  ) {
    final tasks =
        snapshot.tasks
            .where(
              (task) =>
                  !task.completed &&
                  task.priority >= 2 &&
                  task.startDate == null &&
                  task.dueDate == null &&
                  !scheduledKeys.contains(task.key) &&
                  !snapshot.days
                      .expand((day) => day.blocks)
                      .any((block) => block.taskKey == task.key),
            )
            .toList()
          ..sort((a, b) {
            final priority = b.priority.compareTo(a.priority);
            return priority != 0 ? priority : a.title.compareTo(b.title);
          });

    final suggestions = <PlanningSuggestion>[];
    final days = dayByDate.keys.toList()..sort();
    for (final task in tasks) {
      final estimate = task.estimatedMinutes ?? snapshot.defaultSlotMinutes;
      final target = _firstTargetDay(
        days,
        after: DayMath.addDays(today, -1),
        minutes: estimate,
        dayByDate: dayByDate,
        remainingByDay: remainingByDay,
      );
      if (target == null) continue;
      final slot = _firstFreeSlot(dayByDate[target]!, estimate);
      if (slot == null) continue;
      scheduledKeys.add(task.key);
      remainingByDay[target] = remainingByDay[target]! - estimate;
      suggestions.add(
        PlanningSuggestion(
          id: 'unscheduled:${task.key.value}',
          type: PlanningSuggestionType.unscheduledPriority,
          title: 'Schedule "${task.title}"',
          explanation:
              'This ${_priorityLabel(task.priority).toLowerCase()}-priority '
              'task has no date or block. ${_shortDay(target)} has a fitting '
              'window at ${_time(slot.start)}–${_time(slot.end)}.',
          reasons: [
            PlanningReason(
              'priority.unscheduled',
              'Priority ${task.priority} task has no date or schedule block.',
            ),
            PlanningReason(
              'capacity.fits',
              'The suggested window fits $estimate minutes.',
            ),
          ],
          references: [
            PlanningReference(
              kind: 'task',
              id: task.key.value,
              label: task.title,
            ),
          ],
          operations: [
            CreateBlockOperation(
              taskKey: task.key,
              start: slot.start,
              end: slot.start.add(Duration(minutes: estimate)),
            ),
          ],
          targetDate: target,
        ),
      );
      if (suggestions.length >= 3) break;
    }
    return suggestions;
  }

  // ==================== FOCUS WINDOW ====================

  static List<PlanningSuggestion> _focusWindows(
    PlanningSnapshot snapshot,
    DateTime today,
    Map<PlanningTaskKey, PlanningTaskSnapshot> taskByKey,
    Map<DateTime, PlanningDaySnapshot> dayByDate,
    Map<DateTime, int> remainingByDay,
    Set<PlanningTaskKey> scheduledKeys,
  ) {
    final suggestions = <PlanningSuggestion>[];
    final days = dayByDate.keys.toList()..sort();
    final candidates =
        snapshot.tasks
            .where(
              (task) =>
                  !task.completed &&
                  task.estimatedMinutes != null &&
                  !scheduledKeys.contains(task.key) &&
                  !snapshot.days
                      .expand((day) => day.blocks)
                      .any((block) => block.taskKey == task.key),
            )
            .toList()
          ..sort((a, b) {
            final priority = b.priority.compareTo(a.priority);
            if (priority != 0) return priority;
            final dueA = a.dueDate ?? DateTime(9999);
            final dueB = b.dueDate ?? DateTime(9999);
            final due = dueA.compareTo(dueB);
            return due != 0 ? due : a.title.compareTo(b.title);
          });

    for (final day in days) {
      if (suggestions.length >= 3) break;
      final slots = _freeSlots(dayByDate[day]!);
      for (final slot in slots) {
        if (suggestions.length >= 3) break;
        final minutes = slot.end.difference(slot.start).inMinutes;
        if (minutes < 20) continue;
        final task = candidates
            .where(
              (candidate) =>
                  !scheduledKeys.contains(candidate.key) &&
                  candidate.estimatedMinutes! <= minutes &&
                  (candidate.startDate == null ||
                      !day.isBefore(DayMath.dateOnly(candidate.startDate!))) &&
                  (candidate.dueDate == null ||
                      !day.isAfter(DayMath.dateOnly(candidate.dueDate!))),
            )
            .firstOrNull;
        if (task == null) continue;
        final estimate = task.estimatedMinutes!;
        scheduledKeys.add(task.key);
        remainingByDay[day] = (remainingByDay[day] ?? 0) - estimate;
        suggestions.add(
          PlanningSuggestion(
            id: 'focus:${_dayKey(day)}:${_time(slot.start)}:${task.key.value}',
            type: PlanningSuggestionType.focusWindow,
            title: 'Use the $minutes-minute focus window',
            explanation:
                '${_shortDay(day)} has a free $minutes-minute window at '
                '${_time(slot.start)}. "${task.title}" needs $estimate minutes.',
            reasons: [
              PlanningReason(
                'focus.window',
                '$minutes contiguous minutes are free.',
              ),
              PlanningReason(
                'focus.estimate',
                'The task estimate fits the window.',
              ),
            ],
            references: [
              PlanningReference(
                kind: 'task',
                id: task.key.value,
                label: task.title,
              ),
            ],
            operations: [
              CreateBlockOperation(
                taskKey: task.key,
                start: slot.start,
                end: slot.start.add(Duration(minutes: estimate)),
              ),
            ],
            targetDate: day,
          ),
        );
      }
    }
    return suggestions;
  }

  // ==================== EISENHOWER ====================

  static EisenhowerResult _matrix(PlanningSnapshot snapshot, DateTime today) {
    final items = <EisenhowerItem>[];
    final window = snapshot.urgencyWindowDays;
    for (final task in snapshot.tasks) {
      if (task.completed) continue;
      // Importance is stored on personal to-dos. Project checklist tasks keep
      // their Phase 3 priority and do not appear in the matrix until a project
      // importance field exists.
      if (task.key.source != PlanningTaskSource.todo) continue;
      final hasDue = task.dueDate != null;
      final daysUntil = hasDue
          ? DayMath.calendarDaysBetween(today, DayMath.dateOnly(task.dueDate!))
          : null;
      final derivedUrgent = hasDue && daysUntil! <= window;
      final urgent = task.urgencyOverride ?? derivedUrgent;
      final important = task.isImportant;
      final urgencyReason = task.urgencyOverride != null
          ? 'Manually marked ${task.urgencyOverride! ? 'urgent' : 'not urgent'}'
          : hasDue
          ? daysUntil! < 0
                ? 'Overdue by ${-daysUntil} day(s)'
                : 'Due in $daysUntil day(s); window is $window day(s)'
          : 'No due date; urgency defaults to not urgent';
      items.add(
        EisenhowerItem(
          task: task,
          quadrant: _quadrant(important, urgent),
          urgent: urgent,
          important: important,
          urgencyReason: urgencyReason,
          urgencyIsOverride: task.urgencyOverride != null,
        ),
      );
    }
    items.sort((a, b) {
      final dueA = a.task.dueDate ?? DateTime(9999);
      final dueB = b.task.dueDate ?? DateTime(9999);
      final due = dueA.compareTo(dueB);
      if (due != 0) return due;
      final priority = b.task.priority.compareTo(a.task.priority);
      return priority != 0 ? priority : a.task.title.compareTo(b.task.title);
    });
    return EisenhowerResult(
      doFirst: _quadrantItems(items, EisenhowerQuadrant.doFirst),
      schedule: _quadrantItems(items, EisenhowerQuadrant.schedule),
      delegate: _quadrantItems(items, EisenhowerQuadrant.delegate),
      eliminate: _quadrantItems(items, EisenhowerQuadrant.eliminate),
      urgencyWindowDays: window,
    );
  }

  static List<EisenhowerItem> _quadrantItems(
    List<EisenhowerItem> items,
    EisenhowerQuadrant quadrant,
  ) => items.where((item) => item.quadrant == quadrant).toList();

  static EisenhowerQuadrant _quadrant(bool important, bool urgent) {
    if (important && urgent) return EisenhowerQuadrant.doFirst;
    if (important) return EisenhowerQuadrant.schedule;
    if (urgent) return EisenhowerQuadrant.delegate;
    return EisenhowerQuadrant.eliminate;
  }

  // ==================== WEEKLY REVIEW ====================

  static WeeklyReviewResult? _weeklyReview(WeeklyReviewInput? input) {
    if (input == null) return null;
    return WeeklyReviewResult(
      from: DayMath.dateOnly(input.from),
      to: DayMath.dateOnly(input.to),
      completedTasks: input.completedTasks,
      completedOccurrences: input.completedOccurrences,
      projectTasksCompleted: input.projectTasksCompleted,
      carriedTasks: input.carriedTasks,
      overdueTasks: input.overdueTasks,
      focusMinutes: input.focusMinutes,
      focusSessions: input.focusSessions,
      habitCompletions: input.habitCompletions,
      habitPossible: input.habitPossible,
      milestonesCompleted: input.milestonesCompleted,
      milestonesDue: input.milestonesDue,
    );
  }

  // ==================== TIME HELPERS ====================

  static DateTime? _firstTargetDay(
    List<DateTime> days, {
    required DateTime after,
    required int minutes,
    required Map<DateTime, PlanningDaySnapshot> dayByDate,
    required Map<DateTime, int> remainingByDay,
    DateTime? notAfter,
  }) {
    for (final day in days) {
      if (!day.isAfter(after)) continue;
      if (notAfter != null && day.isAfter(notAfter)) continue;
      if ((remainingByDay[day] ?? 0) < minutes) continue;
      final slot = _firstFreeSlot(dayByDate[day]!, minutes);
      if (slot != null) return day;
    }
    return null;
  }

  static ({DateTime start, DateTime end})? _firstFreeSlot(
    PlanningDaySnapshot day,
    int minutes,
  ) {
    for (final slot in _freeSlots(day)) {
      if (slot.end.difference(slot.start).inMinutes >= minutes) return slot;
    }
    return null;
  }

  static List<({DateTime start, DateTime end})> _freeSlots(
    PlanningDaySnapshot day,
  ) {
    final base = DayMath.dateOnly(day.day);
    final working = <({DateTime start, DateTime end})>[
      for (final window in day.workingHours)
        if (window.isValid) window.on(base),
    ];
    if (working.isEmpty) return const [];
    final blocked = <({DateTime start, DateTime end})>[
      for (final window in day.breaks)
        if (window.isValid) window.on(base),
      ...day.busyEvents,
      for (final block in day.blocks) (start: block.start, end: block.end),
    ];
    final mergedBlocked = _merge(blocked);
    final result = <({DateTime start, DateTime end})>[];
    for (final window in _merge(working)) {
      var cursor = window.start;
      for (final block in mergedBlocked) {
        if (!block.end.isAfter(cursor)) continue;
        if (!block.start.isBefore(window.end)) break;
        if (block.start.isAfter(cursor)) {
          result.add((start: cursor, end: block.start));
        }
        if (block.end.isAfter(cursor)) cursor = block.end;
        if (!cursor.isBefore(window.end)) break;
      }
      if (cursor.isBefore(window.end)) {
        result.add((start: cursor, end: window.end));
      }
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static List<({DateTime start, DateTime end})> _merge(
    List<({DateTime start, DateTime end})> input,
  ) {
    final intervals = [
      for (final interval in input)
        if (interval.end.isAfter(interval.start)) interval,
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (intervals.isEmpty) return const [];
    final merged = <({DateTime start, DateTime end})>[];
    var start = intervals.first.start;
    var end = intervals.first.end;
    for (final interval in intervals.skip(1)) {
      if (interval.start.isAfter(end)) {
        merged.add((start: start, end: end));
        start = interval.start;
        end = interval.end;
      } else if (interval.end.isAfter(end)) {
        end = interval.end;
      }
    }
    merged.add((start: start, end: end));
    return merged;
  }

  static String _dayKey(DateTime value) {
    final local = DayMath.dateOnly(value);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  static String _shortDay(DateTime value) {
    final local = DayMath.dateOnly(value);
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[local.weekday - 1]} ${local.day}/${local.month}';
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  static String _priorityLabel(int value) => switch (value) {
    >= 3 => 'High',
    2 => 'Medium',
    1 => 'Low',
    _ => 'No',
  };
}
