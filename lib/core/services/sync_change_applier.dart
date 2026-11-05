import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../db/app_database.dart';
import '../domain/project_status.dart';
import '../utils/app_clock.dart';
import '../utils/diary_merge.dart';

/// A row that an inbound change actually modified.
typedef SyncChangedEntity = ({String type, String id, bool deleted});

/// A change that was dropped because its shape or payload could not be
/// understood. The rest of the batch is still applied, so a single change from
/// a newer (or older) peer cannot wedge sync forever.
typedef SyncRejectedChange = ({String type, String id, String reason});

/// Outcome of applying a batch of inbound changes.
class SyncApplyResult {
  const SyncApplyResult({
    required this.applied,
    required this.skipped,
    this.changes = const [],
    this.rejected = const [],
  });

  /// Changes that modified local data.
  final int applied;

  /// Changes ignored because local data was newer, the change was a replay,
  /// or its parent row no longer exists.
  final int skipped;

  /// The rows behind [applied], in the order they were applied.
  final List<SyncChangedEntity> changes;

  /// Changes whose payload could not be applied. They are reported back to the
  /// sender so the problem is visible, but they never reject the batch.
  final List<SyncRejectedChange> rejected;
}

/// Applies inbound sync changes to the local database. Shared by the desktop
/// server (phone -> desktop) and the Android client (desktop -> phone), so
/// both sides resolve conflicts with exactly the same rules.
///
/// Every synced row has a version in `sync_row_versions`, maintained by the
/// outbox triggers and carried in each payload as `updated_at` (epoch ms). An
/// incoming change only wins if its version is newer than the local one; an
/// exact tie is broken by device id so both devices pick the same winner.
/// Deletes are versioned tombstones, so a stale upsert cannot resurrect a row
/// that was deleted later.
class SyncChangeApplier {
  SyncChangeApplier(this._db);

  final AppDatabase _db;

  /// Diary rows whose merged text the other device does not have yet. They are
  /// re-saved once outbox capture is back on, so the merge is sent back.
  final _republish = <String>[];

  /// Plan items moved to a winning plan while two same-day plans clashed. They
  /// are re-saved after outbox capture is back on so the other device learns
  /// their new parent.
  final _republishPlanItems = <String>[];

