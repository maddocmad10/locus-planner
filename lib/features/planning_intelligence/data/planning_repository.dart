import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/sync_ids.dart';
import '../../calendar/data/planning_preferences_repository.dart';
import '../../my_day/data/my_day_models.dart';
import '../domain/planning_models.dart';

final planningRepositoryProvider = Provider<PlanningRepository>((ref) {
  return PlanningRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
    ref.watch(planningPreferencesRepositoryProvider),
  );
});

/// Executes accepted suggestions. The engine never touches the database; this
/// repository applies all operations in one transaction and then offers one
/// Undo action that restores every row the transaction changed.
class PlanningRepository {
  PlanningRepository(this._db, this._undo, this._preferences);

  final AppDatabase _db;
  final UndoService _undo;
  final PlanningPreferencesRepository _preferences;
  static const _uuid = Uuid();

  Future<void> applySuggestion(
    PlanningSuggestion suggestion, {
    DateTime? targetDay,
  }) async {
    if (suggestion.operations.isEmpty) return;
    final undoActions = <Future<void> Function()>[];
    await _db.transaction(() async {
      for (final operation in suggestion.operations) {
        switch (operation) {
          case MoveBlockOperation():
            await _applyMoveBlock(operation, undoActions);
          case CreateBlockOperation():
            await _applyCreateBlock(operation, undoActions);
          case MovePlanItemOperation():
            await _applyMovePlanItem(operation, undoActions, targetDay);
          case UpdateTaskFlagsOperation():
            await _applyTaskFlags(operation, undoActions);
          case UpdateTaskPriorityOperation():
            await _applyTaskPriority(operation, undoActions);
        }
      }
    });
    if (undoActions.isEmpty) return;
    _undo.offer(
      label: 'planning suggestion',
      restore: () async {
        await _db.transaction(() async {
          for (final action in undoActions.reversed) {
            await action();
          }
        });
      },
    );
  }

  /// Removes the source My Day rows of a carry-forward suggestion. Used by the
  /// explicit "Remove from plan" choice.
  Future<void> removeCarryForward(PlanningSuggestion suggestion) async {
    final items = suggestion.operations
        .whereType<MovePlanItemOperation>()
        .toList();
    if (items.isEmpty) return;
    final removed = <DailyPlanItem>[];
    await _db.transaction(() async {
      for (final operation in items) {
        final row =
            await (_db.select(_db.dailyPlanItems)
                  ..where((item) => item.id.equals(operation.planItemId)))
                .getSingleOrNull();
        if (row == null) continue;
        removed.add(row);
        await (_db.delete(
          _db.dailyPlanItems,
        )..where((item) => item.id.equals(row.id))).go();
      }
    });
    if (removed.isEmpty) return;
    _undo.offer(
      label: 'carry-forward removal',
      restore: () async {
        await _db.transaction(() async {
          for (final row in removed) {
            await _db.into(_db.dailyPlanItems).insertOnConflictUpdate(row);
          }
        });
      },
    );
  }

  Future<void> setImportance(PlanningTaskKey key, bool important) async {
    if (key.source != PlanningTaskSource.todo) return;
    await (_db.update(_db.todoItems)..where((task) => task.id.equals(key.id)))
        .write(TodoItemsCompanion(isImportant: Value(important)));
  }

  Future<void> setUrgencyOverride(
    PlanningTaskKey key,
    bool? urgencyOverride,
  ) async {
    if (key.source != PlanningTaskSource.todo) return;
    await (_db.update(
      _db.todoItems,
    )..where((task) => task.id.equals(key.id))).write(
      TodoItemsCompanion(
        urgencyOverride: urgencyOverride == null
            ? const Value<bool?>(null)
            : Value(urgencyOverride),
      ),
    );
  }

