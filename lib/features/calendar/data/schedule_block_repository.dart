import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';

/// A task that can be dragged from the calendar's side panel.
class PlannableCalendarTask {
  const PlannableCalendarTask({
    required this.key,
    required this.title,
    required this.source,
    this.projectName,
    this.estimatedMinutes,
  });

  /// Stable `todo:<id>` or `task:<id>` key used by capacity and drag payloads.
  final String key;
  final String title;
  final String source;
  final String? projectName;
  final int? estimatedMinutes;
}

final scheduleBlockRepositoryProvider = Provider<ScheduleBlockRepository>((
  ref,
) {
  return ScheduleBlockRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

final scheduleBlocksForRangeProvider = StreamProvider.autoDispose
    .family<List<TaskScheduleBlock>, ({DateTime from, DateTime to})>((
      ref,
      range,
    ) {
      return ref
          .watch(scheduleBlockRepositoryProvider)
          .watchForRange(range.from, range.to);
    });

final unscheduledCalendarTasksProvider = StreamProvider.autoDispose
    .family<List<PlannableCalendarTask>, ({DateTime from, DateTime to})>((
      ref,
      range,
    ) {
      return ref
          .watch(scheduleBlockRepositoryProvider)
          .watchPlannableTasks(range.from, range.to);
    });

/// Titles for both task kinds, keyed `todo:<id>` / `task:<id>`.
final calendarTaskTitlesProvider = StreamProvider<Map<String, String>>((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT 'todo:' || id AS key, title FROM todo_items "
        "UNION ALL SELECT 'task:' || id AS key, title FROM tasks",
        readsFrom: {db.todoItems, db.tasks},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('key'): row.read<String>('title'),
        },
      );
});

/// Data access for calendar time blocks.
///
/// A block is the only canonical record of planned calendar time for a task;
/// `todo_items.start_date`/`due_date` keep their availability/deadline meaning
/// and My Day keeps its daily-intention meaning.
class ScheduleBlockRepository {
  ScheduleBlockRepository(this._db, this._undo);

  final AppDatabase _db;
  final UndoService _undo;
  static const _uuid = Uuid();

  /// Blocks that overlap [from]..[to].
  Stream<List<TaskScheduleBlock>> watchForRange(DateTime from, DateTime to) {
    return (_db.select(_db.taskScheduleBlocks)
          ..where((t) => t.startAt.isSmallerThanValue(to))
          ..where((t) => t.endAt.isBiggerThanValue(from))
          ..orderBy([
            (t) => OrderingTerm.asc(t.startAt),
            (t) => OrderingTerm.asc(t.sortOrder),
          ]))
        .watch();
  }

  /// Incomplete tasks without a block in the visible range.
  ///
  /// A block elsewhere does not hide a task here: multiple blocks per task are
  /// allowed, and the panel is about "what can I place in this view".
  Stream<List<PlannableCalendarTask>> watchPlannableTasks(
    DateTime from,
    DateTime to,
  ) {
    return _db
        .customSelect(
          'SELECT t.id, t.title, t.estimated_minutes, NULL AS project_name, '
          "'todo' AS source FROM todo_items t "
          'WHERE t.completed = 0 '
          'AND NOT EXISTS (SELECT 1 FROM task_schedule_blocks b '
          'WHERE b.todo_item_id = t.id AND b.end_at > ? AND b.start_at < ?) '
          'UNION ALL '
          'SELECT t.id, t.title, NULL AS estimated_minutes, p.name AS project_name, '
          "'task' AS source FROM tasks t "
          'JOIN projects p ON p.id = t.project_id '
          'WHERE t.completed = 0 '
          'AND NOT EXISTS (SELECT 1 FROM task_schedule_blocks b '
          'WHERE b.project_task_id = t.id AND b.end_at > ? AND b.start_at < ?) '
          'ORDER BY source, title COLLATE NOCASE',
          variables: [
            Variable.withDateTime(from),
            Variable.withDateTime(to),
            Variable.withDateTime(from),
            Variable.withDateTime(to),
          ],
          readsFrom: {
            _db.todoItems,
            _db.tasks,
            _db.projects,
            _db.taskScheduleBlocks,
          },
        )
        .watch()
        .map(
          (rows) => [
            for (final row in rows)
              PlannableCalendarTask(
                key: '${row.read<String>('source')}:${row.read<String>('id')}',
                title: row.read<String>('title'),
                source: row.read<String>('source'),
                projectName: row.readNullable<String>('project_name'),
                estimatedMinutes: row.readNullable<int>('estimated_minutes'),
              ),
          ],
        );
  }