  static const _schemas =
      <
        String,
        ({
          String table,
          List<String> columns,
          Map<String, Object?> defaults,
          String versionKey,
        })
      >{
        'project': (
          table: 'projects',
          columns: [
            'id',
            'name',
            'description',
            'created_at',
            'target_date',
            'target_progress',
          ],
          defaults: {},
          versionKey: 'updated_at',
        ),
        'event': (
          table: 'events',
          columns: [
            'id',
            'title',
            'description',
            'start_time',
            'end_time',
            'category',
            'has_reminder',
            'reminder_minutes',
            'recurrence_rule',
            'all_day',
            'recurrence_end',
            'recurrence_exceptions',
          ],
          // A peer from before schema 15 sends the old payload shape. Treat the
          // added columns as their database defaults instead of rejecting it.
          defaults: {
            'all_day': 0,
            'recurrence_end': null,
            'recurrence_exceptions': '[]',
          },
          versionKey: 'updated_at',
        ),
        'project_task': (
          table: 'tasks',
          columns: [
            'id',
            'project_id',
            'title',
            'completed',
            'status_key',
            'start_date',
            'due_date',
            'estimated_minutes',
            'priority',
            'sort_order',
          ],
          // An old peer only knows the checklist shape. Derive status_key from
          // its completed flag in _applyOne; these defaults are the fallback
          // for payloads that omit the newer columns entirely.
          defaults: {
            'status_key': 'todo',
            'start_date': null,
            'due_date': null,
            'estimated_minutes': null,
            'priority': 0,
          },
          versionKey: 'updated_at',
        ),
        'project_status': (
          table: 'project_statuses',
          columns: [
            'id',
            'project_id',
            'status_key',
            'name',
            'color_token',
            'position',
            'is_done',
            'is_default',
            'created_at',
            'updated_at',
          ],
          defaults: {
            'color_token': 'blue',
            'position': 0,
            'is_done': 0,
            'is_default': 1,
          },
          versionKey: 'sync_updated_at',
        ),
        'project_milestone': (
          table: 'project_milestones',
          columns: [
            'id',
            'project_id',
            'title',
            'description',
            'target_date',
            'completed_at',
            'position',
            'created_at',
            'updated_at',
          ],
          defaults: {'description': null, 'position': 0},
          versionKey: 'sync_updated_at',
        ),
        'task_dependency': (
          table: 'task_dependencies',
          columns: [
            'id',
            'predecessor_task_id',
            'successor_task_id',
            'dependency_type',
            'lag_minutes',
            'created_at',
            'updated_at',
          ],
          defaults: {'dependency_type': 'finish_to_start', 'lag_minutes': 0},
          versionKey: 'sync_updated_at',
        ),
        'habit': (
          table: 'habits',
          columns: ['id', 'name', 'icon', 'created_at', 'target_per_week'],
          // A peer from before schema 11 has no habit payloads at all, but a
          // hand-built or partially upgraded payload should still fit defaults.
          defaults: {'icon': '🔥', 'target_per_week': 5},
          versionKey: 'updated_at',
        ),
        'habit_log': (
          table: 'habit_logs',
          columns: ['id', 'habit_id', 'date', 'completed'],
          defaults: {'completed': 1},
          versionKey: 'updated_at',
        ),
        'todo': (
          table: 'todo_items',
          columns: [
            'id',
            'title',
            'notes',
            'completed',
            'created_at',
            'start_date',
            'due_date',
            'priority',
            'tags',
            'recurrence_rule',
            'parent_id',
            'project_id',
            'reminder_at',
            'estimated_minutes',
            'is_important',
            'urgency_override',
          ],
          // A peer from before schema 12 sends the old payload shape. Treat the
          // missing fields as their database defaults instead of rejecting the
          // change, so an upgraded device and an older phone still sync.
          defaults: {
            'notes': null,
            'start_date': null,
            'due_date': null,
            'priority': 0,
            'tags': '[]',
            'recurrence_rule': null,
            'parent_id': null,
            'project_id': null,
            'reminder_at': null,
            'estimated_minutes': null,
            'is_important': 0,
            'urgency_override': null,
          },
          versionKey: 'updated_at',
        ),
        // Append-only completion history. Rows are never edited, so normal
        // version ordering is enough; deleting a to-do cascades the rows and
        // the delete triggers produce the tombstones.
        'todo_completion': (
          table: 'todo_completions',
          columns: ['id', 'todo_id', 'occurrence_due', 'completed_at'],
          defaults: {},
          versionKey: 'updated_at',
        ),
        'diary_entry': (
          table: 'diary_entries',
          columns: ['id', 'date', 'mood', 'content'],
          defaults: {},
          versionKey: 'updated_at',
        ),
        // My Day tables store a real `updated_at` business column, so their
        // sync version travels as `sync_updated_at`. Plans are listed before
        // items so a snapshot always creates a parent before its children.
        'daily_plan': (
          table: 'daily_plans',
          columns: ['id', 'day_key', 'intention', 'created_at', 'updated_at'],
          defaults: {},
          versionKey: 'sync_updated_at',
        ),
        'daily_plan_item': (
          table: 'daily_plan_items',
          columns: [
            'id',
            'plan_id',
            'todo_item_id',
            'project_task_id',
            'sort_order',
            'planned_minutes',
            'created_at',
            'updated_at',
          ],
          defaults: {},
          versionKey: 'sync_updated_at',
        ),
        // Phase 2 calendar blocks. They reference either a personal to-do or a
        // project checklist task and travel after both in a snapshot.
        'task_schedule_block': (
          table: 'task_schedule_blocks',
          columns: [
            'id',
            'todo_item_id',
            'project_task_id',
            'start_at',
            'end_at',
            'timezone_id',
            'block_kind',
            'note',
            'created_at',
            'updated_at',
            'sort_order',
          ],
          defaults: {'block_kind': 'work', 'sort_order': 0},
          versionKey: 'sync_updated_at',
        ),
        // Saved views are user data but contain only validated JSON.
        'saved_filter': (
          table: 'saved_filters',
          columns: [
            'id',
            'name',
            'entity_scope',
            'filter_json',
            'sort_json',
            'is_pinned',
            'position',
            'created_at',
            'updated_at',
            'definition_version',
          ],
          defaults: {
            'sort_json': '[]',
            'is_pinned': 0,
            'position': 0,
            'definition_version': 1,
          },
          versionKey: 'sync_updated_at',
        ),
        'planning_preference': (
          table: 'planning_preferences',
          columns: [
            'id',
            'timezone_id',
            'default_slot_minutes',
            'week_start_day',
            'day_start_minute',
            'day_end_minute',
            'buffer_minutes',
            'urgency_window_days',
            'created_at',
            'updated_at',
          ],
          defaults: {
            'timezone_id': null,
            'default_slot_minutes': 30,
            'week_start_day': 1,
            'day_start_minute': 480,
            'day_end_minute': 1080,
            'buffer_minutes': 10,
            'urgency_window_days': 3,
          },
          versionKey: 'sync_updated_at',
        ),
        'working_hours': (
          table: 'working_hours',
          columns: [
            'id',
            'weekday',
            'enabled',
            'start_minute',
            'end_minute',
            'created_at',
            'updated_at',
          ],
          defaults: {'enabled': 1},
          versionKey: 'sync_updated_at',
        ),
        'working_break': (
          table: 'working_breaks',
          columns: [
            'id',
            'weekday',
            'start_minute',
            'end_minute',
            'label',
            'created_at',
            'updated_at',
          ],
          defaults: {'label': null},
          versionKey: 'sync_updated_at',
        ),
      };

