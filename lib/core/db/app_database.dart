import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/project_status.dart';
import '../utils/day_math.dart';
import '../utils/app_clock.dart';
import '../utils/sync_ids.dart';
import '../services/attachments/attachment_types.dart';
import '../services/error_log_service.dart';
import '../security/database_bootstrap.dart';
import '../security/database_identity.dart';
import '../security/database_security_errors.dart';
import 'database_maintenance.dart' show currentDatabaseSchemaVersion;

export 'database_maintenance.dart'
    show backupDatabaseBeforeUpgrade, currentDatabaseSchemaVersion;

part 'app_database.g.dart';
part 'tables.dart';
part 'sync_triggers.dart';

// ==================== DATABASE ====================

@DriftDatabase(
  tables: [
    Events,
    Projects,
    ProgressLogs,
    Tasks,
    DiaryEntries,
    Habits,
    HabitLogs,
    FocusSessions,
    AppSettings,
    TodoItems,
    TodoCompletions,
    DailyPlans,
    DailyPlanItems,
    TaskScheduleBlocks,
    SavedFilters,
    PlanningPreferences,
    WorkingHours,
    WorkingBreaks,
    ProjectStatuses,
    ProjectMilestones,
    TaskDependencies,
    Attachments,
    AttachmentBlobs,
    SyncOutbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Settings rows that describe this machine's current state, not the user's
  /// data. They are left out of backups and never replaced by an import.
  ///
  /// Theme and notification choices are user preferences, not transient state,
  /// so they stay in [app_settings] and travel with a backup. Reminder runtime
  /// state (the last time the desktop was running, the missed-reminder inbox
  /// and pending snoozes) is machine state and is intentionally excluded.
  static const remindersLastRunningSettingKey = 'reminders.last_running_at';
  static const remindersPendingSettingKey = 'reminders.pending';
  static const remindersSnoozedSettingKey = 'reminders.snoozed';
  static const focusSessionSettingKey = 'focus.active_session';
  static const focusPendingCompletionSettingKey = 'focus.pending_completion';
  static const diaryDraftSettingKey = 'diary.draft';
  static const plainBackupExportAcknowledgedSettingKey =
      'backup.plain_export_acknowledged';
  static const lastAutoBackupSettingKey = 'backup.last_auto';
  static const backupHealthLastAttemptKey = 'backup.health.last_attempt_ms';
  static const backupHealthLastFailureKey = 'backup.health.last_failure_code';
  static const backupHealthLastVerifiedKey = 'backup.health.last_verified_ms';
  static const backupHealthLastVerifiedFileKey =
      'backup.health.last_verified_file';
  static const backupHealthFormatKey = 'backup.health.format';
  static const backupHealthAttachmentsKey = 'backup.health.attachments';
  static const backupHealthMissingFilesKey = 'backup.health.missing_files';
  static const backupSetupLaterKey = 'backup.setup_later';
  static const backupIndependentDirectoryKey = 'backup.independent_directory';
  static const automaticBackupsIncludeAttachmentsKey =
      'backup.include_attachments';
  static const lastQuickCheckSettingKey = 'db.last_quick_check';
  static const syncDeviceIdSettingKey = 'sync.device_id';
  static const syncSuppressOutboxSettingKey = 'sync.suppress_outbox';
  static const syncServerPairedClientsSettingKey = 'sync.server.paired_clients';
  static const syncServerEnabledSettingKey = 'sync.server.enabled';
  static const syncEpochSettingKey = 'sync.epoch';
  static const syncOutboxPrunedThroughSettingKey = 'sync.outbox.pruned_through';
  static const syncTlsCertificateSettingKey = 'sync.tls.certificate';
  static const syncTlsPrivateKeySettingKey = 'sync.tls.private_key';
  static const syncClockSkewMsSettingKey = 'sync.clock_skew_ms';
  static const syncTombstoneHorizonSettingKey = 'sync.tombstone_horizon_ms';
  static const syncAllowCgnatSettingKey = 'sync.allow_cgnat';
  static const syncPrivateNetworkOnlySettingKey = 'sync.private_network_only';
  static const syncIdleStopMinutesSettingKey = 'sync.idle_stop_minutes';
  static const syncRebaseRequiredSettingKey = 'sync.rebase_required';
  static const syncPeerUpdateNeededSettingKey = 'sync.peer_update_needed';
  static const restoreGenerationSettingKey = 'restore.generation';
  static const restoreTimestampSettingKey = 'restore.timestamp';
  static const restoreSourceDatabaseIdSettingKey = 'restore.source_database_id';
  static const restoreSourceBackupSha256SettingKey =
      'restore.source_backup_sha256';
  static const restoreSourceExportedAtSettingKey = 'restore.source_exported_at';
  static const themeModeSettingKey = 'theme_mode';
  static const defaultLandingPageSettingKey = 'navigation.default_page';
  static const eventRemindersSettingKey = 'notifications.event_reminders';
  static const hideNotificationTitlesSettingKey = 'notifications.hide_titles';
  static const reminderSchedulingDegradedSettingKey =
      'notifications.scheduling_degraded';
  static const taskRemindersSettingKey = 'notifications.task_reminders';
  static const focusAlertsSettingKey = 'notifications.focus_alerts';
  static const transientSettingKeys = <String>[
    remindersLastRunningSettingKey,
    remindersPendingSettingKey,
    remindersSnoozedSettingKey,
    focusSessionSettingKey,
    focusPendingCompletionSettingKey,
    diaryDraftSettingKey,
    plainBackupExportAcknowledgedSettingKey,
    lastAutoBackupSettingKey,
    backupHealthLastAttemptKey,
    backupHealthLastFailureKey,
    backupHealthLastVerifiedKey,
    backupHealthLastVerifiedFileKey,
    backupHealthFormatKey,
    backupHealthAttachmentsKey,
    backupHealthMissingFilesKey,
    backupSetupLaterKey,
    backupIndependentDirectoryKey,
    reminderSchedulingDegradedSettingKey,
    automaticBackupsIncludeAttachmentsKey,
    lastQuickCheckSettingKey,
    syncDeviceIdSettingKey,
    syncSuppressOutboxSettingKey,
    syncServerPairedClientsSettingKey,
    syncServerEnabledSettingKey,
    syncEpochSettingKey,
    syncOutboxPrunedThroughSettingKey,
    syncTlsCertificateSettingKey,
    syncTlsPrivateKeySettingKey,
    syncClockSkewMsSettingKey,
    syncTombstoneHorizonSettingKey,
    syncAllowCgnatSettingKey,
    syncPrivateNetworkOnlySettingKey,
    syncIdleStopMinutesSettingKey,
    syncRebaseRequiredSettingKey,
    syncPeerUpdateNeededSettingKey,
    restoreGenerationSettingKey,
    restoreTimestampSettingKey,
    restoreSourceDatabaseIdSettingKey,
    restoreSourceBackupSha256SettingKey,
    restoreSourceExportedAtSettingKey,
    // Local storage policy: another device must choose its own image handling.
    AttachmentRules.keepOriginalSettingKey,
  ];

  static bool isTransientSetting(String key) =>
      transientSettingKeys.contains(key);

  /// For tests: pass `NativeDatabase.memory()`.
  ///
  /// [schemaVersion] lets an upgrade test stop at an intermediate release (for
  /// example 12) instead of always migrating to [currentSchemaVersion].
  AppDatabase.forTesting(super.e, {int? schemaVersion})
    : _schemaVersionOverride = schemaVersion;

  int? _schemaVersionOverride;

  static const currentSchemaVersion = currentDatabaseSchemaVersion;

  @override
  int get schemaVersion => _schemaVersionOverride ?? currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes();
      await _createTodoIndexes();
      await _createTodoCompletionIndexes();
      await _createDailyPlanIndexes();
      await _createCalendarIndexes();
      await _createProjectWorkflowIndexes();
      await _createAttachmentIndexes();
      await _createIntegrityIndexes();
      await _createSyncVersionTable();
      await _createSyncHardeningTables();
      await _createPlatformReminderState();
      await _createSyncReliabilityTables();
      await _createCalendarSubscriptionTables();
      await _createImportReceiptTables();
      await _createSyncOutboxTriggers();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2 && to >= 2) {
        await m.createTable(habits);
        await m.createTable(habitLogs);
        await m.createTable(focusSessions);
      }
      if (from < 3 && to >= 3) {
        await m.addColumn(events, events.recurrenceRule);
        await m.addColumn(projects, projects.targetProgress);
        await m.createTable(tasks);
        await m.createTable(appSettings);
        await _createIndexes();
      }
      if (from < 4 && to >= 4) {
        await m.createTable(todoItems);
        await _createTodoIndexes();
      }
      if (from < 5 && to >= 5) {
        // Foreign keys used to be unenforced, so deleting a project or habit
        // left orphaned children behind. Clean them up before enforcement.
        await _removeOrphans();
      }
      if (from < 6 && to >= 6) {
        await _createIndexes();
      }
      if (from < 7 && to >= 7) {
        // Prevent multiple completion records for the same habit on the same day.
        // Older databases may already contain duplicates, so keep the earliest row.
        await customStatement(
          'DELETE FROM habit_logs '
          'WHERE rowid NOT IN (SELECT MIN(rowid) FROM habit_logs GROUP BY habit_id, date)',
        );
        await _createIntegrityIndexes();
      }
      if (from < 8 && to >= 8) {
        await m.createTable(syncOutbox);
        await _createSyncOutboxTriggers();
      }
      if (from < 9 && to >= 9) {
        // Per-row versions for conflict resolution. The triggers are rebuilt
        // so they maintain the versions and carry them in each payload. Rows
        // that existed before this upgrade have no version until they are
        // next edited; an incoming change always wins over an unversioned row.
        await _createSyncVersionTable();
        await _createSyncOutboxTriggers();
      }
      if (from < 10 && to >= 10) {
        // To-do metadata: priority, tags and recurrence. The sync triggers are
        // rebuilt because their todo payload needs the new columns.
        await m.addColumn(todoItems, todoItems.priority);
        await m.addColumn(todoItems, todoItems.tags);
        await m.addColumn(todoItems, todoItems.recurrenceRule);
        await _createSyncOutboxTriggers();
      }
      if (from < 11 && to >= 11) {
        // Habits and habit logs join LAN sync, so the phone can toggle a habit
        // and send it back instead of only displaying desktop data.
        await _createSyncOutboxTriggers();
      }
      if (from < 12 && to >= 12) {
        // Notes, dates, subtasks, project links and reminders for to-dos. The
        // sync triggers are rebuilt because their todo payload gains columns.
        await m.addColumn(todoItems, todoItems.notes);
        await m.addColumn(todoItems, todoItems.startDate);
        await m.addColumn(todoItems, todoItems.parentId);
        await m.addColumn(todoItems, todoItems.projectId);
        await m.addColumn(todoItems, todoItems.reminderAt);
        await _createTodoIndexes();
        await _createSyncOutboxTriggers();
      }
      if (from < 13 && to >= 13) {
        // My Day is an additive planning layer. Existing task tables are left
        // untouched, and triggers are rebuilt so both new tables join sync.
        await m.createTable(dailyPlans);
        await m.createTable(dailyPlanItems);
        await _createDailyPlanIndexes();
        await _createSyncOutboxTriggers();
      }
      if (from < 15 && to >= 15) {
        // Event phase 2: all-day events and recurrence limits. Both columns are
        // nullable or defaulted so older rows are unaffected.
        await m.addColumn(events, events.allDay);
        await m.addColumn(events, events.recurrenceEnd);
        await m.addColumn(events, events.recurrenceExceptions);
      }
      if (from < 16 && to >= 16) {
        // Completion history for recurring to-dos.
        await m.createTable(todoCompletions);
        await _createTodoCompletionIndexes();
      }
      if (from < 14 && to >= 14) {
        // F4: habits and habit logs joined sync in 11, but rows that existed
        // before then were never queued. Rotate the epoch so every paired phone
        // treats its cursor as stale, fetches a snapshot (which already includes
        // habits and logs) and pushes its own state back.
        await customStatement('DELETE FROM app_settings WHERE key = ?', [
          syncEpochSettingKey,
        ]);
      }
      if (from < 16 && to >= 16) {
        // Rebuild once after every synced table/column change, so an early
        // upgrade step can never create a trigger whose payload references a
        // column that is added by a later step.
        await _createSyncOutboxTriggers();
      }
      if (from < 17 && to >= 17) {
        // Phase 2 professional planning: calendar time blocks, saved filter
        // definitions and local working-hours preferences. All new columns are
        // nullable/defaulted and all new tables are additive.
        await m.createTable(taskScheduleBlocks);
        await m.createTable(savedFilters);
        await m.createTable(planningPreferences);
        await m.createTable(workingHours);
        await m.createTable(workingBreaks);
        // This table is created from the current class shape. When the target
        // is before Phase 4, remove the later column so the intermediate
        // schema matches its historical snapshot.
        if (to < 20) {
          await customStatement(
            'ALTER TABLE planning_preferences DROP COLUMN urgency_window_days',
          );
        }
        await m.addColumn(todoItems, todoItems.estimatedMinutes);
        await _createCalendarIndexes();
        await _createSyncOutboxTriggers();
      }
      if (from < 18 && to >= 18) {
        // Phase 3 project workflow: task status/dates/estimate/priority plus
        // per-project status display metadata and milestones. `status_key` is
        // backfilled from the existing completed flag; no task ids change.
        await _createSyncVersionTable();
        await m.addColumn(tasks, tasks.statusKey);
        await m.addColumn(tasks, tasks.startDate);
        await m.addColumn(tasks, tasks.dueDate);
        await m.addColumn(tasks, tasks.estimatedMinutes);
        await m.addColumn(tasks, tasks.priority);
        await m.createTable(projectStatuses);
        await m.createTable(projectMilestones);
        await _createProjectWorkflowIndexes(includeDependencies: false);
        await customStatement(
          'UPDATE tasks SET status_key = '
          "CASE WHEN completed = 1 THEN 'done' ELSE 'todo' END",
        );
        await _seedDefaultProjectStatuses();
        await _createSyncOutboxTriggers();
      }
      if (from < 19 && to >= 19) {
        // Phase 3 finish-to-start dependencies. No historical rows exist; the
        // repository validates endpoints, same-project membership and cycles.
        await m.createTable(taskDependencies);
        await _createProjectWorkflowIndexes();
        await _createSyncOutboxTriggers();
        // Paired phones must fetch a fresh snapshot: migration 18 added task
        // workflow columns and seeded status rows without queueing them.
        await customStatement('DELETE FROM app_settings WHERE key = ?', [
          syncEpochSettingKey,
        ]);
      }
      if (from < 20 && to >= 20) {
        // Phase 4 planning intelligence: user-assigned importance and an
        // optional urgency override on personal to-dos, plus the Eisenhower
        // urgency window in the planning profile. All additive/defaulted.
        // A create-table step from a very old schema may already have used the
        // current table shape, so check before altering.
        if (!await _columnExists('todo_items', 'is_important')) {
          await m.addColumn(todoItems, todoItems.isImportant);
        }
        if (!await _columnExists('todo_items', 'urgency_override')) {
          await m.addColumn(todoItems, todoItems.urgencyOverride);
        }
        if (!await _columnExists(
          'planning_preferences',
          'urgency_window_days',
        )) {
          await m.addColumn(
            planningPreferences,
            planningPreferences.urgencyWindowDays,
          );
        }
        await _createSyncOutboxTriggers();
      }
      if (from < 21 && to >= 21) {
        // Rich notes and attachment metadata. Format markers are additive and
        // default to `plain`, so every existing row stays valid and an older
        // peer keeps showing readable text. Attachment bytes never enter
        // SQLite; only metadata syncs, and `attachment_blobs` is a device-local
        // cache that is deliberately excluded from sync and backups.
        if (!await _columnExists('todo_items', 'notes_format')) {
          await m.addColumn(todoItems, todoItems.notesFormat);
        }
        if (!await _columnExists('events', 'description_format')) {
          await m.addColumn(events, events.descriptionFormat);
        }
        await m.createTable(attachments);
        await m.createTable(attachmentBlobs);
        await _createAttachmentIndexes();
        await _createSyncVersionTable();
        await _createSyncOutboxTriggers();
      }
      if (from < 22 && to >= 22) {
        // Accessibility alt text for attachments. Nullable, so every existing
        // row remains valid and older peers simply omit the field.
        if (!await _columnExists('attachments', 'alt_text')) {
          await m.addColumn(attachments, attachments.altText);
        }
        await _createSyncOutboxTriggers();
      }
      if (from < 23 && to >= 23) {
        // Sync hardening: HLC counters, per-field versions, conflict/log
        // storage and the clock row. All raw SQL, all additive.
        if (!await _columnExists('sync_row_versions', 'hlc_counter')) {
          await customStatement(
            'ALTER TABLE sync_row_versions '
            'ADD COLUMN hlc_counter INTEGER NOT NULL DEFAULT 0',
          );
        }
        await _createSyncHardeningTables();
        await _createSyncOutboxTriggers();
      }
      if (from < 24 && to >= 24) {
        // Device-local state for OS-scheduled reminders (Windows toasts, iOS
        // notifications, Linux autostart). Never synced, never backed up.
        await _createPlatformReminderState();
      }
      if (from < 25 && to >= 25) {
        // Durable receipts and repair records. Existing row/field versions and
        // platform_reminder_state remain authoritative; the new tables start
        // empty. Rebuild the triggers so field origins carry the writer id and
        // delete payloads carry the tombstone version.
        await _createSyncReliabilityTables();
        await _createSyncOutboxTriggers();
      }
      if (from < 26 && to >= 26) {
        // Desktop-only read-only calendar feed cache. Device-local: never
        // queued by an outbox trigger, never in a logical export.
        await _createCalendarSubscriptionTables();
      }
      if (from < 27 && to >= 27) {
        // Todoist CSV import receipts. They accompany logical backups and keep
        // deliberately deleted tasks from being re-imported by a rerun.
        await _createImportReceiptTables();
      }
      if (from < 28 && to >= 28) {
        // Versioned richer recurrence. Nullable, so every historical rule
        // remains valid input; triggers are rebuilt for both new columns.
        if (!await _columnExists('todo_items', 'recurrence_spec')) {
          await m.addColumn(todoItems, todoItems.recurrenceSpec);
        }
        if (!await _columnExists('events', 'recurrence_spec')) {
          await m.addColumn(events, events.recurrenceSpec);
        }
        await _createSyncOutboxTriggers();
      }
    },
    beforeOpen: (details) async {
      // SQLite ignores REFERENCES / ON DELETE CASCADE unless this is switched
      // on for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
      // Keep temporary B-trees in memory so large sorts during migration or
      // reporting cannot spill plaintext rows into an OS temp file.
      await customStatement('PRAGMA temp_store = MEMORY');
      await customStatement(
        'INSERT OR IGNORE INTO sync_clock (id, last_wall, last_counter) '
        'VALUES (1, 0, 0)',
      );
      await _verifySecurityIdentity();
      await ensureDeviceIdentity();
      await ensureSyncEpoch();
      // Full integrity checks are reserved for creation/upgrades. A lightweight
      // quick_check runs at most once per calendar day on ordinary launches.
      if (details.wasCreated || details.hadUpgrade) {
        await verifyIntegrity(checkForeignKeys: false);
        // Older schema versions may contain orphan rows. Record the problem
        // rather than failing startup after a successful migration.
        await _logForeignKeyViolations();
      }
      await runDailyQuickCheck();
    },
  );

  /// Fail startup if SQLite's physical database structure is corrupt.
  Future<void> verifyIntegrity({bool checkForeignKeys = true}) async {
    final integrity = await customSelect('PRAGMA integrity_check').get();
    if (integrity.length != 1 || integrity.first.data.values.first != 'ok') {
      throw StateError('Database integrity check failed: $integrity');
    }
    if (checkForeignKeys) await _logForeignKeyViolations();
  }

  Future<void> _logForeignKeyViolations() async {
    final violations = await customSelect('PRAGMA foreign_key_check').get();
    if (violations.isNotEmpty) {
      // Keep startup available for legacy data; persist details for later repair.
      await ErrorLogService.log(
        StateError('SQLite foreign-key violations detected: $violations'),
        StackTrace.current,
      );
    }
  }

  /// Verifies the identity anchor inside an encrypted database.
  ///
  /// The anchor is the only trusted statement of "which database is this?"
  /// after decryption; external metadata is an untrusted hint. A missing table,
  /// a missing row or a disagreement fails closed. It is never recreated from
  /// the external metadata: that would let a replaced database inherit an old
  /// identity.
  Future<void> _verifySecurityIdentity() async {
    final context = DatabaseRuntimeContext.current;
    if (context == null || !context.encryptionEnabled) return;
    final metadata = context.metadata;
    if (metadata == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'An encrypted database was opened without identity metadata.',
      );
    }

    final table = await customSelect(
      "SELECT 1 AS present FROM sqlite_master "
      "WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(DatabaseIdentity.tableName)],
    ).get();
    if (table.isEmpty) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The encrypted database has no security identity table. It was not '
        'recreated from external metadata.',
      );
    }
    final rows = await customSelect(await _identitySelectSql()).get();
    if (rows.isEmpty) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The encrypted database has no security identity row. It was not '
        'recreated from external metadata.',
      );
    }

    final identity = _identityFromRow(rows.first);
    if (identity.formatVersion > DatabaseIdentity.currentFormatVersion) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unsupportedEncryption,
        'The encrypted database uses a newer security format.',
      );
    }
    identity.requireMatches(metadata);
  }

  /// Format-2 identity tables predate `updated_at`; both remain readable.
  Future<String> _identitySelectSql() async {
    final columns = await customSelect(
      'PRAGMA table_info(${DatabaseIdentity.tableName})',
    ).get();
    final hasUpdatedAt = columns.any((row) => row.data['name'] == 'updated_at');
    return hasUpdatedAt
        ? DatabaseIdentitySql.select
        : DatabaseIdentitySql.legacySelect;
  }

  DatabaseIdentity _identityFromRow(QueryRow row) => DatabaseIdentity(
    databaseId: row.read<String>('database_id'),
    keyId: row.read<String>('key_id'),
    keyGeneration: row.read<int>('key_generation'),
    cipherProfileId: row.read<String>('cipher_profile_id'),
    formatVersion: row.read<int>('format_version'),
    createdAt: DateTime.parse(row.read<String>('created_at')),
    updatedAt: row.data['updated_at'] is String
        ? DateTime.tryParse(row.data['updated_at'] as String)
        : null,
  );

  /// The encrypted identity, or null for a plaintext/test database.
  Future<DatabaseIdentity?> securityIdentity() async {
    final exists = await customSelect(
      "SELECT 1 AS present FROM sqlite_master "
      "WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(DatabaseIdentity.tableName)],
    ).get();
    if (exists.isEmpty) return null;
    final rows = await customSelect(DatabaseIdentitySql.select).get();
    if (rows.isEmpty) return null;
    return _identityFromRow(rows.first);
  }

  /// Provenance only. Never used to decide which key or database to open.
  Future<String?> sourceDatabaseId() async =>
      (await securityIdentity())?.databaseId;

  /// Runs SQLite's cheaper structural check at most once per calendar day.
  Future<void> runDailyQuickCheck() async {
    final today = AppClock.now().toIso8601String().substring(0, 10);
    const key = lastQuickCheckSettingKey;
    final rows = await customSelect(
      'SELECT value FROM app_settings WHERE key = ?',
      variables: [Variable.withString(key)],
    ).get();
    if (rows.isNotEmpty && rows.first.read<String>('value') == today) return;

    final result = await customSelect('PRAGMA quick_check').get();
    if (result.length != 1 || result.first.data.values.first != 'ok') {
      throw StateError('Database quick_check failed: $result');
    }
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: today),
    );
  }

  /// Identifies this database's change history. A paired phone remembers it
  /// and treats a different value as "the desktop was reset or replaced", which
  /// makes outbox cursors meaningless and forces a full re-sync. Created with
  /// the database, never regenerated on normal launch, and excluded from
  /// backups so a restored backup does not resurrect an old history.
  Future<String> ensureSyncEpoch() async {
    final existing = await getSetting(syncEpochSettingKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final epoch = const Uuid().v4();
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: syncEpochSettingKey, value: epoch),
    );
    return epoch;
  }

  /// Highest outbox id ever issued, even if those rows were pruned. Used as
  /// the "current" cursor so pruning can never make ids look like they went
  /// backwards. (The outbox is AUTOINCREMENT, so ids are never reused.)
  Future<int> outboxHead() async {
    final row = await customSelect(
      'SELECT MAX('
      "COALESCE((SELECT seq FROM sqlite_sequence WHERE name = 'sync_outbox'), 0), "
      'COALESCE((SELECT MAX(id) FROM sync_outbox), 0)) AS head',
    ).getSingle();
    final head = row.read<int>('head');
    final pruned = await outboxPrunedThrough();
    return head > pruned ? head : pruned;
  }

  /// Outbox rows with an id up to and including this value have been deleted.
  Future<int> outboxPrunedThrough() async {
    final raw = await getSetting(syncOutboxPrunedThroughSettingKey);
    return int.tryParse(raw ?? '') ?? 0;
  }

  /// Stable per-install ID. Stored locally, never regenerated on normal launch.
  Future<String> ensureDeviceIdentity() async {
    final existing = await getSetting(syncDeviceIdSettingKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: syncDeviceIdSettingKey, value: id),
    );
    return id;
  }

  Future<bool> _tableExists(String table) async {
    final rows = await customSelect(
      "SELECT 1 AS present FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable.withString(table)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(String table, String column) async {
    if (!await _tableExists(table)) return false;
    final rows = await customSelect('PRAGMA table_info($table)').get();
    return rows.any((row) => row.read<String>('name') == column);
  }

  Future<void> _removeOrphans() async {
    await customStatement(
      'DELETE FROM tasks WHERE project_id NOT IN (SELECT id FROM projects)',
    );
    await customStatement(
      'DELETE FROM progress_logs WHERE project_id NOT IN (SELECT id FROM projects)',
    );
    await customStatement(
      'DELETE FROM habit_logs WHERE habit_id NOT IN (SELECT id FROM habits)',
    );
    await customStatement(
      'UPDATE focus_sessions SET project_id = NULL '
      'WHERE project_id IS NOT NULL AND project_id NOT IN (SELECT id FROM projects)',
    );
  }

  Future<void> _createIntegrityIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_habit_logs_habit_date '
      'ON habit_logs(habit_id, date)',
    );
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_progress_ts ON progress_logs(timestamp)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_diary_date ON diary_entries(date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_sessions(start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_habit_logs_date ON habit_logs(date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_habit_logs_habit_date ON habit_logs(habit_id, date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_tasks_project_order ON tasks(project_id, sort_order)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_progress_project_ts ON progress_logs(project_id, timestamp)',
    );
  }

  Future<void> _createTodoIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_todo_parent ON todo_items(parent_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_todo_project ON todo_items(project_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_todo_due ON todo_items(due_date)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_todo_reminder ON todo_items(reminder_at)',
    );
  }

  Future<void> _createTodoCompletionIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_todo_completions_todo_completed '
      'ON todo_completions(todo_id, completed_at)',
    );
  }

  Future<void> _createDailyPlanIndexes() async {
    // A task can only be planned once per day, regardless of which task model
    // it comes from. Partial indexes keep the two reference columns apart.
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_daily_plan_todo '
      'ON daily_plan_items(plan_id, todo_item_id) '
      'WHERE todo_item_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_daily_plan_project_task '
      'ON daily_plan_items(plan_id, project_task_id) '
      'WHERE project_task_id IS NOT NULL',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_daily_plan_items_plan_order '
      'ON daily_plan_items(plan_id, sort_order)',
    );
  }

  Future<void> _createCalendarIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_schedule_blocks_start '
      'ON task_schedule_blocks(start_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_schedule_blocks_end '
      'ON task_schedule_blocks(end_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_schedule_blocks_todo '
      'ON task_schedule_blocks(todo_item_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_schedule_blocks_project_task '
      'ON task_schedule_blocks(project_task_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_saved_filters_scope_order '
      'ON saved_filters(entity_scope, position)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS ux_saved_filters_scope_name '
      'ON saved_filters(entity_scope, name COLLATE NOCASE)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_working_hours_weekday '
      'ON working_hours(weekday)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_working_breaks_weekday '
      'ON working_breaks(weekday)',
    );
  }

  Future<void> _createProjectWorkflowIndexes({
    bool includeDependencies = true,
  }) async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_statuses_project '
      'ON project_statuses(project_id, position)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_project_milestones_project '
      'ON project_milestones(project_id, target_date)',
    );
    if (!includeDependencies) return;
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_task_dependencies_successor '
      'ON task_dependencies(successor_task_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_task_dependencies_predecessor '
      'ON task_dependencies(predecessor_task_id)',
    );
  }

  Future<void> _createAttachmentIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachments_todo '
      'ON attachments(todo_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachments_event '
      'ON attachments(event_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachments_sha '
      'ON attachments(sha256)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_attachment_blobs_orphaned '
      'ON attachment_blobs(orphaned_at)',
    );
  }

  /// Seeds the five canonical statuses for every project that has none. Used by
  /// the v18 migration and by repositories before the first read. The ids are
  /// deterministic so two devices that upgrade offline converge on one row per
  /// (project, status key).
  Future<void> _seedDefaultProjectStatuses() async {
    final projects = await customSelect('SELECT id FROM projects').get();
    final now = AppClock.now().millisecondsSinceEpoch ~/ 1000;
    for (final project in projects) {
      final projectId = project.read<String>('id');
      for (final status in ProjectStatusCatalog.all) {
        await customStatement(
          'INSERT OR IGNORE INTO project_statuses '
          '(id, project_id, status_key, name, color_token, position, '
          'is_done, is_default, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)',
          [
            SyncIds.projectStatusId(projectId, status.key),
            projectId,
            status.key,
            status.label,
            status.colorToken,
            status.position,
            status.isDone ? 1 : 0,
            now,
            now,
          ],
        );
      }
    }
  }

  // ==================== APP SETTINGS ====================

  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  /// True when no user-authored rows exist in the tables the first-run flow
  /// seeds. Settings, sync state and transient reminder rows are ignored.
  Future<bool> isUserDataEmpty() async {
    for (final table in const <String>[
      'events',
      'todo_items',
      'projects',
      'habits',
      'diary_entries',
    ]) {
      final rows = await customSelect(
        'SELECT 1 AS present FROM $table LIMIT 1',
      ).get();
      if (rows.isNotEmpty) return false;
    }
    return true;
  }

  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, value: value),
    );
  }

  Future<void> deleteSetting(String key) async {
    await (delete(appSettings)..where((t) => t.key.equals(key))).go();
  }

  // ==================== EXISTING METHODS ====================
  Stream<List<Event>> watchAllEvents() => select(events).watch();

  Stream<List<Project>> watchProjects() => (select(
    projects,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  /// Emits project completion percentages from one aggregate query instead of
  /// running one task-count query per project. The stream also invalidates when
  /// either projects or tasks change.
  Stream<Map<String, double>> watchProjectProgress() {
    return customSelect(
      '''
        SELECT p.id AS project_id,
               CASE
                 WHEN COUNT(t.id) = 0 THEN 0.0
                 ELSE SUM(CASE WHEN t.completed = 1 THEN 1 ELSE 0 END) * 100.0
                      / COUNT(t.id)
               END AS progress
        FROM projects p
        LEFT JOIN tasks t ON t.project_id = p.id
        GROUP BY p.id
      ''',
      readsFrom: {projects, tasks},
    ).watch().map((rows) {
      return <String, double>{
        for (final row in rows)
          row.read<String>('project_id'): row.read<double>('progress'),
      };
    });
  }

  Stream<List<ProgressLog>> watchProgressForProject(String projectId) =>
      (select(progressLogs)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
          .watch();

  Stream<List<Task>> watchTasksForProject(String projectId) =>
      (select(tasks)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Stream<List<DiaryEntry>> watchDiaryEntries() => (select(
    diaryEntries,
  )..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  Stream<List<DiaryEntry>> watchDiaryEntriesForRange(
    DateTime from,
    DateTime to,
  ) {
    final start = DayMath.dateOnly(from);
    final end = DayMath.dateOnly(to);
    return (select(diaryEntries)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  Stream<List<Habit>> watchHabits() => select(habits).watch();

  Stream<List<FocusSession>> watchFocusSessions() => (select(
    focusSessions,
  )..orderBy([(t) => OrderingTerm.desc(t.startTime)])).watch();

  Stream<List<FocusSession>> watchFocusSessionsForDay(DateTime day) {
    final start = DayMath.dateOnly(day);
    final end = DayMath.addDays(start, 1);
    return (select(focusSessions)
          ..where(
            (t) =>
                t.startTime.isBiggerOrEqualValue(start) &
                t.startTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
        .watch();
  }

  Stream<List<FocusSession>> watchRecentFocusSessions({int limit = 5}) {
    return (select(focusSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(limit))
        .watch();
  }

  Stream<List<FocusSession>> watchFocusSessionsLastDays(int days) {
    final start = DayMath.addDays(
      DayMath.dateOnly(AppClock.now()),
      -(days - 1),
    );
    return (select(focusSessions)
          ..where((t) => t.startTime.isBiggerOrEqualValue(start))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

  Future<List<HabitLog>> habitLogsForRange(DateTime from, DateTime to) {
    final start = DayMath.dateOnly(from);
    final end = DayMath.dateOnly(to);
    return (select(habitLogs)..where(
          (t) =>
              t.date.isBiggerOrEqualValue(start) &
              t.date.isSmallerThanValue(end),
        ))
        .get();
  }

  Stream<List<HabitLog>> watchHabitLogsForRange(DateTime from, DateTime to) {
    final start = DayMath.dateOnly(from);
    final end = DayMath.dateOnly(to);
    return (select(habitLogs)
          ..where(
            (t) =>
                t.date.isBiggerOrEqualValue(start) &
                t.date.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .watch();
  }

  Future<List<HabitLog>> logsForHabitToday(String habitId) {
    final today = DayMath.dateOnly(AppClock.now());
    return (select(
      habitLogs,
    )..where((t) => t.habitId.equals(habitId) & t.date.equals(today))).get();
  }

  Future<int> completedHabitsToday() async {
    final today = DayMath.dateOnly(AppClock.now());
    final rows = await (select(
      habitLogs,
    )..where((t) => t.date.equals(today) & t.completed.equals(true))).get();
    return rows.map((row) => row.habitId).toSet().length;
  }

  Future<int> focusMinutesToday() async {
    final start = DayMath.dateOnly(AppClock.now());
    final end = DayMath.addDays(start, 1);
    final sessions =
        await (select(focusSessions)..where(
              (t) =>
                  t.startTime.isBiggerOrEqualValue(start) &
                  t.startTime.isSmallerThanValue(end),
            ))
            .get();
    return sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);
  }

  Future<DiaryEntry?> entryForDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return (select(
      diaryEntries,
    )..where((t) => t.date.equals(d))).getSingleOrNull();
  }

  Future<int> diaryStreak() async {
    final entries = await select(diaryEntries).get();
    return DayMath.consecutiveDayStreak(entries.map((e) => e.date));
  }

  Future<double> projectProgressPercent(String projectId) async {
    final taskList = await (select(
      tasks,
    )..where((t) => t.projectId.equals(projectId))).get();
    if (taskList.isEmpty) return 0.0;
    final completedCount = taskList.where((t) => t.completed).length;
    return (completedCount / taskList.length) * 100;
  }

  // ==================== PROJECT HELPER METHODS ====================
  /// Deletes a project together with its tasks and progress logs. Focus
  /// sessions are kept but unlinked. Done explicitly (inside a transaction) so
  /// it doesn't depend on the foreign-key pragma being active.
  Future<void> deleteProject(String projectId) async {
    await transaction(() async {
      await (delete(
        progressLogs,
      )..where((t) => t.projectId.equals(projectId))).go();
      await (delete(tasks)..where((t) => t.projectId.equals(projectId))).go();
      await (update(focusSessions)..where((t) => t.projectId.equals(projectId)))
          .write(const FocusSessionsCompanion(projectId: Value(null)));
      await (delete(projects)..where((t) => t.id.equals(projectId))).go();
    });
  }

  /// Deletes a habit together with its logs.
  Future<void> deleteHabit(String habitId) async {
    await transaction(() async {
      await (delete(habitLogs)..where((t) => t.habitId.equals(habitId))).go();
      await (delete(habits)..where((t) => t.id.equals(habitId))).go();
    });
  }

  Future<void> addTask(String projectId, String title) async {
    // Selecting and inserting in one transaction prevents two concurrent
    // callers from choosing the same next sort order.
    await transaction(() async {
      final last =
          await (select(tasks)
                ..where((t) => t.projectId.equals(projectId))
                ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)])
                ..limit(1))
              .getSingleOrNull();
      final newOrder = (last?.sortOrder ?? 0) + 1;

      await into(tasks).insert(
        TasksCompanion(
          id: Value(const Uuid().v4()),
          projectId: Value(projectId),
          title: Value(title),
          sortOrder: Value(newOrder),
        ),
      );
    });
  }

  /// Creates the five canonical status rows for [projectId] if they are
  /// missing. Deterministic ids make this safe to run on several devices.
  Future<void> ensureProjectStatuses(String projectId) async {
    final existing =
        await (select(projectStatuses)
              ..where((t) => t.projectId.equals(projectId))
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) return;
    final now = AppClock.now();
    await batch((batch) {
      batch.insertAll(projectStatuses, [
        for (final status in ProjectStatusCatalog.all)
          ProjectStatusesCompanion.insert(
            id: SyncIds.projectStatusId(projectId, status.key),
            projectId: projectId,
            statusKey: status.key,
            name: status.label,
            colorToken: Value(status.colorToken),
            position: Value(status.position),
            isDone: Value(status.isDone),
            isDefault: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
      ]);
    });
  }

  Future<void> toggleTask(String taskId, bool completed) async {
    await (update(tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(
        statusKey: Value(
          completed
              ? ProjectStatusCatalog.done.key
              : ProjectStatusCatalog.todo.key,
        ),
        completed: Value(completed),
      ),
    );
  }

  Future<void> logProjectProgress(
    String projectId,
    int value,
    String? note,
  ) async {
    await into(progressLogs).insert(
      ProgressLogsCompanion(
        id: Value(const Uuid().v4()),
        projectId: Value(projectId),
        value: Value(value),
        note: Value(note),
        timestamp: Value(AppClock.now()),
      ),
    );
  }

  Future<List<ProgressLog>> getProgressLogs(String projectId) async {
    return (select(progressLogs)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
  }

  // ==================== TODO LIST METHODS ====================
  Stream<List<TodoItem>> watchAllTodoItems() =>
      (select(todoItems)..orderBy([
            (t) => OrderingTerm.asc(t.completed),
            (t) => OrderingTerm.desc(t.priority),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
          .watch();

  Future<String> addTodoItem(
    String title,
    DateTime? dueDate, {
    String? id,
    String? notes,
    String notesFormat = 'plain',
    DateTime? startDate,
    int priority = 0,
    String tags = '[]',
    String? recurrenceRule,
    String? recurrenceSpec,
    String? parentId,
    String? projectId,
    DateTime? reminderAt,
  }) async {
    final todoId = id ?? const Uuid().v4();
    await into(todoItems).insert(
      TodoItemsCompanion(
        id: Value(todoId),
        title: Value(title),
        notes: Value(notes),
        notesFormat: Value(notesFormat == 'md1' ? 'md1' : 'plain'),
        createdAt: Value(AppClock.now()),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        priority: Value(priority),
        tags: Value(tags),
        recurrenceRule: Value(recurrenceRule),
        recurrenceSpec: Value(recurrenceSpec),
        parentId: Value(parentId),
        projectId: Value(projectId),
        reminderAt: Value(reminderAt),
      ),
    );
    return todoId;
  }

  Future<TodoItem?> getTodoItem(String id) =>
      (select(todoItems)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> toggleTodoItem(String id, bool completed) async {
    await (update(todoItems)..where((t) => t.id.equals(id))).write(
      TodoItemsCompanion(completed: Value(completed)),
    );
  }

  Future<void> deleteTodoItem(String id) async {
    await (delete(todoItems)..where((t) => t.id.equals(id))).go();
  }

  /// Appends one completion row for a recurring to-do. Callers run this in the
  /// same transaction as the due-date advance so history and the task agree.
  Future<String> addTodoCompletion({
    required String todoId,
    DateTime? occurrenceDue,
    DateTime? completedAt,
  }) async {
    final id = const Uuid().v4();
    await into(todoCompletions).insert(
      TodoCompletionsCompanion.insert(
        id: id,
        todoId: todoId,
        occurrenceDue: Value(occurrenceDue),
        completedAt: completedAt ?? AppClock.now(),
      ),
    );
    return id;
  }

  Future<List<TodoCompletion>> todoCompletionsFor(String todoId) {
    return (select(todoCompletions)
          ..where((t) => t.todoId.equals(todoId))
          ..orderBy([(t) => OrderingTerm.desc(t.completedAt)]))
        .get();
  }

  Future<void> deleteTodoCompletion(String id) async {
    await (delete(todoCompletions)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateTodoItem({
    required String id,
    required String title,
    String? notes,
    String notesFormat = 'plain',
    DateTime? startDate,
    DateTime? dueDate,
    int priority = 0,
    String tags = '[]',
    String? recurrenceRule,
    String? recurrenceSpec,
    String? parentId,
    String? projectId,
    DateTime? reminderAt,
  }) async {
    await (update(todoItems)..where((t) => t.id.equals(id))).write(
      TodoItemsCompanion(
        title: Value(title),
        notes: Value(notes),
        notesFormat: Value(notesFormat == 'md1' ? 'md1' : 'plain'),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        priority: Value(priority),
        tags: Value(tags),
        recurrenceRule: Value(recurrenceRule),
        recurrenceSpec: Value(recurrenceSpec),
        parentId: Value(parentId),
        projectId: Value(projectId),
        reminderAt: Value(reminderAt),
      ),
    );
  }

  /// Every task nested beneath [id] through `parent_id`. The query is an
  /// iterative breadth walk so a malformed cycle can never hang it.
  Future<List<TodoItem>> getTodoDescendants(String id) async {
    final all = await select(todoItems).get();
    final children = <String, List<TodoItem>>{};
    for (final item in all) {
      final parent = item.parentId;
      if (parent == null) continue;
      children.putIfAbsent(parent, () => []).add(item);
    }
    final result = <TodoItem>[];
    final seen = <String>{id};
    final queue = <String>[id];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final child in children[current] ?? const <TodoItem>[]) {
        if (!seen.add(child.id)) continue;
        result.add(child);
        queue.add(child.id);
      }
    }
    return result;
  }

  /// True when [candidateParentId] is [id] or sits below it. Used to stop a
  /// drag/edit from making a task its own ancestor.
  Future<bool> wouldCreateTodoCycle(
    String id,
    String? candidateParentId,
  ) async {
    if (candidateParentId == null) return false;
    if (candidateParentId == id) return true;
    final descendants = await getTodoDescendants(id);
    return descendants.any((item) => item.id == candidateParentId);
  }

  // ==================== COMMAND PALETTE SEARCH ====================

  String _likePattern(String query) {
    final escaped = query
        .trim()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    return '%$escaped%';
  }

  Future<List<Event>> searchEvents(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(events)
          ..where(
            (t) =>
                t.title.like(pattern, escapeChar: '\\') |
                t.description.like(pattern, escapeChar: '\\'),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(limit))
        .get();
  }

  Future<List<TodoItem>> searchTodoItems(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(todoItems)
          ..where(
            (t) =>
                t.title.like(pattern, escapeChar: '\\') |
                t.notes.like(pattern, escapeChar: '\\'),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<Attachment>> searchAttachments(String query, {int limit = 40}) {
    final pattern = _likePattern(query);
    return (select(attachments)
          ..where((t) => t.displayName.like(pattern, escapeChar: '\\'))
          ..limit(limit))
        .get();
  }

  Future<List<TodoItem>> todoItemsByIds(Iterable<String> ids) {
    if (ids.isEmpty) return Future.value(const <TodoItem>[]);
    return (select(todoItems)..where((t) => t.id.isIn(ids))).get();
  }

  Future<List<Event>> eventsByIds(Iterable<String> ids) {
    if (ids.isEmpty) return Future.value(const <Event>[]);
    return (select(events)..where((t) => t.id.isIn(ids))).get();
  }

  Future<List<Habit>> searchHabits(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(habits)
          ..where((t) => t.name.like(pattern, escapeChar: '\\'))
          ..limit(limit))
        .get();
  }

  Future<List<Project>> searchProjects(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(projects)
          ..where(
            (t) =>
                t.name.like(pattern, escapeChar: '\\') |
                t.description.like(pattern, escapeChar: '\\'),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<List<DiaryEntry>> searchDiaryEntries(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(diaryEntries)
          ..where((t) => t.content.like(pattern, escapeChar: '\\'))
          ..orderBy([(t) => OrderingTerm.desc(t.date)])
          ..limit(limit))
        .get();
  }

  Future<List<FocusSession>> searchFocusSessions(
    String query, {
    int limit = 20,
  }) {
    final pattern = _likePattern(query);
    return (select(focusSessions)
          ..where(
            (t) =>
                t.durationMinutes.cast<String>().like(
                  pattern,
                  escapeChar: '\\',
                ) |
                t.note.like(pattern, escapeChar: '\\'),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.startTime)])
          ..limit(limit))
        .get();
  }

  /// Emits when data used by the dashboard changes. It lists only the tables
  /// the dashboard reads, so unrelated task or project edits don't recompute it.
  Stream<void> watchDashboardChanges() {
    return customSelect(
      'SELECT 1 AS changed',
      readsFrom: {events, diaryEntries, habits, habitLogs, focusSessions},
    ).watch().map((_) {});
  }

  /// Emits when data used by Insights changes.
  Stream<void> watchInsightsChanges() {
    return customSelect(
      'SELECT 1 AS changed',
      readsFrom: {
        projects,
        diaryEntries,
        habits,
        habitLogs,
        focusSessions,
        progressLogs,
        tasks,
      },
    ).watch().map((_) {});
  }

  // ==================== INSIGHTS & HABIT HELPERS ====================

  /// Length of the habit's current run of consecutive completed days.
  ///
  /// [now] is injectable so tests can freeze the clock; production callers
  /// let it default to the real current time.
  Future<int> habitStreak(String habitId, {DateTime? now}) async {
    final logs =
        await (select(habitLogs)..where(
              (t) => t.habitId.equals(habitId) & t.completed.equals(true),
            ))
            .get();

    if (logs.isEmpty) return 0;

    return DayMath.consecutiveDayStreak(logs.map((l) => l.date), now: now);
  }
}

// ==================== DATABASE CONNECTION ====================
LazyDatabase _openConnection() {
  return LazyDatabase(DatabaseBootstrap.open);
}
