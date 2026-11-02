import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_agenda.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/sync_ids.dart';
import '../../projects/data/project_repository.dart';
import '../../tasks/data/task_metadata.dart';
import '../../tasks/data/task_repository.dart';
import 'my_day_models.dart';

final myDayRepositoryProvider = Provider<MyDayRepository>((ref) {
  return MyDayRepository(
    ref.watch(databaseProvider),
    ref.watch(taskRepositoryProvider),
    ref.watch(projectRepositoryProvider),
  );
});

/// Daily-planning data access. The original task row stays the source of truth:
/// this repository only stores the planning association, its manual order and
/// an optional estimate, and delegates completion to the task repositories.
class MyDayRepository {
  MyDayRepository(this._db, this._tasks, this._projects);

  final AppDatabase _db;
  final TaskRepository _tasks;
  final ProjectRepository _projects;

  /// Creates a personal to-do without planning it. Kept here so the picker and
  /// the "create a task for today" action share one code path.
  Future<String> createTodo(String title) => _tasks.add(title: title);

  /// Rows that influence a day view. A custom select with [readsFrom] lets one
  /// stream invalidate on task, project, event or plan edits without manually
  /// combining several streams.
  Stream<DailyPlanView> watchDay(DateTime day) {
    final normalized = DayMath.dateOnly(day);
    final key = myDayKey(normalized);
    return _db
        .customSelect(
          'SELECT 1 AS tick',
          readsFrom: {
            _db.dailyPlans,
            _db.dailyPlanItems,
            _db.todoItems,
            _db.tasks,
            _db.projects,
            _db.events,
          },
        )
        .watch()
        .asyncMap((_) => _buildDayView(normalized, key));
  }

  Future<void> setIntention({
    required DateTime day,
    required String intention,
  }) async {
    final trimmed = intention.trim();
    await _db.transaction(() async {
      final plan = await _ensurePlanRow(day);
      await (_db.update(
        _db.dailyPlans,
      )..where((t) => t.id.equals(plan.id))).write(
        DailyPlansCompanion(
          intention: Value(trimmed.isEmpty ? null : trimmed),
          updatedAt: Value(AppClock.now()),
        ),
      );
    });
  }

  Future<void> addTodo({
    required DateTime day,
    required String todoId,
    int? plannedMinutes,
  }) => _addItem(
    day: day,
    source: PlannedTaskSource.todo,
    taskId: todoId,
    plannedMinutes: plannedMinutes,
  );

  Future<void> addProjectTask({
    required DateTime day,
    required String taskId,
    int? plannedMinutes,
  }) => _addItem(
    day: day,
    source: PlannedTaskSource.projectTask,
    taskId: taskId,
    plannedMinutes: plannedMinutes,
  );