  /// Every synced row as an upsert plus every delete tombstone, each carrying
  /// its sync version. Used for the desktop's initial snapshot and for the
  /// phone's full push after a resync; because receivers compare versions,
  /// sending rows they already have is harmless.
  ///
  /// The result is ordered by [snapshotTypeRank] and then entity id. That order
  /// is independent of row positions, so a snapshot page can resume after the
  /// last row it sent (the server's `after` token) even if an earlier row is
  /// deleted while the transfer is in progress. Tombstones are sorted into the
  /// same buckets as live rows, which also keeps a delete in place of the row
  /// it replaced.
  static Future<List<Map<String, dynamic>>> readFullState(
    AppDatabase db,
  ) async {
    final changes = <Map<String, dynamic>>[];
    final liveIds = <String, Set<String>>{};
    for (final entry in _schemas.entries) {
      final type = entry.key;
      final rows = await db
          .customSelect(
            'SELECT t.*, COALESCE(v.updated_at, 0) AS sync_updated_at, '
            'v.device_id AS sync_device_id FROM ${entry.value.table} t '
            'LEFT JOIN sync_row_versions v '
            'ON v.entity_type = ? AND v.entity_id = t.id',
            variables: [Variable.withString(type)],
          )
          .get();
      final ids = liveIds.putIfAbsent(type, () => <String>{});
      for (final row in rows) {
        final payload = Map<String, dynamic>.from(row.data);
        final deviceId = payload.remove('sync_device_id');
        payload[entry.value.versionKey] = payload.remove('sync_updated_at');
        ids.add(payload['id'] as String);
        changes.add({
          'entityType': type,
          'entityId': payload['id'],
          'operation': 'upsert',
          'payload': payload,
          'deviceId': deviceId,
        });
      }
    }
    final tombstones = await db
        .customSelect(
          'SELECT entity_type, entity_id, updated_at, device_id '
          'FROM sync_row_versions WHERE deleted = 1',
        )
        .get();
    for (final row in tombstones) {
      final type = row.read<String>('entity_type');
      final id = row.read<String>('entity_id');
      final isLive = liveIds[type]?.contains(id) ?? false;
      final schema = _schemas[type];
      if (schema == null || isLive) continue;
      changes.add({
        'entityType': type,
        'entityId': id,
        'operation': 'delete',
        'payload': {'id': id, schema.versionKey: row.read<int>('updated_at')},
        'deviceId': row.readNullable<String>('device_id'),
      });
    }
    changes.sort(_compareSnapshotRows);
    return changes;
  }

  /// Rank of a synced entity type in snapshot order. Unknown types sort last
  /// and are rejected as snapshot resume tokens by the server.
  static int snapshotTypeRank(String type) {
    final index = _schemaOrder.indexOf(type);
    return index < 0 ? _schemaOrder.length : index;
  }

  /// Whether [type] is a synced entity this version understands.
  static bool isSnapshotEntityType(String type) => _schemas.containsKey(type);

  static final _schemaOrder = _schemas.keys.toList(growable: false);

  static int _compareSnapshotRows(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final rankA = snapshotTypeRank(a['entityType'] as String);
    final rankB = snapshotTypeRank(b['entityType'] as String);
    if (rankA != rankB) return rankA.compareTo(rankB);
    return (a['entityId'] as String).compareTo(b['entityId'] as String);
  }

