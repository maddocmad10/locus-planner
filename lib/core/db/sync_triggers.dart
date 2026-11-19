part of 'app_database.dart';

/// Outbox trigger SQL and the per-row sync version table.
///
/// Kept in an extension so the migration/query surface in pp_database.dart
/// stays focused while the trigger bodies remain in one auditable place.
extension _SyncTriggers on AppDatabase {
  /// Per-row version used to resolve sync conflicts. It is a plain SQLite
  /// table (not a Drift table) so adding it does not change generated code.
  /// `updated_at` is epoch milliseconds; `deleted` marks a tombstone.
  Future<void> _createSyncVersionTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_row_versions (
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        device_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      ) WITHOUT ROWID
    ''');
  }

  String get _nowMsSql =>
      "CAST(ROUND((julianday('now') - 2440587.5) * 86400000.0) AS INTEGER)";

  String _versionLookupSql(String type, String idRef) =>
      '(SELECT updated_at FROM sync_row_versions '
      "WHERE entity_type = '$type' AND entity_id = $idRef)";

  /// Appends the row's current version to a `json_object(...)` payload.
  ///
  /// Most tables expose their business timestamp as `updated_at`, so payloads
  /// use the same key for the sync version. Tables that already store a real
  /// `updated_at` column (the My Day tables) use `sync_updated_at` instead so
  /// the two values cannot overwrite each other.
  String _withVersion(
    String payload,
    String type,
    String idRef, {
    String versionKey = 'updated_at',
  }) =>
      "${payload.substring(0, payload.length - 1)}, '$versionKey', "
      '${_versionLookupSql(type, idRef)})';

  /// Stamps a local edit. The new version is at least one more than the
  /// previous one, so an edit made after receiving a change from a device with
  /// a fast clock still wins over that change.
  ///
  /// The first statement deliberately avoids `INSERT OR IGNORE`: a trigger
  /// inherits the conflict policy of the statement that fired it, so an upsert
  /// (`ON CONFLICT DO UPDATE`) or `INSERT OR REPLACE` on a synced table would
  /// override the IGNORE and fail on the existing version row.
  String _bumpVersionSql(String type, String idRef, {required bool deleted}) =>
      '''
          INSERT INTO sync_row_versions (entity_type, entity_id, updated_at, device_id, deleted)
          SELECT '$type', $idRef, 0, NULL, 0
          WHERE NOT EXISTS (
            SELECT 1 FROM sync_row_versions
            WHERE entity_type = '$type' AND entity_id = $idRef
          );
          UPDATE sync_row_versions
          SET updated_at = MAX($_nowMsSql, updated_at + 1),
            device_id = (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'),
            deleted = ${deleted ? 1 : 0}
          WHERE entity_type = '$type' AND entity_id = $idRef;
      ''';

  /// Triggers record changes atomically with the user's transaction.
  /// Future remote-apply code should set sync.suppress_outbox='1' in its
  /// transaction, apply changes, and restore it to '0' before committing.
  Future<void> _createSyncOutboxTriggers() async {
    // A migration step may rebuild triggers before the optional event columns
    // exist. Emit their defaults in that case; the final rebuild after the
    // columns are added writes the real NEW.* references.
    final hasEventRecurrenceColumns = await _columnExists('events', 'all_day');
    final hasEventFormat = await _columnExists('events', 'description_format');
    final eventBasePayload = hasEventRecurrenceColumns
        ? "json_object('id', NEW.id, 'title', NEW.title, 'description', NEW.description, 'start_time', NEW.start_time, 'end_time', NEW.end_time, 'category', NEW.category, 'has_reminder', NEW.has_reminder, 'reminder_minutes', NEW.reminder_minutes, 'recurrence_rule', NEW.recurrence_rule, 'all_day', NEW.all_day, 'recurrence_end', NEW.recurrence_end, 'recurrence_exceptions', NEW.recurrence_exceptions)"
        : "json_object('id', NEW.id, 'title', NEW.title, 'description', NEW.description, 'start_time', NEW.start_time, 'end_time', NEW.end_time, 'category', NEW.category, 'has_reminder', NEW.has_reminder, 'reminder_minutes', NEW.reminder_minutes, 'recurrence_rule', NEW.recurrence_rule, 'all_day', 0, 'recurrence_end', NULL, 'recurrence_exceptions', '[]')";
    // A migration may rebuild triggers before schema 21 adds the format
    // columns; emit their defaults until the real columns exist.
    final eventPayload =
        '${eventBasePayload.substring(0, eventBasePayload.length - 1)}, '
        "'description_format', "
        '${hasEventFormat ? 'NEW.description_format' : "'plain'"})';
    final hasTodoFormat = await _columnExists('todo_items', 'notes_format');
    final todoPayload =
        "json_object('id', NEW.id, 'title', NEW.title, 'notes', NEW.notes, 'completed', NEW.completed, 'created_at', NEW.created_at, 'start_date', NEW.start_date, 'due_date', NEW.due_date, 'priority', NEW.priority, 'tags', NEW.tags, 'recurrence_rule', NEW.recurrence_rule, 'parent_id', NEW.parent_id, 'project_id', NEW.project_id, 'reminder_at', NEW.reminder_at, 'estimated_minutes', NEW.estimated_minutes, 'is_important', NEW.is_important, 'urgency_override', NEW.urgency_override, "
        "'notes_format', ${hasTodoFormat ? 'NEW.notes_format' : "'plain'"})";
    final tables = <({String table, String type, String id, String payload, String versionKey})>[
      (
        table: 'projects',
        type: 'project',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'name', NEW.name, 'description', NEW.description, 'created_at', NEW.created_at, 'target_date', NEW.target_date, 'target_progress', NEW.target_progress)",
      ),
      (
        table: 'events',
        type: 'event',
        id: 'id',
        versionKey: 'updated_at',
        payload: eventPayload,
      ),
      (
        table: 'tasks',
        type: 'project_task',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'project_id', NEW.project_id, 'title', NEW.title, 'completed', NEW.completed, 'status_key', NEW.status_key, 'start_date', NEW.start_date, 'due_date', NEW.due_date, 'estimated_minutes', NEW.estimated_minutes, 'priority', NEW.priority, 'sort_order', NEW.sort_order)",
      ),
      (
        table: 'project_statuses',
        type: 'project_status',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'project_id', NEW.project_id, 'status_key', NEW.status_key, 'name', NEW.name, 'color_token', NEW.color_token, 'position', NEW.position, 'is_done', NEW.is_done, 'is_default', NEW.is_default, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'project_milestones',
        type: 'project_milestone',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'project_id', NEW.project_id, 'title', NEW.title, 'description', NEW.description, 'target_date', NEW.target_date, 'completed_at', NEW.completed_at, 'position', NEW.position, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'task_dependencies',
        type: 'task_dependency',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'predecessor_task_id', NEW.predecessor_task_id, 'successor_task_id', NEW.successor_task_id, 'dependency_type', NEW.dependency_type, 'lag_minutes', NEW.lag_minutes, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'habits',
        type: 'habit',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'name', NEW.name, 'icon', NEW.icon, 'created_at', NEW.created_at, 'target_per_week', NEW.target_per_week)",
      ),
      (
        table: 'habit_logs',
        type: 'habit_log',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'habit_id', NEW.habit_id, 'date', NEW.date, 'completed', NEW.completed)",
      ),
      (
        table: 'todo_items',
        type: 'todo',
        id: 'id',
        versionKey: 'updated_at',
        payload: todoPayload,
      ),
      (
        table: 'todo_completions',
        type: 'todo_completion',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'todo_id', NEW.todo_id, 'occurrence_due', NEW.occurrence_due, 'completed_at', NEW.completed_at)",
      ),
      (
        table: 'diary_entries',
        type: 'diary_entry',
        id: 'id',
        versionKey: 'updated_at',
        payload:
            "json_object('id', NEW.id, 'date', NEW.date, 'mood', NEW.mood, 'content', NEW.content)",
      ),
      (
        table: 'daily_plans',
        type: 'daily_plan',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'day_key', NEW.day_key, 'intention', NEW.intention, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'daily_plan_items',
        type: 'daily_plan_item',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'plan_id', NEW.plan_id, 'todo_item_id', NEW.todo_item_id, 'project_task_id', NEW.project_task_id, 'sort_order', NEW.sort_order, 'planned_minutes', NEW.planned_minutes, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'task_schedule_blocks',
        type: 'task_schedule_block',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'todo_item_id', NEW.todo_item_id, 'project_task_id', NEW.project_task_id, 'start_at', NEW.start_at, 'end_at', NEW.end_at, 'timezone_id', NEW.timezone_id, 'block_kind', NEW.block_kind, 'note', NEW.note, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'sort_order', NEW.sort_order)",
      ),
      (
        table: 'saved_filters',
        type: 'saved_filter',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'name', NEW.name, 'entity_scope', NEW.entity_scope, 'filter_json', NEW.filter_json, 'sort_json', NEW.sort_json, 'is_pinned', NEW.is_pinned, 'position', NEW.position, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at, 'definition_version', NEW.definition_version)",
      ),
      (
        table: 'planning_preferences',
        type: 'planning_preference',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'timezone_id', NEW.timezone_id, 'default_slot_minutes', NEW.default_slot_minutes, 'week_start_day', NEW.week_start_day, 'day_start_minute', NEW.day_start_minute, 'day_end_minute', NEW.day_end_minute, 'buffer_minutes', NEW.buffer_minutes, 'urgency_window_days', NEW.urgency_window_days, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'working_hours',
        type: 'working_hours',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'weekday', NEW.weekday, 'enabled', NEW.enabled, 'start_minute', NEW.start_minute, 'end_minute', NEW.end_minute, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      (
        table: 'working_breaks',
        type: 'working_break',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'weekday', NEW.weekday, 'start_minute', NEW.start_minute, 'end_minute', NEW.end_minute, 'label', NEW.label, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
      // Attachment metadata only. Bytes live outside SQLite in a local
      // content-addressed cache, so this row can travel through the existing
      // JSON channel without the 1 MiB body cap mattering.
      (
        table: 'attachments',
        type: 'attachment',
        id: 'id',
        versionKey: 'sync_updated_at',
        payload:
            "json_object('id', NEW.id, 'todo_id', NEW.todo_id, 'event_id', NEW.event_id, 'kind', NEW.kind, 'display_name', NEW.display_name, 'mime_type', NEW.mime_type, 'size_bytes', NEW.size_bytes, 'sha256', NEW.sha256, 'width', NEW.width, 'height', NEW.height, 'alt_text', NEW.alt_text, 'position', NEW.position, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
      ),
    ];
    for (final item in tables) {
      // A migration that runs from an older version may rebuild the triggers
      // before a later step creates a new synced table (My Day tables arrive in
      // schema 13). Skip tables that do not exist yet; the later step rebuilds
      // the trigger set again once they do.
      if (!await _tableExists(item.table)) continue;
      final prefix = 'sync_outbox_${item.table}';
      // Triggers are rebuilt on every upgrade because their bodies changed in
      // schema 9. Each one first bumps the row's version, then queues the
      // change with that version inside the payload.
      for (final suffix in const ['insert', 'update', 'delete']) {
        await customStatement('DROP TRIGGER IF EXISTS ${prefix}_$suffix');
      }
      final upsertPayload = _withVersion(
        item.payload,
        item.type,
        'NEW.${item.id}',
        versionKey: item.versionKey,
      );
      final deletePayload =
          "json_object('id', OLD.${item.id}, '${item.versionKey}', "
          "${_versionLookupSql(item.type, 'OLD.${item.id}')})";
      await customStatement('''
        CREATE TRIGGER ${prefix}_insert AFTER INSERT ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '${AppDatabase.syncSuppressOutboxSettingKey}'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $upsertPayload,
            (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER ${prefix}_update AFTER UPDATE ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '${AppDatabase.syncSuppressOutboxSettingKey}'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $upsertPayload,
            (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER ${prefix}_delete AFTER DELETE ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '${AppDatabase.syncSuppressOutboxSettingKey}'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'OLD.${item.id}', deleted: true)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', OLD.${item.id}, 'delete', $deletePayload,
            (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(id)',
    );
  }
}