  Future<void> saveUrgencyWindow(int days) async {
    if (days < 1 || days > 30) {
      throw ArgumentError('Urgency window must be between 1 and 30 days.');
    }
    final profile = await _preferences.loadProfile();
    await _preferences.savePreferences(
      timezoneId: profile.timezoneId,
      defaultSlotMinutes: profile.defaultSlotMinutes,
      weekStartDay: profile.weekStartDay,
      dayStartMinute: profile.dayStartMinute,
      dayEndMinute: profile.dayEndMinute,
      bufferMinutes: profile.bufferMinutes,
      urgencyWindowDays: days,
    );
  }

  Future<void> _applyMoveBlock(
    MoveBlockOperation operation,
    List<Future<void> Function()> undo,
  ) async {
    final previous = await (_db.select(
      _db.taskScheduleBlocks,
    )..where((block) => block.id.equals(operation.blockId))).getSingleOrNull();
    if (previous == null) {
      throw StateError('That schedule block no longer exists.');
    }
    if (!operation.newEnd.isAfter(operation.newStart)) {
      throw StateError('The suggested block has an invalid interval.');
    }
    await (_db.update(
      _db.taskScheduleBlocks,
    )..where((block) => block.id.equals(operation.blockId))).write(
      TaskScheduleBlocksCompanion(
        startAt: Value(operation.newStart),
        endAt: Value(operation.newEnd),
        updatedAt: Value(AppClock.now()),
      ),
    );
    undo.add(() async {
      await _db.into(_db.taskScheduleBlocks).insertOnConflictUpdate(previous);
    });
  }

  Future<void> _applyCreateBlock(
    CreateBlockOperation operation,
    List<Future<void> Function()> undo,
  ) async {
    if (!operation.end.isAfter(operation.start)) {
      throw StateError('The suggested block has an invalid interval.');
    }
    final minutes = operation.end.difference(operation.start).inMinutes;
    if (minutes < 5 || minutes > 24 * 60) {
      throw StateError('The suggested block is outside the allowed length.');
    }
    if (operation.taskKey.source == PlanningTaskSource.todo) {
      final exists =
          await (_db.select(_db.todoItems)
                ..where((task) => task.id.equals(operation.taskKey.id)))
              .getSingleOrNull();
      if (exists == null) {
        throw StateError('That task no longer exists.');
      }
    } else {
      final exists =
          await (_db.select(_db.tasks)
                ..where((task) => task.id.equals(operation.taskKey.id)))
              .getSingleOrNull();
      if (exists == null) {
        throw StateError('That project task no longer exists.');
      }
    }
    final now = AppClock.now();
    final id = _uuid.v4();
    await _db
        .into(_db.taskScheduleBlocks)
        .insert(
          TaskScheduleBlocksCompanion.insert(
            id: id,
            todoItemId: Value(
              operation.taskKey.source == PlanningTaskSource.todo
                  ? operation.taskKey.id
                  : null,
            ),
            projectTaskId: Value(
              operation.taskKey.source == PlanningTaskSource.project
                  ? operation.taskKey.id
                  : null,
            ),
            startAt: operation.start,
            endAt: operation.end,
            blockKind: const Value('work'),
            createdAt: now,
            updatedAt: now,
          ),
        );
    undo.add(() async {
      await (_db.delete(
        _db.taskScheduleBlocks,
      )..where((block) => block.id.equals(id))).go();
    });
  }