  /// Applies [changes] in order inside one transaction with trigger-based
  /// outbox capture suppressed. The desktop may supply
  /// [fanOutOriginDeviceId] to enqueue accepted changes for other phones;
  /// mobile callers omit it so pulled changes are not relayed back.
  ///
  /// A malformed change is skipped and listed in [SyncApplyResult.rejected];
  /// it never rejects the rest of the batch. That keeps a newer peer's payload
  /// shape from poisoning an older peer's sync cursor.
  Future<SyncApplyResult> apply(
    List<Map<String, dynamic>> changes, {
    String? fanOutOriginDeviceId,
  }) async {
    var skipped = 0;
    final changed = <SyncChangedEntity>[];
    final rejected = <SyncRejectedChange>[];
    // A previous batch that failed outside the per-change handlers must not
    // leak ids into this one.
    _republishPlanItems.clear();
    await _db.transaction(() async {
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        for (final change in changes) {
          try {
            if (await _applyOne(change)) {
              changed.add((
                type: change['entityType'] as String,
                id: change['entityId'] as String,
                deleted: change['operation'] == 'delete',
              ));
            } else {
              skipped++;
            }
          } on FormatException catch (error) {
            developer.log(
              'Skipping a malformed sync change',
              name: 'SyncChangeApplier',
              error: error,
            );
            rejected.add(_rejection(change, error.message));
          } on SqliteException catch (error, stackTrace) {
            // A malformed value can still reach SQLite as a constraint or type
            // error. Isolating it keeps the rest of the batch (and the sender's
            // cursor) moving instead of retrying the same page forever.
            developer.log(
              'Skipping a sync change that SQLite rejected',
              name: 'SyncChangeApplier',
              error: error,
              stackTrace: stackTrace,
            );
            rejected.add(_rejection(change, 'could not be applied'));
          }
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
      // Outbox capture is on again, so this update bumps the row's version and
      // queues it for the sender, which still holds the unmerged text.
      final republishedDiaryIds = _republish.toSet();
      for (final id in republishedDiaryIds) {
        await _db.customStatement(
          'UPDATE diary_entries SET content = content WHERE id = ?',
          [id],
        );
      }
      _republish.clear();

      // Items re-parented by a same-day plan clash are written again with
      // outbox capture on, so the sender learns their new plan.
      for (final id in _republishPlanItems) {
        await _db.customStatement(
          "UPDATE daily_plan_items SET plan_id = plan_id, "
          "updated_at = CAST(strftime('%s','now') AS INTEGER) WHERE id = ?",
          [id],
        );
      }
      _republishPlanItems.clear();

      // The desktop must relay accepted phone changes to the other paired
      // phones. Mobile callers omit fanOutOriginDeviceId, so applying desktop
      // changes on a phone never creates a relay loop. Diary merges are already
      // queued above as desktop-originated changes and must not be duplicated.
      if (fanOutOriginDeviceId != null && fanOutOriginDeviceId.isNotEmpty) {
        await _enqueueFanOut(
          changed,
          fanOutOriginDeviceId,
          republishedDiaryIds,
        );
      }
    });
    _notifyStreams(changed);
    return SyncApplyResult(
      applied: changed.length,
      skipped: skipped,
      changes: changed,
      rejected: rejected,
    );
  }

  static SyncRejectedChange _rejection(
    Map<String, dynamic> change,
    String reason,
  ) {
    final type = change['entityType'];
    final id = change['entityId'];
    return (
      type: type is String && type.isNotEmpty ? type : 'unknown',
      id: id is String && id.isNotEmpty ? id : 'unknown',
      reason: reason,
    );
  }

  Future<void> _enqueueFanOut(
    List<SyncChangedEntity> changed,
    String originDeviceId,
    Set<String> republishedDiaryIds,
  ) async {
    final queued = <String>{};
    for (final entity in changed) {
      final key = '${entity.type}:${entity.id}';
      if (!queued.add(key) ||
          (entity.type == 'diary_entry' &&
              republishedDiaryIds.contains(entity.id))) {
        continue;
      }
      final schema = _schemas[entity.type]!;
      final versions = await _db
          .customSelect(
            'SELECT updated_at, deleted FROM sync_row_versions '
            'WHERE entity_type = ? AND entity_id = ?',
            variables: [
              Variable.withString(entity.type),
              Variable.withString(entity.id),
            ],
          )
          .get();
      if (versions.isEmpty) continue;
      final version = versions.first.read<int>('updated_at');
      final deleted = versions.first.read<int>('deleted') == 1;
      final operation = deleted ? 'delete' : 'upsert';
      Map<String, dynamic> payload;
      if (deleted) {
        payload = {'id': entity.id, schema.versionKey: version};
      } else {
        final rows = await _db
            .customSelect(
              'SELECT ${schema.columns.join(', ')} FROM ${schema.table} WHERE id = ?',
              variables: [Variable.withString(entity.id)],
            )
            .get();
        if (rows.isEmpty) continue;
        payload = Map<String, dynamic>.from(rows.first.data)
          ..[schema.versionKey] = version;
      }
      await _db.customStatement(
        'INSERT INTO sync_outbox '
        '(entity_type, entity_id, operation, payload, device_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          entity.type,
          entity.id,
          operation,
          jsonEncode(payload),
          originDeviceId,
          AppClock.now().millisecondsSinceEpoch,
        ],
      );
    }
  }

  /// Rows are written with raw SQL, which Drift cannot see, so watch() streams
  /// (every screen) would keep showing old data. Tell Drift which tables
  /// changed. Deleting a project also cascades to dependent tables.
  void _notifyStreams(List<SyncChangedEntity> changed) {
    if (changed.isEmpty) return;
    final tables = <String>{};
    for (final entity in changed) {
      tables.add(_schemas[entity.type]!.table);
      if (entity.type == 'project' && entity.deleted) {
        tables.addAll(const [
          'tasks',
          'progress_logs',
          'focus_sessions',
          'project_statuses',
          'project_milestones',
          'task_dependencies',
        ]);
      }
      if (entity.type == 'habit' && entity.deleted) {
        tables.add('habit_logs');
      }
      if (entity.type == 'todo' && entity.deleted) {
        tables.add('todo_completions');
        tables.add('task_schedule_blocks');
      }
      if (entity.type == 'project_task' && entity.deleted) {
        tables.add('task_schedule_blocks');
        tables.add('task_dependencies');
      }
      if (entity.type == 'daily_plan') {
        // An upsert can delete a losing same-day plan, whose items are moved to
        // the winner; both tables changed even though the plan row survived.
        tables.add('daily_plan_items');
      }
      // A diary clash can also delete a differently-keyed row in the same
      // table, which the table name above already covers.
    }
    _db.markTablesUpdated(tables.map(_tableInfo));
  }