  Future<TaskScheduleBlock> createBlock({
    String? todoItemId,
    String? projectTaskId,
    required DateTime startAt,
    required DateTime endAt,
    String blockKind = 'work',
    String? note,
    int? sortOrder,
  }) async {
    _validateTarget(todoItemId, projectTaskId);
    _validateInterval(startAt, endAt);
    if (!const {'work', 'focus', 'buffer'}.contains(blockKind)) {
      throw ArgumentError.value(blockKind, 'blockKind', 'Unsupported kind.');
    }
    await _validateParentExists(todoItemId, projectTaskId);

    final now = AppClock.now();
    final id = _uuid.v4();
    await _db
        .into(_db.taskScheduleBlocks)
        .insert(
          TaskScheduleBlocksCompanion.insert(
            id: id,
            todoItemId: Value(todoItemId),
            projectTaskId: Value(projectTaskId),
            startAt: startAt,
            endAt: endAt,
            blockKind: Value(blockKind),
            note: Value(normalizeNote(note)),
            createdAt: now,
            updatedAt: now,
            sortOrder: Value(sortOrder ?? await _nextSortOrder()),
          ),
        );
    _undo.offer(
      label: 'block created',
      restore: () async {
        await (_db.delete(
          _db.taskScheduleBlocks,
        )..where((t) => t.id.equals(id))).go();
      },
    );
    return (_db.select(
      _db.taskScheduleBlocks,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateBlock({
    required String id,
    required DateTime startAt,
    required DateTime endAt,
    String? blockKind,
    String? note,
  }) async {
    _validateInterval(startAt, endAt);
    if (blockKind != null &&
        !const {'work', 'focus', 'buffer'}.contains(blockKind)) {
      throw ArgumentError.value(blockKind, 'blockKind', 'Unsupported kind.');
    }
    await (_db.update(
      _db.taskScheduleBlocks,
    )..where((t) => t.id.equals(id))).write(
      TaskScheduleBlocksCompanion(
        startAt: Value(startAt),
        endAt: Value(endAt),
        blockKind: blockKind == null ? const Value.absent() : Value(blockKind),
        note: Value(normalizeNote(note)),
        updatedAt: Value(AppClock.now()),
      ),
    );
  }

  /// Moves a block to [newStart] keeping its duration.
  Future<void> moveBlock({
    required TaskScheduleBlock block,
    required DateTime newStart,
  }) async {
    final duration = block.endAt.difference(block.startAt);
    await updateBlock(
      id: block.id,
      startAt: newStart,
      endAt: newStart.add(duration),
      blockKind: block.blockKind,
      note: block.note,
    );
    _offerRestore(block, 'block moved');
  }

  /// Resizes a block by moving its end. The minimum duration is five minutes.
  Future<void> resizeBlock({
    required TaskScheduleBlock block,
    required DateTime newEnd,
  }) async {
    final minimumEnd = block.startAt.add(const Duration(minutes: 5));
    final end = newEnd.isBefore(minimumEnd) ? minimumEnd : newEnd;
    await updateBlock(
      id: block.id,
      startAt: block.startAt,
      endAt: end,
      blockKind: block.blockKind,
      note: block.note,
    );
    _offerRestore(block, 'block resized');
  }

  Future<void> deleteBlock(TaskScheduleBlock block) async {
    await (_db.delete(
      _db.taskScheduleBlocks,
    )..where((t) => t.id.equals(block.id))).go();
    _offerRestore(block, 'block deleted');
  }

  /// Re-inserts a previously captured row. Used by dialogs that want a
  /// stronger undo action than a single field-level revert.
  Future<void> restoreBlock(TaskScheduleBlock block) async {
    await _db.into(_db.taskScheduleBlocks).insertOnConflictUpdate(block);
  }

  void _offerRestore(TaskScheduleBlock previous, String label) {
    _undo.offer(
      label: label,
      restore: () async {
        await _db.into(_db.taskScheduleBlocks).insertOnConflictUpdate(previous);
      },
    );
  }

  Future<int> _nextSortOrder() async {
    final last =
        await (_db.select(_db.taskScheduleBlocks)
              ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)])
              ..limit(1))
            .getSingleOrNull();
    return (last?.sortOrder ?? -1) + 1;
  }

  Future<void> _validateParentExists(
    String? todoItemId,
    String? projectTaskId,
  ) async {
    if (todoItemId != null) {
      final found =
          await (_db.select(_db.todoItems)
                ..where((t) => t.id.equals(todoItemId))
                ..limit(1))
              .getSingleOrNull();
      if (found == null) {
        throw StateError('The task no longer exists.');
      }
      return;
    }
    final found =
        await (_db.select(_db.tasks)
              ..where((t) => t.id.equals(projectTaskId!))
              ..limit(1))
            .getSingleOrNull();
    if (found == null) {
      throw StateError('The project task no longer exists.');
    }
  }

  static void _validateTarget(String? todoItemId, String? projectTaskId) {
    if ((todoItemId == null) == (projectTaskId == null)) {
      throw ArgumentError('A schedule block must reference exactly one task.');
    }
  }

  static void _validateInterval(DateTime startAt, DateTime endAt) {
    final minutes = endAt.difference(startAt).inMinutes;
    if (minutes < 5) {
      throw ArgumentError('A time block must be at least five minutes.');
    }
    if (minutes > 24 * 60) {
      throw ArgumentError('A time block cannot be longer than 24 hours.');
    }
    if (DayMath.calendarDaysBetween(startAt, endAt).abs() > 1) {
      throw ArgumentError('A time block cannot span more than two days.');
    }
  }

  static String? normalizeNote(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
