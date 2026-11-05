import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/recurrence.dart';
import '../../calendar/data/planning_preferences_repository.dart';
import '../../my_day/data/my_day_models.dart';
import '../domain/planning_engine.dart';
import '../domain/planning_models.dart';

final planningSnapshotRepositoryProvider = Provider<PlanningSnapshotRepository>(
  (ref) {
    return PlanningSnapshotRepository(
      ref.watch(databaseProvider),
      ref.watch(planningPreferencesRepositoryProvider),
    );
  },
);

final planningSnapshotProvider = FutureProvider.autoDispose<PlanningSnapshot>((
  ref,
) {
  return ref.watch(planningSnapshotRepositoryProvider).load();
});

final planningResultProvider = FutureProvider.autoDispose<PlanningResult>((
  ref,
) async {
  final snapshot = await ref.watch(planningSnapshotProvider.future);
  return PlanningEngine.build(snapshot);
});

class PlanningSnapshotRepository {
  PlanningSnapshotRepository(this._db, this._preferences);

  final AppDatabase _db;
  final PlanningPreferencesRepository _preferences;

  Future<PlanningSnapshot> load({
    DateTime? now,
    int horizonDays = 7,
    DateTime? reviewFrom,
    DateTime? reviewTo,
  }) async {
    final clock = DayMath.dateOnly(now ?? AppClock.now());
    final reviewStart = DayMath.dateOnly(
      reviewFrom ?? DayMath.startOfWeek(clock),
    );
    final reviewEnd = DayMath.dateOnly(reviewTo ?? clock);
    final profile = await _preferences.loadProfile();

    final todos = await _db.select(_db.todoItems).get();
    final projectTasks = await _db.select(_db.tasks).get();
    final projects = await _db.select(_db.projects).get();
    final projectNames = {
      for (final project in projects) project.id: project.name,
    };
    final taskSnapshots = <PlanningTaskSnapshot>[
      for (final todo in todos)
        PlanningTaskSnapshot(
          key: PlanningTaskKey(PlanningTaskSource.todo, todo.id),
          title: todo.title,
          completed: todo.completed,
          priority: todo.priority,
          dueDate: todo.dueDate,
          startDate: todo.startDate,
          estimatedMinutes: todo.estimatedMinutes,
          isImportant: todo.isImportant,
          urgencyOverride: todo.urgencyOverride,
          projectId: todo.projectId,
          projectName: projectNames[todo.projectId],
        ),
      for (final task in projectTasks)
        PlanningTaskSnapshot(
          key: PlanningTaskKey(PlanningTaskSource.project, task.id),
          title: task.title,
          completed: task.completed,
          priority: task.priority,
          dueDate: task.dueDate,
          startDate: task.startDate,
          estimatedMinutes: task.estimatedMinutes,
          projectId: task.projectId,
          projectName: projectNames[task.projectId],
        ),
    ];
    final tasksByKey = {for (final task in taskSnapshots) task.key: task};

    final dayKeys = [
      for (var offset = -7; offset < horizonDays; offset++)
        myDayKey(DayMath.addDays(clock, offset)),
    ];
    final plans = await (_db.select(
      _db.dailyPlans,
    )..where((plan) => plan.dayKey.isIn(dayKeys))).get();
    final planIds = plans.map((plan) => plan.id).toList();
    final items = planIds.isEmpty
        ? <DailyPlanItem>[]
        : await (_db.select(
            _db.dailyPlanItems,
          )..where((item) => item.planId.isIn(planIds))).get();
    final planById = {for (final plan in plans) plan.id: plan};
    final planItems = <PlanningPlanItemSnapshot>[];
    final itemsByDay = <DateTime, List<PlanningPlanItemSnapshot>>{};
    final plannedByDay = <DateTime, Map<String, int>>{};
    for (final item in items) {
      final plan = planById[item.planId];
      if (plan == null) continue;
      final day = DayMath.dateOnly(DateTime.parse(plan.dayKey));
      final taskKey = item.todoItemId != null
          ? PlanningTaskKey(PlanningTaskSource.todo, item.todoItemId!)
          : item.projectTaskId != null
          ? PlanningTaskKey(PlanningTaskSource.project, item.projectTaskId!)
          : null;
      if (taskKey == null || !tasksByKey.containsKey(taskKey)) continue;
      final snapshot = PlanningPlanItemSnapshot(
        id: item.id,
        taskKey: taskKey,
        day: day,
        plannedMinutes: item.plannedMinutes,
      );
      planItems.add(snapshot);
      itemsByDay.putIfAbsent(day, () => []).add(snapshot);
      if (item.plannedMinutes != null && item.plannedMinutes! > 0) {
        final map = plannedByDay.putIfAbsent(day, () => {});
        map[taskKey.value] = (map[taskKey.value] ?? 0) + item.plannedMinutes!;
      }
    }

    final allEvents = await _db.select(_db.events).get();
    final allBlocks = await _db.select(_db.taskScheduleBlocks).get();

    final days = <PlanningDaySnapshot>[];
    for (var offset = 0; offset < horizonDays; offset++) {
      final day = DayMath.addDays(clock, offset);
      final dayStart = day;
      final dayEnd = DayMath.addDays(day, 1);
      final busy = <({DateTime start, DateTime end})>[];
      for (final event in allEvents) {
        if (event.allDay) continue;
        for (final occurrence in Recurrence.expand(event, dayStart, dayEnd)) {
          final shift = occurrence.startTime.difference(event.startTime);
          final end =
              event.endTime?.add(shift) ??
              occurrence.startTime.add(const Duration(minutes: 30));
          busy.add((start: occurrence.startTime, end: end));
        }
      }
      final dayBlocks = <PlanningBlockSnapshot>[
        for (final block in allBlocks)
          if (block.startAt.isBefore(dayEnd) && block.endAt.isAfter(dayStart))
            PlanningBlockSnapshot(
              id: block.id,
              taskKey: block.todoItemId != null
                  ? PlanningTaskKey(PlanningTaskSource.todo, block.todoItemId!)
                  : PlanningTaskKey(
                      PlanningTaskSource.project,
                      block.projectTaskId!,
                    ),
              start: block.startAt,
              end: block.endAt,
              kind: block.blockKind,
            ),
      ];
      days.add(
        PlanningDaySnapshot(
          day: day,
          workingHours: profile.windowsFor(day.weekday),
          breaks: profile.breaksFor(day.weekday),
          busyEvents: busy,
          blocks: dayBlocks,
          plannedMinutesByTask: plannedByDay[day] ?? const {},
        ),
      );
    }

    final dependencies = await _db.select(_db.taskDependencies).get();
    final weekly = await _weeklyReview(
      from: reviewStart,
      to: reviewEnd,
      tasks: taskSnapshots,
      planItems: planItems,
      today: clock,
    );

    return PlanningSnapshot(
      now: clock,
      tasks: taskSnapshots,
      days: days,
      planItems: planItems,
      dependencies: [
        for (final dependency in dependencies)
          if (tasksByKey.containsKey(
                PlanningTaskKey(
                  PlanningTaskSource.project,
                  dependency.predecessorTaskId,
                ),
              ) &&
              tasksByKey.containsKey(
                PlanningTaskKey(
                  PlanningTaskSource.project,
                  dependency.successorTaskId,
                ),
              ))
            PlanningDependencySnapshot(
              predecessorTaskKey: PlanningTaskKey(
                PlanningTaskSource.project,
                dependency.predecessorTaskId,
              ),
              successorTaskKey: PlanningTaskKey(
                PlanningTaskSource.project,
                dependency.successorTaskId,
              ),
            ),
      ],
      weeklyReview: weekly,
      bufferMinutes: profile.bufferMinutes,
      urgencyWindowDays: profile.urgencyWindowDays,
      defaultSlotMinutes: profile.defaultSlotMinutes,
    );
  }