  TableInfo<Table, dynamic> _tableInfo(String name) => switch (name) {
    'projects' => _db.projects,
    'events' => _db.events,
    'tasks' => _db.tasks,
    'habits' => _db.habits,
    'habit_logs' => _db.habitLogs,
    'todo_items' => _db.todoItems,
    'todo_completions' => _db.todoCompletions,
    'diary_entries' => _db.diaryEntries,
    'daily_plans' => _db.dailyPlans,
    'daily_plan_items' => _db.dailyPlanItems,
    'task_schedule_blocks' => _db.taskScheduleBlocks,
    'project_statuses' => _db.projectStatuses,
    'project_milestones' => _db.projectMilestones,
    'task_dependencies' => _db.taskDependencies,
    'saved_filters' => _db.savedFilters,
    'planning_preferences' => _db.planningPreferences,
    'working_hours' => _db.workingHours,
    'working_breaks' => _db.workingBreaks,
    'progress_logs' => _db.progressLogs,
    'focus_sessions' => _db.focusSessions,
    _ => throw ArgumentError.value(name, 'name', 'Unknown synced table'),
  };

  Future<bool> _applyOne(Map<String, dynamic> change) async {
    final type = change['entityType'];
    final operation = change['operation'];
    final id = change['entityId'];
    if (type is! String) {
      throw const FormatException('Unsupported change');
    }
    // Older clients must tolerate entities introduced by a newer peer.
    // Skip unknown entity types so they cannot permanently block a batch,
    // while still validating the shape and payload of supported entities.
    if (!_schemas.containsKey(type)) return false;
    if (id is! String ||
        id.isEmpty ||
        (operation != 'upsert' && operation != 'delete')) {
      throw const FormatException('Unsupported change');
    }
    final schema = _schemas[type]!;
    final payload = change['payload'];
    if (payload is! Map<String, dynamic> || payload['id'] != id) {
      throw const FormatException('Invalid payload');
    }

    final rawVersion = payload[schema.versionKey];
    final incomingVersion = rawVersion is int ? rawVersion : null;
    final rawDevice = change['deviceId'];
    final incomingDevice = rawDevice is String ? rawDevice : null;
    final local = await _localVersion(type, id);
    if (incomingVersion != null &&
        local != null &&
        !_incomingWins(incomingVersion, incomingDevice, local)) {
      return false;
    }

    if (operation == 'delete') {
      await _db.customStatement('DELETE FROM ${schema.table} WHERE id = ?', [
        id,
      ]);
      await _recordVersion(
        type,
        id,
        incomingVersion,
        incomingDevice,
        local,
        deleted: true,
      );
      return true;
    }

    final values = schema.columns.map((column) {
      if (!payload.containsKey(column)) {
        if (schema.defaults.containsKey(column)) {
          return schema.defaults[column];
        }
        throw const FormatException('Missing payload field');
      }
      final value = payload[column];
      if (value == null || value is String || value is int || value is double) {
        return value;
      }
      if (value is bool) return value ? 1 : 0;
      throw const FormatException('Invalid payload value');
    }).toList();

    if (type == 'project_task') {
      final statusIndex = schema.columns.indexOf('status_key');
      final completedIndex = schema.columns.indexOf('completed');
      final startIndex = schema.columns.indexOf('start_date');
      final dueIndex = schema.columns.indexOf('due_date');
      final estimateIndex = schema.columns.indexOf('estimated_minutes');
      final priorityIndex = schema.columns.indexOf('priority');
      final rawKey = payload['status_key'];
      final completedFlag = values[completedIndex] == 1;
      final key = rawKey is String && ProjectStatusCatalog.contains(rawKey)
          ? rawKey
          : (completedFlag
                ? ProjectStatusCatalog.done.key
                : ProjectStatusCatalog.todo.key);
      values[statusIndex] = key;
      values[completedIndex] = ProjectStatusCatalog.isDoneKey(key) ? 1 : 0;
      final start = values[startIndex];
      final due = values[dueIndex];
      if (start is int && due is int && start > due) {
        throw const FormatException('Task start date is after its due date');
      }
      final estimate = values[estimateIndex];
      if (estimate is int && (estimate < 1 || estimate > 525600)) {
        throw const FormatException('Task estimate is out of range');
      }
      final priority = values[priorityIndex];
      if (priority is int && (priority < 0 || priority > 3)) {
        throw const FormatException('Task priority is out of range');
      }
    }
    if (type == 'project_status') {
      final keyIndex = schema.columns.indexOf('status_key');
      final nameIndex = schema.columns.indexOf('name');
      final colorIndex = schema.columns.indexOf('color_token');
      final doneIndex = schema.columns.indexOf('is_done');
      final rawKey = values[keyIndex];
      final name = values[nameIndex];
      if (rawKey is! String || !ProjectStatusCatalog.contains(rawKey)) {
        throw const FormatException('Unknown project status key');
      }
      if (name is! String || name.trim().isEmpty || name.length > 40) {
        throw const FormatException('Invalid project status name');
      }
      final color = values[colorIndex];
      if (color is! String ||
          !ProjectStatusCatalog.colorTokens.contains(color)) {
        throw const FormatException('Invalid project status colour');
      }
      values[doneIndex] = ProjectStatusCatalog.isDoneKey(rawKey) ? 1 : 0;
    }
    if (type == 'project_status' || type == 'project_milestone') {
      final projectId = payload['project_id'];
      if (projectId is! String) {
        throw const FormatException('Invalid project reference');
      }
      if (!(await _rowExists('projects', projectId))) return false;
    }
    if (type == 'project_milestone') {
      final title = payload['title'];
      if (title is! String || title.trim().isEmpty) {
        throw const FormatException('Invalid milestone title');
      }
    }
    if (type == 'task_dependency') {
      final predecessor = payload['predecessor_task_id'];
      final successor = payload['successor_task_id'];
      if (predecessor is! String || successor is! String) {
        throw const FormatException('Invalid dependency endpoints');
      }
      if (predecessor == successor) {
        throw const FormatException('A task cannot depend on itself');
      }
      final endpoints = await _db
          .customSelect(
            'SELECT id, project_id FROM tasks WHERE id IN (?, ?)',
            variables: [
              Variable.withString(predecessor),
              Variable.withString(successor),
            ],
          )
          .get();
      final projects = {
        for (final row in endpoints)
          row.read<String>('id'): row.read<String>('project_id'),
      };
      if (!projects.containsKey(predecessor) ||
          !projects.containsKey(successor)) {
        throw const FormatException(
          'Dependency endpoint task is missing; keeping it rejected for a '
          'later resync.',
        );
      }
      if (projects[predecessor] != projects[successor]) {
        throw const FormatException('Dependencies cannot cross projects');
      }
      final edges = await _db
          .customSelect(
            'SELECT predecessor_task_id, successor_task_id '
            'FROM task_dependencies',
          )
          .get();
      final adjacency = <String, List<String>>{};
      for (final row in edges) {
        adjacency
            .putIfAbsent(row.read<String>('predecessor_task_id'), () => [])
            .add(row.read<String>('successor_task_id'));
      }
      final stack = <String>[successor];
      final seen = <String>{};
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (current == predecessor) {
          throw const FormatException(
            'Dependency would create a cycle; the change was rejected.',
          );
        }
        if (!seen.add(current)) continue;
        stack.addAll(adjacency[current] ?? const []);
      }
    }
    if (type == 'diary_entry') {
      // Diary dates are unique independently of id. The row with the lowest
      // id keeps its id on every device and the text of the other row is
      // merged into it (see mergeDiaryContent), so both sides converge, a
      // same-day clash can never fail the whole batch, and nothing the user
      // wrote is discarded.
      final date = payload['date'];
      final incomingContent = payload['content'];
      if (date is! int) {
        throw const FormatException('Invalid diary date');
      }
      if (incomingContent is! String) {
        throw const FormatException('Invalid diary content');
      }
      final clash = await _db
          .customSelect(
            'SELECT id, content FROM diary_entries WHERE date = ? AND id != ?',
            variables: [Variable.withInt(date), Variable.withString(id)],
          )
          .get();
      if (clash.isNotEmpty) {
        // The date column is unique, so there is at most one clashing row.
        final localId = clash.first.read<String>('id');
        final localContent = clash.first.read<String>('content');
        if (localId.compareTo(id) < 0) {
          // The local row keeps its id: fold the incoming text into it and do
          // not insert the incoming row at all.
          final merged = mergeDiaryContent(localContent, incomingContent);
          if (merged == localContent) return false;
          await _db.customStatement(
            'UPDATE diary_entries SET content = ? WHERE id = ?',
            [merged, localId],
          );
          _republish.add(localId);
          return true;
        }
        // The incoming row keeps its id: fold the local text into it, drop
        // the local row and fall through to the normal upsert below.
        final merged = mergeDiaryContent(incomingContent, localContent);
        values[schema.columns.indexOf('content')] = merged;
        await _db.customStatement('DELETE FROM diary_entries WHERE id = ?', [
          localId,
        ]);
        if (merged != incomingContent) _republish.add(id);
      }
    }
    if (type == 'project_task') {
      // The parent project may have been deleted since this change was
      // recorded. The delete wins; skip instead of failing the foreign key.
      final parent = payload['project_id'];
      if (parent is! String) {
        throw const FormatException('Invalid task project');
      }
      final parentRows = await _db
          .customSelect(
            'SELECT 1 AS present FROM projects WHERE id = ?',
            variables: [Variable.withString(parent)],
          )
          .get();
      if (parentRows.isEmpty) return false;
    }
    if (type == 'habit_log') {
      // A habit can be deleted on the other device before its log arrives.
      final parent = payload['habit_id'];
      if (parent is! String) {
        throw const FormatException('Invalid habit log habit');
      }
      final parentRows = await _db
          .customSelect(
            'SELECT 1 AS present FROM habits WHERE id = ?',
            variables: [Variable.withString(parent)],
          )
          .get();
      if (parentRows.isEmpty) return false;

      // habit_logs is unique on (habit_id, date). A tick on both devices while
      // offline creates two ids for one fact; the lowest id wins on every
      // device so they converge without coordination. The losing local row is
      // deleted with outbox capture suppressed, so no tombstone is sent for
      // it. The surviving row is the one the other device also keeps.
      final date = payload['date'];
      if (date is! int) {
        throw const FormatException('Invalid habit log date');
      }
      final clash = await _db
          .customSelect(
            'SELECT id FROM habit_logs '
            'WHERE habit_id = ? AND date = ? AND id != ?',
            variables: [
              Variable.withString(parent),
              Variable.withInt(date),
              Variable.withString(id),
            ],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        if (localId.compareTo(id) < 0) return false;
        await _db.customStatement('DELETE FROM habit_logs WHERE id = ?', [
          localId,
        ]);
      }
    }
    if (type == 'todo_completion') {
      // A completion for a to-do that has been deleted here cannot be linked.
      // Deleting a to-do cascades its completions, so the tombstone wins.
      final parent = payload['todo_id'];
      if (parent is! String) {
        throw const FormatException('Invalid completion todo');
      }
      if (!(await _rowExists('todo_items', parent))) return false;
    }
    if (type == 'todo') {
      // A to-do may point at a project or parent that no longer exists here,
      // or a parent chain may have formed a cycle on a peer. Fall back to a
      // root/unlinked task instead of rejecting the whole change.
      final projectIndex = schema.columns.indexOf('project_id');
      final projectId = values[projectIndex];
      if (projectId is String) {
        final rows = await _db
            .customSelect(
              'SELECT 1 AS present FROM projects WHERE id = ?',
              variables: [Variable.withString(projectId)],
            )
            .get();
        if (rows.isEmpty) values[projectIndex] = null;
      }
      final parentIndex = schema.columns.indexOf('parent_id');
      final parentId = values[parentIndex];
      if (parentId is String) {
        var cursor = parentId;
        final seen = <String>{};
        var cycle = parentId == id || !(await _todoExists(cursor));
        while (!cycle && seen.add(cursor)) {
          if (cursor == id) {
            cycle = true;
            break;
          }
          final rows = await _db
              .customSelect(
                'SELECT parent_id FROM todo_items WHERE id = ?',
                variables: [Variable.withString(cursor)],
              )
              .get();
          if (rows.isEmpty) break;
          final next = rows.first.read<String?>('parent_id');
          if (next == null) break;
          cursor = next;
        }
        if (cycle) values[parentIndex] = null;
      }
    }
    if (type == 'daily_plan') {
      // One plan per local calendar day. If both devices created a plan for the
      // same day, the newer version wins; the losing plan row disappears.
      final dayKey = payload['day_key'];
      if (dayKey is! String || dayKey.isEmpty) {
        throw const FormatException('Invalid plan day');
      }
      final clash = await _db
          .customSelect(
            'SELECT id FROM daily_plans WHERE day_key = ? AND id != ?',
            variables: [Variable.withString(dayKey), Variable.withString(id)],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        final localVersion = await _localVersion(type, localId);
        if (incomingVersion != null &&
            localVersion != null &&
            !_incomingWins(incomingVersion, incomingDevice, localVersion)) {
          return false;
        }
        // The incoming plan wins. Deleting the loser cascades to its items, so
        // capture them first and re-create them under the winner. Losing tasks
        // would otherwise vanish without an error. The write itself happens
        // with outbox capture suppressed; the moved rows are queued afterwards.
        final movedItems = await _db
            .customSelect(
              'SELECT * FROM daily_plan_items WHERE plan_id = ?',
              variables: [Variable.withString(localId)],
            )
            .get();
        await _db.customStatement('DELETE FROM daily_plans WHERE id = ?', [
          localId,
        ]);
        await _upsertRow(schema.table, schema.columns, values);
        await _restorePlanItems(id, movedItems);
        await _recordVersion(
          type,
          id,
          incomingVersion,
          incomingDevice,
          local,
          deleted: false,
        );
        return true;
      }
    }
    if (type == 'daily_plan_item') {
      // Both task-reference columns are constrained, so reject a payload that
      // would fail the CHECK instead of rejecting the whole batch.
      final todoId = payload['todo_item_id'];
      final projectTaskId = payload['project_task_id'];
      if ((todoId is String) == (projectTaskId is String)) {
        throw const FormatException('Invalid plan item task');
      }
      final planId = payload['plan_id'];
      if (planId is! String || !(await _rowExists('daily_plans', planId))) {
        return false;
      }
      final taskTable = todoId is String ? 'todo_items' : 'tasks';
      final taskId = todoId is String ? todoId : projectTaskId as String;
      if (!(await _rowExists(taskTable, taskId))) return false;

      // A task can appear only once per plan. When the other device already
      // has a different row for the same task, keep whichever version is newer
      // and drop the loser.
      final taskColumn = todoId is String ? 'todo_item_id' : 'project_task_id';
      final clash = await _db
          .customSelect(
            'SELECT id FROM daily_plan_items '
            'WHERE plan_id = ? AND $taskColumn = ? AND id != ?',
            variables: [
              Variable.withString(planId),
              Variable.withString(taskId),
              Variable.withString(id),
            ],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        final localVersion = await _localVersion(type, localId);
        if (incomingVersion != null &&
            localVersion != null &&
            !_incomingWins(incomingVersion, incomingDevice, localVersion)) {
          return false;
        }
        await _db.customStatement('DELETE FROM daily_plan_items WHERE id = ?', [
          localId,
        ]);
      }
    }

