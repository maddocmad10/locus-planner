import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/project_status.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';

final projectWorkflowRepositoryProvider = Provider<ProjectWorkflowRepository>((
  ref,
) {
  return ProjectWorkflowRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

/// Per-project display metadata for the five fixed workflow statuses.
final projectStatusesProvider = StreamProvider.autoDispose
    .family<List<ProjectStatus>, String>((ref, projectId) {
      return ref
          .watch(projectWorkflowRepositoryProvider)
          .watchStatuses(projectId);
    });

final projectMilestonesProvider = StreamProvider.autoDispose
    .family<List<ProjectMilestone>, String>((ref, projectId) {
      return ref
          .watch(projectWorkflowRepositoryProvider)
          .watchMilestones(projectId);
    });

final projectDependenciesProvider = StreamProvider.autoDispose
    .family<List<TaskDependency>, String>((ref, projectId) {
      return ref
          .watch(projectWorkflowRepositoryProvider)
          .watchDependencies(projectId);
    });

/// Milestones, status metadata, dependency graph edits and project-task
/// workflows that are richer than the original checklist.
class ProjectWorkflowRepository {
  ProjectWorkflowRepository(this._db, this._undo);

  final AppDatabase _db;
  final UndoService _undo;
  static const _uuid = Uuid();

  // ==================== STATUSES ====================

  Stream<List<ProjectStatus>> watchStatuses(String projectId) async* {
    await _db.ensureProjectStatuses(projectId);
    yield* (_db.select(_db.projectStatuses)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  Future<List<ProjectStatus>> loadStatuses(String projectId) async {
    await _db.ensureProjectStatuses(projectId);
    return (_db.select(_db.projectStatuses)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  Future<void> updateStatus(
    ProjectStatus status, {
    String? name,
    String? colorToken,
  }) async {
    final nextName = (name ?? status.name).trim();
    if (nextName.isEmpty || nextName.length > 40) {
      throw ArgumentError('A status name must be 1-40 characters.');
    }
    final nextColor = colorToken ?? status.colorToken;
    if (!ProjectStatusCatalog.colorTokens.contains(nextColor)) {
      throw ArgumentError.value(nextColor, 'colorToken', 'Unknown colour.');
    }
    await (_db.update(
      _db.projectStatuses,
    )..where((t) => t.id.equals(status.id))).write(
      ProjectStatusesCompanion(
        name: Value(nextName),
        colorToken: Value(nextColor),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  Future<void> reorderStatuses(
    String projectId,
    List<String> orderedIds,
  ) async {
    final now = AppClock.now();
    await _db.transaction(() async {
      for (var index = 0; index < orderedIds.length; index++) {
        await (_db.update(_db.projectStatuses)..where(
              (t) =>
                  t.id.equals(orderedIds[index]) &
                  t.projectId.equals(projectId),
            ))
            .write(
              ProjectStatusesCompanion(
                position: Value(index),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  // ==================== TASKS ====================

  /// Updates every workflow field atomically. `completed` is never written
  /// independently of `status_key`.
  Future<void> updateTask(
    Task task, {
    required String title,
    required String statusKey,
    DateTime? startDate,
    DateTime? dueDate,
    required int? estimatedMinutes,
    required int priority,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('A project task needs a title.');
    }
    final key = ProjectStatusCatalog.normalize(statusKey);
    final start = startDate == null ? null : DayMath.dateOnly(startDate);
    final due = dueDate == null ? null : DayMath.dateOnly(dueDate);
    if (start != null && due != null && start.isAfter(due)) {
      throw ArgumentError('The start date must not be after the due date.');
    }
    if (estimatedMinutes != null &&
        (estimatedMinutes < 1 || estimatedMinutes > 525600)) {
      throw ArgumentError('Estimate must be between 1 and 525600 minutes.');
    }
    final nextPriority = priority.clamp(0, 3).toInt();

    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        title: Value(trimmed),
        statusKey: Value(key),
        completed: Value(ProjectStatusCatalog.isDoneKey(key)),
        startDate: Value(start),
        dueDate: Value(due),
        estimatedMinutes: Value(estimatedMinutes),
        priority: Value(nextPriority),
      ),
    );
  }

  /// Drag/drop entry point. The task is moved to the end of the new column.
  Future<void> moveTaskToStatus(Task task, String statusKey) async {
    final key = ProjectStatusCatalog.normalize(statusKey);
    await _db.transaction(() async {
      final nextOrder = await _nextSortOrder(task.projectId);
      await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
        TasksCompanion(
          statusKey: Value(key),
          completed: Value(ProjectStatusCatalog.isDoneKey(key)),
          sortOrder: Value(nextOrder),
        ),
      );
    });
  }

  Future<void> toggleTask(Task task, bool completed) async {
    if (completed) {
      await moveTaskToStatus(task, ProjectStatusCatalog.done.key);
      return;
    }
    final key = ProjectStatusCatalog.isDoneKey(task.statusKey)
        ? ProjectStatusCatalog.todo.key
        : task.statusKey;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(statusKey: Value(key), completed: const Value(false)),
    );
  }

  Future<void> deleteTaskWithUndo(Task task) async {
    final dependencies =
        await (_db.select(_db.taskDependencies)..where(
              (t) =>
                  t.predecessorTaskId.equals(task.id) |
                  t.successorTaskId.equals(task.id),
            ))
            .get();
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(task.id))).go();
    _undo.offer(
      label: 'project task',
      restore: () async {
        await _db.transaction(() async {
          await _db.into(_db.tasks).insertOnConflictUpdate(task);
          for (final dependency in dependencies) {
            await _db
                .into(_db.taskDependencies)
                .insertOnConflictUpdate(dependency);
          }
        });
      },
    );
  }

  Future<int> _nextSortOrder(String projectId) async {
    final last =
        await (_db.select(_db.tasks)
              ..where((t) => t.projectId.equals(projectId))
              ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.sortOrder ?? 0) + 1;
  }

  // ==================== MILESTONES ====================

  Stream<List<ProjectMilestone>> watchMilestones(String projectId) {
    return (_db.select(_db.projectMilestones)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.createdAt),
          ]))
        .watch();
  }

  Future<String> addMilestone({
    required String projectId,
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError('A milestone needs a title.');
    final now = AppClock.now();
    final id = _uuid.v4();
    await _db
        .into(_db.projectMilestones)
        .insert(
          ProjectMilestonesCompanion.insert(
            id: id,
            projectId: projectId,
            title: trimmed,
            description: Value(_normalizeText(description)),
            targetDate: Value(
              targetDate == null ? null : DayMath.dateOnly(targetDate),
            ),
            position: Value(await _nextMilestonePosition(projectId)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  Future<void> updateMilestone(
    ProjectMilestone milestone, {
    required String title,
    String? description,
    DateTime? targetDate,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw ArgumentError('A milestone needs a title.');
    await (_db.update(
      _db.projectMilestones,
    )..where((t) => t.id.equals(milestone.id))).write(
      ProjectMilestonesCompanion(
        title: Value(trimmed),
        description: Value(_normalizeText(description)),
        targetDate: Value(
          targetDate == null ? null : DayMath.dateOnly(targetDate),
        ),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  Future<void> setMilestoneCompleted(
    ProjectMilestone milestone,
    bool completed,
  ) async {
    await (_db.update(
      _db.projectMilestones,
    )..where((t) => t.id.equals(milestone.id))).write(
      ProjectMilestonesCompanion(
        completedAt: Value(completed ? AppClock.now() : null),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  Future<void> deleteMilestone(ProjectMilestone milestone) async {
    await (_db.delete(
      _db.projectMilestones,
    )..where((t) => t.id.equals(milestone.id))).go();
    _undo.offer(
      label: 'milestone',
      restore: () async {
        await _db.into(_db.projectMilestones).insertOnConflictUpdate(milestone);
      },
    );
  }

  Future<int> _nextMilestonePosition(String projectId) async {
    final last =
        await (_db.select(_db.projectMilestones)
              ..where((t) => t.projectId.equals(projectId))
              ..orderBy([(t) => OrderingTerm.desc(t.position)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.position ?? -1) + 1;
  }

  // ==================== DEPENDENCIES ====================

  Stream<List<TaskDependency>> watchDependencies(String projectId) {
    return _db
        .customSelect(
          'SELECT d.* FROM task_dependencies d '
          'JOIN tasks p ON p.id = d.predecessor_task_id '
          'JOIN tasks s ON s.id = d.successor_task_id '
          'WHERE p.project_id = ? AND s.project_id = ? '
          'ORDER BY d.created_at, d.id',
          variables: [
            Variable.withString(projectId),
            Variable.withString(projectId),
          ],
          readsFrom: {_db.taskDependencies, _db.tasks},
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              TaskDependency(
                id: row.read<String>('id'),
                predecessorTaskId: row.read<String>('predecessor_task_id'),
                successorTaskId: row.read<String>('successor_task_id'),
                dependencyType: row.read<String>('dependency_type'),
                lagMinutes: row.read<int>('lag_minutes'),
                createdAt: DateTime.fromMillisecondsSinceEpoch(
                  row.read<int>('created_at') * 1000,
                ),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(
                  row.read<int>('updated_at') * 1000,
                ),
              ),
          ],
        );
  }

  Future<List<TaskDependency>> loadDependencies(String projectId) async {
    final rows = await _db
        .customSelect(
          'SELECT d.* FROM task_dependencies d '
          'JOIN tasks p ON p.id = d.predecessor_task_id '
          'JOIN tasks s ON s.id = d.successor_task_id '
          'WHERE p.project_id = ? AND s.project_id = ?',
          variables: [
            Variable.withString(projectId),
            Variable.withString(projectId),
          ],
        )
        .get();
    return [
      for (final row in rows)
        TaskDependency(
          id: row.read<String>('id'),
          predecessorTaskId: row.read<String>('predecessor_task_id'),
          successorTaskId: row.read<String>('successor_task_id'),
          dependencyType: row.read<String>('dependency_type'),
          lagMinutes: row.read<int>('lag_minutes'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at') * 1000,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('updated_at') * 1000,
          ),
        ),
    ];
  }

  Future<String> addDependency({
    required String predecessorTaskId,
    required String successorTaskId,
    int lagMinutes = 0,
  }) async {
    if (predecessorTaskId == successorTaskId) {
      throw ArgumentError('A task cannot depend on itself.');
    }
    if (lagMinutes < 0 || lagMinutes > 10080) {
      throw ArgumentError(
        'Dependency lag must be between 0 and 10080 minutes.',
      );
    }
    return _db.transaction(() async {
      final tasks =
          await (_db.select(_db.tasks)..where(
                (t) =>
                    t.id.equals(predecessorTaskId) |
                    t.id.equals(successorTaskId),
              ))
              .get();
      final predecessor = tasks
          .where((task) => task.id == predecessorTaskId)
          .firstOrNull;
      final successor = tasks
          .where((task) => task.id == successorTaskId)
          .firstOrNull;
      if (predecessor == null || successor == null) {
        throw StateError('Both dependency tasks must exist.');
      }
      if (predecessor.projectId != successor.projectId) {
        throw ArgumentError('Dependencies cannot cross projects yet.');
      }

      final existing =
          await (_db.select(_db.taskDependencies)..where(
                (t) =>
                    t.predecessorTaskId.equals(predecessorTaskId) &
                    t.successorTaskId.equals(successorTaskId),
              ))
              .getSingleOrNull();
      if (existing != null) {
        throw StateError('These tasks already have that dependency.');
      }

      final projectDependencies = await loadDependencies(predecessor.projectId);
      if (_wouldCreateCycle(
        projectDependencies,
        predecessorTaskId: predecessorTaskId,
        successorTaskId: successorTaskId,
      )) {
        throw StateError(
          'That dependency would create a cycle. Remove one of the existing '
          'links first.',
        );
      }

      final now = AppClock.now();
      final id = _uuid.v4();
      await _db
          .into(_db.taskDependencies)
          .insert(
            TaskDependenciesCompanion.insert(
              id: id,
              predecessorTaskId: predecessorTaskId,
              successorTaskId: successorTaskId,
              lagMinutes: Value(lagMinutes),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    });
  }

  Future<void> removeDependency(TaskDependency dependency) async {
    await (_db.delete(
      _db.taskDependencies,
    )..where((t) => t.id.equals(dependency.id))).go();
    _undo.offer(
      label: 'dependency',
      restore: () async {
        await _db.into(_db.taskDependencies).insertOnConflictUpdate(dependency);
      },
    );
  }

  /// Advisory warnings for the task editor and timeline. Dependencies never
  /// move tasks or change dates automatically in Phase 3.
  List<String> dependencyWarnings({
    required Task task,
    required List<Task> projectTasks,
    required List<TaskDependency> dependencies,
  }) {
    final byId = {for (final item in projectTasks) item.id: item};
    final warnings = <String>[];
    for (final dependency in dependencies) {
      if (dependency.successorTaskId != task.id) continue;
      final predecessor = byId[dependency.predecessorTaskId];
      if (predecessor == null) continue;
      if (!predecessor.completed) {
        warnings.add('Blocked by "${predecessor.title}" (not done yet).');
      }
      final predecessorDue = predecessor.dueDate;
      final start = task.startDate;
      if (predecessorDue != null && start != null) {
        final earliest = predecessorDue.add(
          Duration(minutes: dependency.lagMinutes),
        );
        if (earliest.isAfter(start)) {
          warnings.add(
            'Starts before "${predecessor.title}" is due. Suggested earliest '
            'start: ${_dayKey(earliest)}.',
          );
        }
      }
    }
    return warnings;
  }

  static bool _wouldCreateCycle(
    List<TaskDependency> dependencies, {
    required String predecessorTaskId,
    required String successorTaskId,
  }) {
    final adjacency = <String, List<String>>{};
    for (final dependency in dependencies) {
      adjacency
          .putIfAbsent(dependency.predecessorTaskId, () => [])
          .add(dependency.successorTaskId);
    }
    // A cycle exists if the predecessor is already reachable from the
    // successor through existing finish-to-start edges.
    final stack = <String>[successorTaskId];
    final seen = <String>{};
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == predecessorTaskId) return true;
      if (!seen.add(current)) continue;
      stack.addAll(adjacency[current] ?? const []);
    }
    return false;
  }

  /// Completing a predecessor only records that fact; successors keep their
  /// dates. This repository leaves the scheduling decision to Phase 4.
  static String? _normalizeText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _dayKey(DateTime value) {
    final local = DayMath.dateOnly(value);
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