  Future<WeeklyReviewInput> _weeklyReview({
    required DateTime from,
    required DateTime to,
    required List<PlanningTaskSnapshot> tasks,
    required List<PlanningPlanItemSnapshot> planItems,
    required DateTime today,
  }) async {
    final endExclusive = DayMath.addDays(to, 1);
    final completions = await _db.select(_db.todoCompletions).get();
    final completedInRange = completions.where(
      (row) =>
          !row.completedAt.isBefore(from) &&
          row.completedAt.isBefore(endExclusive),
    );
    final projectTasksCompleted = tasks
        .where(
          (task) =>
              task.completed &&
              task.dueDate != null &&
              !task.dueDate!.isBefore(from) &&
              task.dueDate!.isBefore(endExclusive) &&
              task.key.source == PlanningTaskSource.project,
        )
        .length;

    final carried = planItems
        .where(
          (item) =>
              !item.day.isBefore(DayMath.addDays(today, -7)) &&
              item.day.isBefore(today) &&
              !(tasks
                      .where((task) => task.key == item.taskKey)
                      .firstOrNull
                      ?.completed ??
                  false),
        )
        .length;
    final overdue = tasks
        .where(
          (task) =>
              !task.completed &&
              task.dueDate != null &&
              task.dueDate!.isBefore(today),
        )
        .length;

    final focus = await _db.select(_db.focusSessions).get();
    final sessions = focus.where(
      (session) =>
          !session.startTime.isBefore(from) &&
          session.startTime.isBefore(endExclusive),
    );
    final habitLogs = await _db.select(_db.habitLogs).get();
    final habits = await _db.select(_db.habits).get();
    final days = DayMath.calendarDaysBetween(from, to) + 1;
    final milestones = await _db.select(_db.projectMilestones).get();

    return WeeklyReviewInput(
      from: from,
      to: to,
      completedOccurrences: completedInRange.length,
      completedDistinctTasks: completedInRange
          .map((row) => row.todoId)
          .toSet()
          .length,
      projectTasksCompleted: projectTasksCompleted,
      carriedTasks: carried,
      overdueTasks: overdue,
      focusMinutes: sessions.fold(0, (sum, row) => sum + row.durationMinutes),
      focusSessions: sessions.length,
      habitCompletions: habitLogs
          .where(
            (log) =>
                log.completed &&
                !log.date.isBefore(from) &&
                log.date.isBefore(endExclusive),
          )
          .length,
      habitPossible: habits.length * days,
      milestonesCompleted: milestones
          .where(
            (milestone) =>
                milestone.completedAt != null &&
                !milestone.completedAt!.isBefore(from) &&
                milestone.completedAt!.isBefore(endExclusive),
          )
          .length,
      milestonesDue: milestones
          .where(
            (milestone) =>
                milestone.targetDate != null &&
                !milestone.targetDate!.isBefore(from) &&
                milestone.targetDate!.isBefore(endExclusive),
          )
          .length,
    );
  }
}