    await _upsertRow(schema.table, schema.columns, values);
    await _recordVersion(
      type,
      id,
      incomingVersion,
      incomingDevice,
      local,
      deleted: false,
    );
    return true;
  }

  Future<void> _upsertRow(
    String table,
    List<String> columns,
    List<Object?> values,
  ) async {
    final placeholders = List.filled(columns.length, '?').join(', ');
    final columnList = columns.join(', ');
    final updates = columns
        .where((column) => column != 'id')
        .map((column) => '$column = excluded.$column')
        .join(', ');
    await _db.customStatement(
      'INSERT INTO $table ($columnList) VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      values,
    );
  }

  /// Re-creates a losing plan's items under [planId], skipping any task the
  /// winner already plans. The rows are touched again after outbox capture is
  /// re-enabled, so the other device learns their new parent.
  Future<void> _restorePlanItems(String planId, List<QueryRow> rows) async {
    if (rows.isEmpty) return;
    final existing = await _db
        .customSelect(
          'SELECT todo_item_id, project_task_id FROM daily_plan_items '
          'WHERE plan_id = ?',
          variables: [Variable.withString(planId)],
        )
        .get();
    final planned = <String>{
      for (final row in existing)
        if (row.readNullable<String>('todo_item_id') != null)
          'todo:${row.readNullable<String>('todo_item_id')}'
        else
          'task:${row.readNullable<String>('project_task_id')}',
    };
    for (final row in rows) {
      final itemId = row.read<String>('id');
      final todoId = row.readNullable<String>('todo_item_id');
      final taskId = row.readNullable<String>('project_task_id');
      final key = todoId != null ? 'todo:$todoId' : 'task:$taskId';
      if (!planned.add(key)) continue;
      if (await _rowExists('daily_plan_items', itemId)) continue;
      await _db.customStatement(
        'INSERT INTO daily_plan_items '
        '(id, plan_id, todo_item_id, project_task_id, sort_order, '
        'planned_minutes, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          itemId,
          planId,
          todoId,
          taskId,
          row.read<int>('sort_order'),
          row.readNullable<int>('planned_minutes'),
          row.read<int>('created_at'),
          row.read<int>('updated_at'),
        ],
      );
      _republishPlanItems.add(itemId);
    }
  }

  bool _incomingWins(
    int incomingVersion,
    String? incomingDevice,
    _LocalVersion local,
  ) {
    if (incomingVersion != local.updatedAt) {
      return incomingVersion > local.updatedAt;
    }
    // Exact tie: the higher device id wins on both sides. The same device with
    // the same version is a replay of a change that was already applied.
    return (incomingDevice ?? '').compareTo(local.deviceId ?? '') > 0;
  }

  Future<bool> _todoExists(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM todo_items WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> _rowExists(String table, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<_LocalVersion?> _localVersion(String type, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT updated_at, device_id FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          variables: [Variable.withString(type), Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return _LocalVersion(
      rows.first.read<int>('updated_at'),
      rows.first.readNullable<String>('device_id'),
    );
  }

  Future<void> _recordVersion(
    String type,
    String id,
    int? incomingVersion,
    String? incomingDevice,
    _LocalVersion? local, {
    required bool deleted,
  }) async {
    // Changes from a peer that predates versioning are applied unconditionally
    // and stamped just after whatever version this row already had.
    final version =
        incomingVersion ??
        _maxInt(
          AppClock.now().millisecondsSinceEpoch,
          (local?.updatedAt ?? 0) + 1,
        );
    await _db.customStatement(
      'INSERT INTO sync_row_versions '
      '(entity_type, entity_id, updated_at, device_id, deleted) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id) DO UPDATE SET '
      'updated_at = excluded.updated_at, device_id = excluded.device_id, '
      'deleted = excluded.deleted',
      [type, id, version, incomingDevice, deleted ? 1 : 0],
    );
  }

  static int _maxInt(int a, int b) => a > b ? a : b;
}

class _LocalVersion {
  const _LocalVersion(this.updatedAt, this.deviceId);

  final int updatedAt;
  final String? deviceId;
}