  Future<void> _applyMovePlanItem(
    MovePlanItemOperation operation,
    List<Future<void> Function()> undo,
    DateTime? targetDay,
  ) async {
    final previous = await (_db.select(
      _db.dailyPlanItems,
    )..where((item) => item.id.equals(operation.planItemId))).getSingleOrNull();
    if (previous == null) return;
    final day = DayMath.dateOnly(targetDay ?? operation.toDay);
    final key = myDayKey(day);
    var targetPlan = await (_db.select(
      _db.dailyPlans,
    )..where((plan) => plan.dayKey.equals(key))).getSingleOrNull();
    var createdPlanId = '';
    if (targetPlan == null) {
      final now = AppClock.now();
      createdPlanId = SyncIds.dailyPlanId(day);
      await _db
          .into(_db.dailyPlans)
          .insert(
            DailyPlansCompanion.insert(
              id: createdPlanId,
              dayKey: key,
              createdAt: now,
              updatedAt: now,
            ),
          );
      targetPlan = await (_db.select(
        _db.dailyPlans,
      )..where((plan) => plan.id.equals(createdPlanId))).getSingle();
    }

    final duplicate =
        await (_db.select(_db.dailyPlanItems)..where(
              (item) =>
                  item.planId.equals(targetPlan!.id) &
                  (previous.todoItemId != null
                      ? item.todoItemId.equals(previous.todoItemId!)
                      : item.projectTaskId.equals(previous.projectTaskId!)),
            ))
            .getSingleOrNull();
    if (duplicate != null) {
      await (_db.delete(
        _db.dailyPlanItems,
      )..where((item) => item.id.equals(previous.id))).go();
    } else {
      await (_db.update(
        _db.dailyPlanItems,
      )..where((item) => item.id.equals(previous.id))).write(
        DailyPlanItemsCompanion(
          planId: Value(targetPlan.id),
          sortOrder: Value(await _nextSortOrder(targetPlan.id)),
          updatedAt: Value(AppClock.now()),
        ),
      );
    }

    undo.add(() async {
      await _db.into(_db.dailyPlanItems).insertOnConflictUpdate(previous);
      if (createdPlanId.isNotEmpty) {
        final remaining = await (_db.select(
          _db.dailyPlanItems,
        )..where((item) => item.planId.equals(createdPlanId))).get();
        if (remaining.isEmpty) {
          await (_db.delete(
            _db.dailyPlans,
          )..where((plan) => plan.id.equals(createdPlanId))).go();
        }
      }
    });
  }

  Future<void> _applyTaskFlags(
    UpdateTaskFlagsOperation operation,
    List<Future<void> Function()> undo,
  ) async {
    if (operation.taskKey.source != PlanningTaskSource.todo) return;
    final previous = await (_db.select(
      _db.todoItems,
    )..where((task) => task.id.equals(operation.taskKey.id))).getSingleOrNull();
    if (previous == null) return;
    await (_db.update(
      _db.todoItems,
    )..where((task) => task.id.equals(operation.taskKey.id))).write(
      TodoItemsCompanion(
        isImportant: operation.isImportant == null
            ? const Value.absent()
            : Value(operation.isImportant!),
        urgencyOverride: operation.clearUrgencyOverride
            ? const Value<bool?>(null)
            : operation.urgencyOverride == null
            ? const Value.absent()
            : Value(operation.urgencyOverride),
      ),
    );
    undo.add(() async {
      await _db.into(_db.todoItems).insertOnConflictUpdate(previous);
    });
  }

  Future<void> _applyTaskPriority(
    UpdateTaskPriorityOperation operation,
    List<Future<void> Function()> undo,
  ) async {
    if (operation.taskKey.source == PlanningTaskSource.todo) {
      final previous =
          await (_db.select(_db.todoItems)
                ..where((task) => task.id.equals(operation.taskKey.id)))
              .getSingleOrNull();
      if (previous == null) return;
      await (_db.update(
        _db.todoItems,
      )..where((task) => task.id.equals(operation.taskKey.id))).write(
        TodoItemsCompanion(priority: Value(operation.priority.clamp(0, 3))),
      );
      undo.add(() async {
        await _db.into(_db.todoItems).insertOnConflictUpdate(previous);
      });
      return;
    }
    final previous = await (_db.select(
      _db.tasks,
    )..where((task) => task.id.equals(operation.taskKey.id))).getSingleOrNull();
    if (previous == null) return;
    await (_db.update(_db.tasks)
          ..where((task) => task.id.equals(operation.taskKey.id)))
        .write(TasksCompanion(priority: Value(operation.priority.clamp(0, 3))));
    undo.add(() async {
      await _db.into(_db.tasks).insertOnConflictUpdate(previous);
    });
  }

  Future<int> _nextSortOrder(String planId) async {
    final last =
        await (_db.select(_db.dailyPlanItems)
              ..where((item) => item.planId.equals(planId))
              ..orderBy([(item) => OrderingTerm.desc(item.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.sortOrder ?? -1) + 1;
  }
}