  Future<void> _addItem({
    required DateTime day,
    required PlannedTaskSource source,
    required String taskId,
    int? plannedMinutes,
  }) async {
    _validateMinutes(plannedMinutes);
    await _db.transaction(() async {
      final plan = await _ensurePlanRow(day);
      final isTodo = source == PlannedTaskSource.todo;
      final existing =
          await (_db.select(_db.dailyPlanItems)..where(
                (t) =>
                    t.planId.equals(plan.id) &
                    (isTodo
                        ? t.todoItemId.equals(taskId)
                        : t.projectTaskId.equals(taskId)),
              ))
              .getSingleOrNull();
      if (existing != null) return;

      final now = AppClock.now();
      await _db
          .into(_db.dailyPlanItems)
          .insert(
            DailyPlanItemsCompanion.insert(
              id: SyncIds.dailyPlanItemId(
                planId: plan.id,
                todoItemId: isTodo ? taskId : null,
                projectTaskId: isTodo ? null : taskId,
              ),
              planId: plan.id,
              todoItemId: Value(isTodo ? taskId : null),
              projectTaskId: Value(isTodo ? null : taskId),
              sortOrder: Value(await _nextSortOrder(plan.id)),
              plannedMinutes: Value(plannedMinutes),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  Future<void> removeItem(String itemId) async {
    await (_db.delete(
      _db.dailyPlanItems,
    )..where((t) => t.id.equals(itemId))).go();
  }

  /// Moves one plan association to [targetDay]. The destination plan is
  /// created atomically with the move. If the task is already planned there,
  /// the duplicate row from the source day is dropped.
  Future<void> moveItem({
    required String itemId,
    required DateTime targetDay,
  }) async {
    await _db.transaction(() async {
      final item = await (_db.select(
        _db.dailyPlanItems,
      )..where((t) => t.id.equals(itemId))).getSingleOrNull();
      if (item == null) return;

      final targetPlan = await _ensurePlanRow(targetDay);
      if (targetPlan.id == item.planId) return;

      final todoId = item.todoItemId;
      final projectTaskId = item.projectTaskId;
      final duplicate =
          await (_db.select(_db.dailyPlanItems)..where(
                (t) =>
                    t.planId.equals(targetPlan.id) &
                    (todoId != null
                        ? t.todoItemId.equals(todoId)
                        : t.projectTaskId.equals(projectTaskId!)),
              ))
              .getSingleOrNull();
      if (duplicate != null) {
        await (_db.delete(
          _db.dailyPlanItems,
        )..where((t) => t.id.equals(itemId))).go();
        return;
      }

      await (_db.update(
        _db.dailyPlanItems,
      )..where((t) => t.id.equals(itemId))).write(
        DailyPlanItemsCompanion(
          planId: Value(targetPlan.id),
          sortOrder: Value(await _nextSortOrder(targetPlan.id)),
          updatedAt: Value(AppClock.now()),
        ),
      );
    });
  }

  /// Persists manual drag-and-drop order. All affected rows are written in one
  /// transaction so a crash cannot leave a half-applied order.
  Future<void> reorderItems(List<String> orderedItemIds) async {
    if (orderedItemIds.isEmpty) return;
    final now = AppClock.now();
    await _db.transaction(() async {
      for (var index = 0; index < orderedItemIds.length; index++) {
        await (_db.update(
          _db.dailyPlanItems,
        )..where((t) => t.id.equals(orderedItemIds[index]))).write(
          DailyPlanItemsCompanion(
            sortOrder: Value(index),
            updatedAt: Value(now),
          ),
        );
      }
    });
  }

  Future<void> updateEstimate({
    required String itemId,
    required int? plannedMinutes,
  }) async {
    _validateMinutes(plannedMinutes);
    await (_db.update(
      _db.dailyPlanItems,
    )..where((t) => t.id.equals(itemId))).write(
      DailyPlanItemsCompanion(
        plannedMinutes: Value(plannedMinutes),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  /// Completion writes through to the original task, keeping one completion
  /// flag and preserving the existing recurrence semantics.
  Future<void> setCompleted(PlannedTaskView item, bool completed) async {
    if (item.source == PlannedTaskSource.todo) {
      await _tasks.toggle(item.taskId, completed);
      return;
    }
    final task = await (_db.select(
      _db.tasks,
    )..where((t) => t.id.equals(item.taskId))).getSingleOrNull();
    if (task != null) await _projects.toggleTask(task, completed);
  }

  /// Every incomplete task that can be planned on [day], including ones that
  /// are already planned so the picker can mark them instead of hiding them.
  Future<List<PlannableTaskView>> plannableTasks(DateTime day) async {
    final plan = await _planForDay(myDayKey(day));
    final plannedTodoIds = <String>{};
    final plannedTaskIds = <String>{};
    if (plan != null) {
      final rows = await (_db.select(
        _db.dailyPlanItems,
      )..where((t) => t.planId.equals(plan.id))).get();
      for (final row in rows) {
        final todoId = row.todoItemId;
        final taskId = row.projectTaskId;
        if (todoId != null) plannedTodoIds.add(todoId);
        if (taskId != null) plannedTaskIds.add(taskId);
      }
    }

    final projects = await _db.select(_db.projects).get();
    final projectNames = {for (final p in projects) p.id: p.name};
    final todos = await _db.select(_db.todoItems).get();
    final tasks = await _db.select(_db.tasks).get();

    final result = <PlannableTaskView>[
      for (final task in todos)
        if (!task.completed)
          PlannableTaskView(
            taskId: task.id,
            title: task.title,
            source: PlannedTaskSource.todo,
            alreadyPlanned: plannedTodoIds.contains(task.id),
            priority: task.priority,
            dueDate: task.dueDate,
            projectId: task.projectId,
            projectName: projectNames[task.projectId],
          ),
      for (final task in tasks)
        if (!task.completed)
          PlannableTaskView(
            taskId: task.id,
            title: task.title,
            source: PlannedTaskSource.projectTask,
            alreadyPlanned: plannedTaskIds.contains(task.id),
            priority: 0,
            projectId: task.projectId,
            projectName: projectNames[task.projectId],
          ),
    ];
    result.sort((a, b) {
      if (a.alreadyPlanned != b.alreadyPlanned) {
        return a.alreadyPlanned ? 1 : -1;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return result;
  }

  Future<DailyPlanView> _buildDayView(DateTime day, String key) async {
    final plan = await _planForDay(key);
    final projects = await _db.select(_db.projects).get();
    final projectNames = {for (final p in projects) p.id: p.name};

    final items = plan == null
        ? const <PlannedTaskView>[]
        : await _itemsForPlan(plan.id, projectNames);
    final plannedTodoIds = <String>{
      for (final item in items)
        if (item.source == PlannedTaskSource.todo) item.taskId,
    };
    final plannedTaskIds = <String>{
      for (final item in items)
        if (item.source == PlannedTaskSource.projectTask) item.taskId,
    };

    final todos = await _db.select(_db.todoItems).get();
    final tasks = await _db.select(_db.tasks).get();
    final suggestions = <SuggestedTaskView>[];

    for (final task in todos) {
      if (task.completed || plannedTodoIds.contains(task.id)) continue;
      final reason = _reasonForTodo(task, day);
      if (reason == null) continue;
      suggestions.add(
        SuggestedTaskView(
          taskId: task.id,
          title: task.title,
          source: PlannedTaskSource.todo,
          reason: reason,
          priority: task.priority,
          dueDate: task.dueDate,
          projectId: task.projectId,
          projectName: projectNames[task.projectId],
        ),
      );
    }
    for (final task in tasks) {
      if (task.completed || plannedTaskIds.contains(task.id)) continue;
      suggestions.add(
        SuggestedTaskView(
          taskId: task.id,
          title: task.title,
          source: PlannedTaskSource.projectTask,
          reason: SuggestedReason.noDate,
          priority: 0,
          projectId: task.projectId,
          projectName: projectNames[task.projectId],
        ),
      );
    }
    suggestions.sort(_compareSuggestions);
    final limited = suggestions.length > 100
        ? suggestions.sublist(0, 100)
        : suggestions;

    final events = agendaForDay(await _db.select(_db.events).get(), day);
    return DailyPlanView(
      day: day,
      planId: plan?.id,
      intention: plan?.intention ?? '',
      items: items,
      suggestions: limited,
      events: events,
    );
  }

  Future<List<PlannedTaskView>> _itemsForPlan(
    String planId,
    Map<String, String?> projectNames,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT i.id AS plan_item_id, '
          'i.todo_item_id, i.project_task_id, i.sort_order, i.planned_minutes, '
          'COALESCE(t.title, pt.title) AS title, '
          'CASE WHEN i.todo_item_id IS NOT NULL '
          'THEN t.completed ELSE pt.completed END AS completed, '
          'COALESCE(t.priority, 0) AS priority, '
          't.due_date AS due_date, '
          'COALESCE(t.project_id, pt.project_id) AS project_id '
          'FROM daily_plan_items i '
          'LEFT JOIN todo_items t ON t.id = i.todo_item_id '
          'LEFT JOIN tasks pt ON pt.id = i.project_task_id '
          'WHERE i.plan_id = ? '
          'ORDER BY i.sort_order ASC, i.created_at ASC',
          variables: [Variable.withString(planId)],
        )
        .get();

    final items = <PlannedTaskView>[];
    for (final row in rows) {
      final title = row.readNullable<String>('title');
      if (title == null) continue; // The task row is gone; the cascade wins.
      final todoId = row.readNullable<String>('todo_item_id');
      final projectTaskId = row.readNullable<String>('project_task_id');
      final projectId = row.readNullable<String>('project_id');
      items.add(
        PlannedTaskView(
          planItemId: row.read<String>('plan_item_id'),
          taskId: todoId ?? projectTaskId!,
          title: title,
          source: todoId != null
              ? PlannedTaskSource.todo
              : PlannedTaskSource.projectTask,
          completed: row.read<int>('completed') != 0,
          sortOrder: row.read<int>('sort_order'),
          priority: row.read<int>('priority'),
          plannedMinutes: row.readNullable<int>('planned_minutes'),
          dueDate: row.readNullable<DateTime>('due_date'),
          projectId: projectId,
          projectName: projectNames[projectId],
        ),
      );
    }
    return items;
  }

  SuggestedReason? _reasonForTodo(TodoItem task, DateTime day) {
    final due = task.dueDate;
    if (due != null) {
      final days = DayMath.calendarDaysBetween(day, due);
      if (days < 0) return SuggestedReason.overdue;
      if (days == 0) return SuggestedReason.dueToday;
    }
    if (TaskPriority.fromStorage(task.priority) == TaskPriority.high) {
      return SuggestedReason.highPriority;
    }
    if (due == null) return SuggestedReason.noDate;
    return null;
  }

  static int _compareSuggestions(SuggestedTaskView a, SuggestedTaskView b) {
    final byReason = a.reason.index.compareTo(b.reason.index);
    if (byReason != 0) return byReason;
    final byPriority = b.priority.compareTo(a.priority);
    if (byPriority != 0) return byPriority;
    final aDue = a.dueDate;
    final bDue = b.dueDate;
    if (aDue != null && bDue != null) {
      final byDue = aDue.compareTo(bDue);
      if (byDue != 0) return byDue;
    } else if (aDue != null) {
      return -1;
    } else if (bDue != null) {
      return 1;
    }
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  Future<DailyPlan?> _planForDay(String key) async {
    return (_db.select(
      _db.dailyPlans,
    )..where((t) => t.dayKey.equals(key))).getSingleOrNull();
  }

  /// Creates the plan row on first edit. Merely opening a day never writes, so
  /// browsing tomorrow does not create sync traffic.
  Future<DailyPlan> _ensurePlanRow(DateTime day) async {
    final key = myDayKey(day);
    final existing = await _planForDay(key);
    if (existing != null) return existing;

    final now = AppClock.now();
    final id = SyncIds.dailyPlanId(day);
    await _db
        .into(_db.dailyPlans)
        .insert(
          DailyPlansCompanion.insert(
            id: id,
            dayKey: key,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(
      _db.dailyPlans,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> _nextSortOrder(String planId) async {
    final last =
        await (_db.select(_db.dailyPlanItems)
              ..where((t) => t.planId.equals(planId))
              ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.sortOrder ?? -1) + 1;
  }

  static void _validateMinutes(int? minutes) {
    if (minutes != null && minutes <= 0) {
      throw ArgumentError.value(
        minutes,
        'plannedMinutes',
        'must be positive or null',
      );
    }
  }
}
