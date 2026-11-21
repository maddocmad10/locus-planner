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
        hlc_counter INTEGER NOT NULL DEFAULT 0,
        device_id TEXT,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (entity_type, entity_id)
      ) WITHOUT ROWID
    ''');
  }

  /// Schema v23 sync-hardening tables. They are raw SQL for the same reason as
  /// sync_row_versions: they are protocol state, not Drift entities.
  Future<void> _createPlatformReminderState() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS platform_reminder_state (
        id           TEXT PRIMARY KEY,
        kind         TEXT NOT NULL,
        entity_id    TEXT NOT NULL,
        fire_at      INTEGER NOT NULL,
        scheduled_at INTEGER NOT NULL,
        delivered_at INTEGER,
        snoozed_from TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_prs_fire '
      'ON platform_reminder_state (fire_at)',
    );
  }

  Future<void> _createImportReceiptTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS import_receipts (
        source_kind      TEXT NOT NULL,
        destination_id   TEXT NOT NULL,
        file_sha256      TEXT NOT NULL,
        row_number       INTEGER NOT NULL,
        target_id        TEXT,
        row_fingerprint  TEXT NOT NULL,
        imported_at_ms   INTEGER NOT NULL,
        PRIMARY KEY (source_kind, destination_id, file_sha256, row_number)
      ) WITHOUT ROWID
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_import_receipts_destination '
      'ON import_receipts (source_kind, destination_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_import_receipts_fingerprint '
      'ON import_receipts (source_kind, destination_id, row_fingerprint)',
    );
  }

  Future<void> _createCalendarSubscriptionTables() async {
    // Device-local desktop feed cache. Deliberately absent from the outbox,
    // logical exports, diagnostics and LAN sync snapshots.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS calendar_sources (
        id              TEXT PRIMARY KEY,
        label           TEXT NOT NULL,
        kind            TEXT NOT NULL DEFAULT 'ics_feed'
                        CHECK (kind = 'ics_feed'),
        secret_ref      TEXT NOT NULL,
        enabled         INTEGER NOT NULL DEFAULT 1,
        etag            TEXT,
        last_modified   TEXT,
        last_success_ms INTEGER,
        last_attempt_ms INTEGER,
        last_error_code TEXT
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS calendar_occurrences (
        source_id            TEXT NOT NULL
                             REFERENCES calendar_sources(id) ON DELETE CASCADE,
        uid                  TEXT NOT NULL,
        recurrence_key       TEXT NOT NULL,
        occurrence_start_key TEXT NOT NULL,
        title                TEXT NOT NULL,
        all_day              INTEGER NOT NULL DEFAULT 0,
        tzid                 TEXT,
        start_ms             INTEGER,
        end_ms               INTEGER,
        start_date           TEXT,
        end_date             TEXT,
        PRIMARY KEY (source_id, uid, recurrence_key, occurrence_start_key)
      ) WITHOUT ROWID
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_cal_occ_source_start '
      'ON calendar_occurrences (source_id, start_ms, start_date)',
    );
  }

  Future<void> _createSchema29Stores() async {
    Future<void> addColumnIfMissing(
      String table,
      String column,
      String sql,
    ) async {
      if (!await _columnExists(table, column)) {
        await customStatement('ALTER TABLE $table ADD COLUMN $sql');
      }
    }

    await addColumnIfMissing(
      'sync_peer_progress',
      'last_trusted_server_ms',
      'last_trusted_server_ms INTEGER',
    );
    await addColumnIfMissing(
      'sync_rejected_changes',
      'resolution_kind',
      'resolution_kind TEXT',
    );
    await addColumnIfMissing(
      'sync_rejected_changes',
      'last_attempt_ms',
      'last_attempt_ms INTEGER',
    );
    await addColumnIfMissing(
      'sync_rejected_changes',
      'payload_sha256',
      'payload_sha256 TEXT',
    );
    await addColumnIfMissing(
      'calendar_sources',
      'coverage_start_ms',
      'coverage_start_ms INTEGER',
    );
    await addColumnIfMissing(
      'calendar_sources',
      'coverage_end_ms',
      'coverage_end_ms INTEGER',
    );
    await addColumnIfMissing(
      'calendar_sources',
      'cache_revision',
      'cache_revision INTEGER NOT NULL DEFAULT 0',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_peer_exchange (
        peer_id                 TEXT NOT NULL,
        epoch                   TEXT NOT NULL,
        last_clean_ms           INTEGER,
        last_attempt_ms         INTEGER,
        last_trusted_server_ms  INTEGER,
        PRIMARY KEY (peer_id, epoch)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_change_receipts (
        peer_id        TEXT NOT NULL,
        epoch          TEXT NOT NULL,
        direction      TEXT NOT NULL,
        change_id      TEXT NOT NULL,
        payload_sha256 TEXT NOT NULL,
        revision       INTEGER,
        counter        INTEGER,
        operation      TEXT NOT NULL,
        outcome        TEXT NOT NULL,
        reason         TEXT,
        first_seen_ms  INTEGER NOT NULL,
        last_seen_ms   INTEGER NOT NULL,
        PRIMARY KEY (peer_id, epoch, direction, change_id)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS snapshot_session (
        snapshot_id               TEXT PRIMARY KEY,
        peer_id                   TEXT NOT NULL,
        epoch                     TEXT NOT NULL,
        phase                     TEXT NOT NULL,
        remote_cursor             INTEGER,
        resume_token              TEXT,
        trusted_baseline_server_ms INTEGER,
        created_at                INTEGER NOT NULL,
        updated_at                INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS snapshot_item (
        snapshot_id   TEXT NOT NULL
                      REFERENCES snapshot_session(snapshot_id) ON DELETE CASCADE,
        change_id     TEXT NOT NULL,
        ordinal       INTEGER NOT NULL,
        payload_json  TEXT NOT NULL,
        disposition   TEXT NOT NULL DEFAULT 'pending',
        reason        TEXT,
        updated_at    INTEGER NOT NULL,
        PRIMARY KEY (snapshot_id, change_id)
      ) WITHOUT ROWID
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_snapshot_item_restart '
      'ON snapshot_item (snapshot_id, disposition, ordinal)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS share_intake_state (
        intake_id   TEXT PRIMARY KEY,
        status      TEXT NOT NULL,
        claimed_at  INTEGER,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS share_intake_files (
        intake_id     TEXT NOT NULL,
        ordinal       INTEGER NOT NULL,
        attachment_id TEXT,
        status        TEXT NOT NULL,
        reason        TEXT,
        updated_at    INTEGER NOT NULL,
        PRIMARY KEY (intake_id, ordinal)
      ) WITHOUT ROWID
    ''');
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_todo_completions_occurrence '
      'ON todo_completions (todo_id, occurrence_key) '
      'WHERE occurrence_key IS NOT NULL',
    );
  }

  Future<void> _createSyncReliabilityTables() async {
    // Durable per-peer exchange progress. A cursor only advances when every
    // preceding change has a durable outcome (applied, replay, superseded or a
    // retained repair record).
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_peer_progress (
        peer_id          TEXT NOT NULL,
        epoch            TEXT NOT NULL,
        direction        TEXT NOT NULL CHECK (direction IN ('push', 'pull')),
        cursor           INTEGER NOT NULL DEFAULT 0 CHECK (cursor >= 0),
        last_attempt_ms  INTEGER,
        last_exchange_ms INTEGER,
        last_clean_ms    INTEGER,
        error_code       TEXT,
        PRIMARY KEY (peer_id, epoch, direction)
      ) WITHOUT ROWID
    ''');
    // A rejected change keeps its original revision so it can be retried or
    // explicitly discarded. Payloads stay inside the encrypted planner DB.
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_rejected_changes (
        peer_id       TEXT NOT NULL,
        epoch         TEXT NOT NULL,
        direction     TEXT NOT NULL,
        change_id     TEXT NOT NULL,
        entity_type   TEXT NOT NULL,
        entity_id     TEXT NOT NULL,
        operation     TEXT NOT NULL,
        payload_json  TEXT NOT NULL,
        reason_code   TEXT NOT NULL,
        attempts      INTEGER NOT NULL DEFAULT 0,
        first_seen_ms INTEGER NOT NULL,
        last_seen_ms  INTEGER NOT NULL,
        resolved_ms   INTEGER,
        PRIMARY KEY (peer_id, epoch, direction, change_id)
      ) WITHOUT ROWID
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_src_open '
      'ON sync_rejected_changes (peer_id, epoch, direction, resolved_ms)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_src_resolved '
      'ON sync_rejected_changes (resolved_ms)',
    );
  }

  Future<void> _createSyncHardeningTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_field_versions (
        entity_type TEXT NOT NULL,
        entity_id   TEXT NOT NULL,
        field       TEXT NOT NULL,
        updated_at  INTEGER NOT NULL,
        hlc_counter INTEGER NOT NULL DEFAULT 0,
        device_id   TEXT,
        PRIMARY KEY (entity_type, entity_id, field)
      ) WITHOUT ROWID
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_clock (
        id           INTEGER PRIMARY KEY CHECK (id = 1),
        last_wall    INTEGER NOT NULL,
        last_counter INTEGER NOT NULL
      )
    ''');
    await customStatement(
      'INSERT OR IGNORE INTO sync_clock (id, last_wall, last_counter) '
      'VALUES (1, 0, 0)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_log (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at  INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        peer_id     TEXT,
        transport   TEXT NOT NULL DEFAULT 'lan',
        direction   TEXT NOT NULL,
        applied     INTEGER NOT NULL DEFAULT 0,
        skipped     INTEGER NOT NULL DEFAULT 0,
        rejected    INTEGER NOT NULL DEFAULT 0,
        error_code  TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_log_started '
      'ON sync_log (started_at)',
    );
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type  TEXT NOT NULL,
        entity_id    TEXT NOT NULL,
        field        TEXT,
        kind         TEXT NOT NULL,
        loser_value  TEXT,
        loser_device TEXT,
        loser_wall   INTEGER NOT NULL,
        winner_wall  INTEGER NOT NULL,
        created_at   INTEGER NOT NULL,
        reviewed_at  INTEGER
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open '
      'ON sync_conflicts (reviewed_at, created_at)',
    );
  }

  String get _nowMsSql =>
      "CAST(ROUND((julianday('now') - 2440587.5) * 86400000.0) AS INTEGER)";

  /// Wall clock used by local edits, with the phone's measured skew applied.
  /// The desktop keeps the setting absent/zero.
  String get _correctedNowMsSql =>
      "$_nowMsSql + COALESCE((SELECT CAST(value AS INTEGER) FROM app_settings "
      "WHERE key = '${AppDatabase.syncClockSkewMsSettingKey}'), 0)";

  /// Fields that participate in per-field merge for the first wave. The id is
  /// deliberately excluded; row identity never conflicts.
  static const _fieldColumns = <String, List<String>>{
    'project': [
      'name',
      'description',
      'created_at',
      'target_date',
      'target_progress',
    ],
    'event': [
      'title',
      'description',
      'description_format',
      'start_time',
      'end_time',
      'category',
      'has_reminder',
      'reminder_minutes',
      'recurrence_rule',
      'recurrence_spec',
      'all_day',
      'recurrence_end',
      'recurrence_exceptions',
    ],
    'project_task': [
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
    'habit': ['name', 'icon', 'created_at', 'target_per_week'],
    'todo': [
      'title',
      'notes',
      'notes_format',
      'completed',
      'created_at',
      'start_date',
      'due_date',
      'priority',
      'tags',
      'recurrence_rule',
      'recurrence_spec',
      'parent_id',
      'project_id',
      'reminder_at',
      'estimated_minutes',
      'is_important',
      'urgency_override',
    ],
  };

  /// Upserts one sync_field_versions row per changed field. All fields in a
  /// single local edit share the just-bumped row version.
  String _fieldVersionSql(
    String type, {
    required bool insert,
    List<String>? fields,
  }) {
    final columns = fields ?? _fieldColumns[type];
    if (columns == null) return '';
    final buffer = StringBuffer();
    for (final field in columns) {
      final changed = insert ? '' : ' AND (NEW.$field IS NOT OLD.$field)';
      buffer.writeln('''
        INSERT INTO sync_field_versions
          (entity_type, entity_id, field, updated_at, hlc_counter, device_id)
        SELECT '$type', NEW.id, '$field', v.updated_at, v.hlc_counter, v.device_id
        FROM sync_row_versions v
        WHERE v.entity_type = '$type' AND v.entity_id = NEW.id$changed
        ON CONFLICT(entity_type, entity_id, field) DO UPDATE SET
          updated_at = excluded.updated_at,
          hlc_counter = excluded.hlc_counter,
          device_id = excluded.device_id;
      ''');
    }
    return buffer.toString();
  }

  /// JSON object of every tracked field version, emitted as payload.fv.
  ///
  /// All tracked fields are emitted, not only the columns changed by this
  /// statement: a field last edited on another device must keep its older
  /// field version so an unrelated later row edit cannot overwrite it through
  /// the row-version fallback.
  String _fieldVersionsJson(
    String type, {
    required bool insert,
    List<String>? fields,
  }) {
    if (!_fieldColumns.containsKey(type)) return "'{}'";
    // The caller may narrow the list when an intermediate migration schema
    // does not yet contain a newer column.
    if (fields != null && fields.isEmpty) return "'{}'";
    // field-origins-v2: [wallMs, counter, originalWriterId]. Older readers use
    // the first two entries and fall back to the row origin, so this stays
    // wire-compatible during the upgrade window.
    return "(SELECT json_group_object(field, json_array(updated_at, hlc_counter, device_id)) "
        "FROM sync_field_versions WHERE entity_type = '$type' "
        "AND entity_id = NEW.id)";
  }

  String _hlcLookupSql(String type, String idRef, String column) =>
      '(SELECT $column FROM sync_row_versions '
      "WHERE entity_type = '$type' AND entity_id = $idRef)";

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
      '${_versionLookupSql(type, idRef)}, '
      "'hlc_counter', ${_hlcLookupSql(type, idRef, 'hlc_counter')})";

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
          UPDATE sync_clock
          SET last_counter = 0,
              last_wall = MAX($_correctedNowMsSql, last_wall + 1)
          WHERE id = 1;
          INSERT INTO sync_row_versions
            (entity_type, entity_id, updated_at, hlc_counter, device_id, deleted)
          SELECT '$type', $idRef, 0, 0, NULL, 0
          WHERE NOT EXISTS (
            SELECT 1 FROM sync_row_versions
            WHERE entity_type = '$type' AND entity_id = $idRef
          );
          UPDATE sync_row_versions
          SET updated_at = (SELECT last_wall FROM sync_clock WHERE id = 1),
            hlc_counter = (SELECT last_counter FROM sync_clock WHERE id = 1),
            device_id = (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'),
            deleted = ${deleted ? 1 : 0}
          WHERE entity_type = '$type' AND entity_id = $idRef;
      ''';

  /// Triggers record changes atomically with the user's transaction.
  /// Future remote-apply code should set sync.suppress_outbox='1' in its
  /// transaction, apply changes, and restore it to '0' before committing.
  Future<void> _createSyncOutboxTriggers() async {
    // Triggers now read the HLC clock and write field versions. Make sure the
    // v23 protocol tables exist before any migration step rebuilds a trigger,
    // including steps that run long before the v23 block.
    await _createSyncVersionTable();
    if (!await _columnExists('sync_row_versions', 'hlc_counter')) {
      await customStatement(
        'ALTER TABLE sync_row_versions '
        'ADD COLUMN hlc_counter INTEGER NOT NULL DEFAULT 0',
      );
    }
    await _createSyncHardeningTables();
    // A migration step may rebuild triggers before the optional event columns
    // exist. Emit their defaults in that case; the final rebuild after the
    // columns are added writes the real NEW.* references.
    final hasEventRecurrenceColumns = await _columnExists('events', 'all_day');
    final hasEventFormat = await _columnExists('events', 'description_format');
    final hasEventSpec = await _columnExists('events', 'recurrence_spec');
    final eventBasePayload = hasEventRecurrenceColumns
        ? "json_object('id', NEW.id, 'title', NEW.title, 'description', NEW.description, 'start_time', NEW.start_time, 'end_time', NEW.end_time, 'category', NEW.category, 'has_reminder', NEW.has_reminder, 'reminder_minutes', NEW.reminder_minutes, 'recurrence_rule', NEW.recurrence_rule, 'recurrence_spec', ${hasEventSpec ? 'NEW.recurrence_spec' : 'NULL'}, 'all_day', NEW.all_day, 'recurrence_end', NEW.recurrence_end, 'recurrence_exceptions', NEW.recurrence_exceptions)"
        : "json_object('id', NEW.id, 'title', NEW.title, 'description', NEW.description, 'start_time', NEW.start_time, 'end_time', NEW.end_time, 'category', NEW.category, 'has_reminder', NEW.has_reminder, 'reminder_minutes', NEW.reminder_minutes, 'recurrence_rule', NEW.recurrence_rule, 'recurrence_spec', NULL, 'all_day', 0, 'recurrence_end', NULL, 'recurrence_exceptions', '[]')";
    // A migration may rebuild triggers before schema 21 adds the format
    // columns; emit their defaults until the real columns exist.
    final eventPayload =
        '${eventBasePayload.substring(0, eventBasePayload.length - 1)}, '
        "'description_format', "
        '${hasEventFormat ? 'NEW.description_format' : "'plain'"})';
    final hasTodoFormat = await _columnExists('todo_items', 'notes_format');
    final hasTodoSpec = await _columnExists('todo_items', 'recurrence_spec');
    final hasCompletionKey = await _columnExists(
      'todo_completions',
      'occurrence_key',
    );
    final todoPayload =
        "json_object('id', NEW.id, 'title', NEW.title, 'notes', NEW.notes, 'completed', NEW.completed, 'created_at', NEW.created_at, 'start_date', NEW.start_date, 'due_date', NEW.due_date, 'priority', NEW.priority, 'tags', NEW.tags, 'recurrence_rule', NEW.recurrence_rule, 'recurrence_spec', ${hasTodoSpec ? 'NEW.recurrence_spec' : 'NULL'}, 'parent_id', NEW.parent_id, 'project_id', NEW.project_id, 'reminder_at', NEW.reminder_at, 'estimated_minutes', NEW.estimated_minutes, 'is_important', NEW.is_important, 'urgency_override', NEW.urgency_override, "
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
            "json_object('id', NEW.id, 'todo_id', NEW.todo_id, 'occurrence_due', NEW.occurrence_due, 'completed_at', NEW.completed_at, 'occurrence_key', ${hasCompletionKey ? 'NEW.occurrence_key' : 'NULL'})",
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
      var availableFields = _fieldColumns[item.type];
      if (availableFields != null) {
        final specMissing =
            (item.type == 'todo' && !hasTodoSpec) ||
            (item.type == 'event' && !hasEventSpec);
        if (specMissing) {
          availableFields = availableFields
              .where((field) => field != 'recurrence_spec')
              .toList();
        }
      }
      final hasFields = availableFields != null && availableFields.isNotEmpty;
      final insertPayload = hasFields
          ? "json_set($upsertPayload, '\$.fv', json(COALESCE("
                "${_fieldVersionsJson(item.type, insert: true, fields: availableFields)}, '{}')))"
          : upsertPayload;
      final updatePayload = hasFields
          ? "json_set($upsertPayload, '\$.fv', json(COALESCE("
                "${_fieldVersionsJson(item.type, insert: false, fields: availableFields)}, '{}')))"
          : upsertPayload;
      final insertFieldSql = _fieldVersionSql(
        item.type,
        insert: true,
        fields: availableFields,
      );
      final updateFieldSql = _fieldVersionSql(
        item.type,
        insert: false,
        fields: availableFields,
      );
      final deletePayload =
          "json_object('id', OLD.${item.id}, '${item.versionKey}', "
          "${_versionLookupSql(item.type, 'OLD.${item.id}')}, "
          "'hlc_counter', ${_hlcLookupSql(item.type, 'OLD.${item.id}', 'hlc_counter')}, "
          "'deleted', 1, 'device_id', "
          "${_hlcLookupSql(item.type, 'OLD.${item.id}', 'device_id')})";
      await customStatement('''
        CREATE TRIGGER ${prefix}_insert AFTER INSERT ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '${AppDatabase.syncSuppressOutboxSettingKey}'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          $insertFieldSql
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $insertPayload,
            (SELECT value FROM app_settings WHERE key = '${AppDatabase.syncDeviceIdSettingKey}'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER ${prefix}_update AFTER UPDATE ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '${AppDatabase.syncSuppressOutboxSettingKey}'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          $updateFieldSql
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $updatePayload,
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
