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

// ==================== TABLES ====================

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();

  /// Format marker for [description]: `plain` or `md1`. Existing rows default
  /// to plain so an older peer still shows readable text.
  TextColumn get descriptionFormat =>
      text().withDefault(const Constant('plain'))();

  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  BoolColumn get hasReminder => boolean().withDefault(const Constant(false))();
  IntColumn get reminderMinutes => integer().withDefault(const Constant(10))();

  /// Recurrence vocabulary (`daily`, `weekly`, ...); null or `none` means a
  /// one-off event.
  TextColumn get recurrenceRule => text().nullable()();

  /// Date-only event. The UI hides the clock, and reminders treat the start as
  /// all-day rather than a midnight appointment.
  BoolColumn get allDay => boolean().withDefault(const Constant(false))();

  /// Last allowed occurrence start, inclusive. Covers RRULE `UNTIL` and a
  /// `COUNT` converted to an end date. Null means the series does not end.
  DateTimeColumn get recurrenceEnd => dateTime().nullable()();

  /// JSON array of `YYYY-MM-DD` local dates removed from the series (EXDATE).
  TextColumn get recurrenceExceptions =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  IntColumn get targetProgress => integer().withDefault(const Constant(100))();
  @override
  Set<Column> get primaryKey => {id};
}

class ProgressLogs extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  IntColumn get value => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  /// Canonical workflow status. `completed` remains the compatibility flag and
  /// is always derived from this key by the repository.
  TextColumn get statusKey => text().withDefault(const Constant('todo'))();

  /// Optional planned start for the timeline. Date-only intent; the stored
  /// value is normalised to local midnight by the repository.
  DateTimeColumn get startDate => dateTime().nullable()();

  /// Optional deadline.
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// Effort estimate in minutes. Never a calendar booking.
  IntColumn get estimatedMinutes => integer().nullable()();

  /// Same stable vocabulary as the to-do priority: 0 none, 1 low, 2 medium,
  /// 3 high.
  IntColumn get priority => integer().withDefault(const Constant(0))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Per-project display metadata for the fixed workflow statuses.
///
/// The status keys themselves are a closed vocabulary (backlog, todo,
/// in_progress, waiting, done); users can rename, recolour and reorder the
/// columns, but a custom key never becomes part of a synced payload.
@DataClassName('ProjectStatus')
class ProjectStatuses extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  TextColumn get statusKey => text()();
  TextColumn get name => text()();
  TextColumn get colorToken => text().withDefault(const Constant('blue'))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  BoolColumn get isDone => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {projectId, statusKey},
  ];

  @override
  List<String> get customConstraints => ['CHECK (position >= 0)'];
}

/// Project-level checkpoints. A milestone is not a task and never overloads
/// `tasks.project_id`; completion is represented by [completedAt].
class ProjectMilestones extends Table {
  TextColumn get id => text()();
  TextColumn get projectId =>
      text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (position >= 0)'];
}

/// One finish-to-start edge between two project tasks.
class TaskDependencies extends Table {
  TextColumn get id => text()();
  TextColumn get predecessorTaskId =>
      text().customConstraint('REFERENCES tasks(id) ON DELETE CASCADE')();
  TextColumn get successorTaskId =>
      text().customConstraint('REFERENCES tasks(id) ON DELETE CASCADE')();
  TextColumn get dependencyType =>
      text().withDefault(const Constant('finish_to_start'))();
  IntColumn get lagMinutes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {predecessorTaskId, successorTaskId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (predecessor_task_id != successor_task_id)',
    "CHECK (dependency_type IN ('finish_to_start'))",
    'CHECK (lag_minutes BETWEEN 0 AND 10080)',
  ];
}

class DiaryEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime().unique()();
  IntColumn get mood => integer()();
  TextColumn get content => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('🔥'))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get targetPerWeek => integer().withDefault(const Constant(5))();
  @override
  Set<Column> get primaryKey => {id};
}

class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get habitId =>
      text().customConstraint('REFERENCES habits(id) ON DELETE CASCADE')();
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(true))();
  @override
  Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().customConstraint(
    'NULL REFERENCES projects(id) ON DELETE SET NULL',
  )();
  DateTimeColumn get startTime => dateTime()();
  IntColumn get durationMinutes => integer()();
  TextColumn get note => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

// NEW: Global To-Do List Table
class TodoItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();

  /// Long-form details that should travel with the task but not crowd its
  /// one-line title.
  TextColumn get notes => text().nullable()();

  /// Format marker for [notes]: `plain` or `md1`. Existing rows default to
  /// plain so an older peer still shows readable text.
  TextColumn get notesFormat => text().withDefault(const Constant('plain'))();

  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  /// When work may start. A task is scheduled as soon as either this or
  /// [dueDate] is set; with neither it is explicitly unscheduled.
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();

  /// 0 = none, 1 = low, 2 = medium, 3 = high (see `TaskPriority`).
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// JSON array of free-form tag names. Stored as text so a tag set needs no
  /// join table and travels with backups and sync payloads.
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  /// Reuses the planner's recurrence vocabulary (`daily`, `weekly`, ...).
  TextColumn get recurrenceRule => text().nullable()();

  /// The task this one is a subtask of. Deleting a parent removes its subtasks.
  TextColumn get parentId => text().nullable().customConstraint(
    'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  )();

  /// Optional link to a project. Deleting the project unlinks the task rather
  /// than deleting it, because the task also exists independently.
  TextColumn get projectId => text().nullable().customConstraint(
    'NULL REFERENCES projects(id) ON DELETE SET NULL',
  )();

  /// Exact moment to show a reminder. Null means the task has no reminder.
  DateTimeColumn get reminderAt => dateTime().nullable()();

  /// Optional effort estimate used by capacity calculations. This is an
  /// estimate, not a booking: actual calendar time lives in
  /// [TaskScheduleBlocks].
  IntColumn get estimatedMinutes => integer().nullable()();

  /// User-assigned importance, used only by the Eisenhower matrix. It is never
  /// inferred from priority.
  BoolColumn get isImportant => boolean().withDefault(const Constant(false))();

  /// User override for the derived urgency. Null means "use the due-date
  /// window"; true/false pins the task to urgent/not urgent.
  BoolColumn get urgencyOverride => boolean().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Append-only history of completed recurring to-dos. A recurring task advances
/// its due date instead of staying completed, so these rows are the only record
/// that an occurrence was finished.
class TodoCompletions extends Table {
  TextColumn get id => text()();

  TextColumn get todoId => text().customConstraint(
    'NOT NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  )();

  /// Due date of the occurrence that was completed. Null when the task had no
  /// due date (which cannot advance, so no row is normally written).
  DateTimeColumn get occurrenceDue => dateTime().nullable()();

  DateTimeColumn get completedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One planning record per local calendar day. [dayKey] is a `YYYY-MM-DD`
/// string rather than a UTC instant so a plan always means the user's local
/// date, independent of time zone or daylight-saving changes.
class DailyPlans extends Table {
  TextColumn get id => text()();

  TextColumn get dayKey => text().unique()();

  TextColumn get intention => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Links one existing task (a personal to-do or a project checklist task) to
/// one daily plan. Exactly one of [todoItemId] and [projectTaskId] is set;
/// completion state and task data stay on the original task row.
class DailyPlanItems extends Table {
  TextColumn get id => text()();

  TextColumn get planId => text().customConstraint(
    'NOT NULL REFERENCES daily_plans(id) ON DELETE CASCADE',
  )();

  TextColumn get todoItemId => text().nullable().customConstraint(
    'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  )();

  TextColumn get projectTaskId => text().nullable().customConstraint(
    'NULL REFERENCES tasks(id) ON DELETE CASCADE',
  )();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  IntColumn get plannedMinutes => integer().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    '''
    CHECK (
      (todo_item_id IS NOT NULL AND project_task_id IS NULL)
      OR
      (todo_item_id IS NULL AND project_task_id IS NOT NULL)
    )
    ''',
    'CHECK (planned_minutes IS NULL OR planned_minutes > 0)',
  ];
}

/// One planned block of work on the calendar. Blocks are the only place a
/// calendar time allocation for a task is stored; a task's start/due dates keep
/// their availability/deadline meaning and My Day keeps its daily intention
/// meaning.
class TaskScheduleBlocks extends Table {
  TextColumn get id => text()();

  TextColumn get todoItemId => text().nullable().customConstraint(
    'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  )();

  TextColumn get projectTaskId => text().nullable().customConstraint(
    'NULL REFERENCES tasks(id) ON DELETE CASCADE',
  )();

  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();

  /// IANA zone for wall-clock intent. Null means the local zone.
  TextColumn get timezoneId => text().nullable()();

  /// Controlled vocabulary: work, focus, buffer.
  TextColumn get blockKind => text().withDefault(const Constant('work'))();

  TextColumn get note => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    '''
    CHECK (
      (todo_item_id IS NOT NULL AND project_task_id IS NULL)
      OR
      (todo_item_id IS NULL AND project_task_id IS NOT NULL)
    )
    ''',
    'CHECK (end_at > start_at)',
    "CHECK (block_kind IN ('work', 'focus', 'buffer'))",
    'CHECK (sort_order >= 0)',
  ];
}

/// A validated, versioned query definition. The JSON is parsed into an
/// allowlisted AST before it is compiled; raw SQL is never stored or executed.
class SavedFilters extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get entityScope => text()();
  TextColumn get filterJson => text()();
  TextColumn get sortJson => text().withDefault(const Constant('[]'))();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get definitionVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One default planning profile. Kept as a row rather than app settings so it
/// has a sync version and travels with backups like any other user preference.
class PlanningPreferences extends Table {
  TextColumn get id => text()();
  TextColumn get timezoneId => text().nullable()();
  IntColumn get defaultSlotMinutes =>
      integer().withDefault(const Constant(30))();
  IntColumn get weekStartDay => integer().withDefault(const Constant(1))();
  IntColumn get dayStartMinute => integer().withDefault(const Constant(480))();
  IntColumn get dayEndMinute => integer().withDefault(const Constant(1080))();
  IntColumn get bufferMinutes => integer().withDefault(const Constant(10))();

  /// Due-date proximity in days used to derive urgency in the Eisenhower
  /// matrix.
  IntColumn get urgencyWindowDays => integer().withDefault(const Constant(3))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (default_slot_minutes BETWEEN 5 AND 720)',
    'CHECK (week_start_day BETWEEN 1 AND 7)',
    'CHECK (day_start_minute BETWEEN 0 AND 1439)',
    'CHECK (day_end_minute BETWEEN 1 AND 1440)',
    'CHECK (day_end_minute > day_start_minute)',
    'CHECK (buffer_minutes BETWEEN 0 AND 240)',
  ];
}

/// One working interval per row. More than one interval on a weekday is
/// allowed; the capacity service sums them.
class WorkingHours extends Table {
  TextColumn get id => text()();
  IntColumn get weekday => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (weekday BETWEEN 1 AND 7)',
    'CHECK (start_minute BETWEEN 0 AND 1439)',
    'CHECK (end_minute BETWEEN 1 AND 1440)',
    'CHECK (end_minute > start_minute)',
  ];
}

/// Optional recurring breaks inside a working day. They reduce capacity but do
/// not create calendar events.
class WorkingBreaks extends Table {
  TextColumn get id => text()();
  IntColumn get weekday => integer()();
  IntColumn get startMinute => integer()();
  IntColumn get endMinute => integer()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (weekday BETWEEN 1 AND 7)',
    'CHECK (start_minute BETWEEN 0 AND 1439)',
    'CHECK (end_minute BETWEEN 1 AND 1440)',
    'CHECK (end_minute > start_minute)',
  ];
}

/// Attachment metadata for a personal to-do or an event.
///
/// Bytes never live in SQLite: [sha256] identifies content-addressed plaintext
/// and the encrypted file is stored by [AttachmentStore] under the application
/// support directory. Metadata is synced and backed up; the local blob cache in
/// [AttachmentBlobs] is neither.
///
/// Exactly one of [todoId] and [eventId] is set. Two nullable foreign keys with
/// a CHECK keep real `ON DELETE CASCADE` behaviour instead of a polymorphic id.
/// Attachments belong to a recurring event's series, not one occurrence.
@DataClassName('Attachment')
class Attachments extends Table {
  TextColumn get id => text()();

  TextColumn get todoId => text().nullable().customConstraint(
    'NULL REFERENCES todo_items(id) ON DELETE CASCADE',
  )();

  TextColumn get eventId => text().nullable().customConstraint(
    'NULL REFERENCES events(id) ON DELETE CASCADE',
  )();

  /// Controlled vocabulary: `file` or `image`.
  TextColumn get kind => text()();

  /// Sanitized display text only. Never used as a disk path.
  TextColumn get displayName => text()();

  /// Sniffed from magic bytes, not trusted from the extension.
  TextColumn get mimeType => text()();

  IntColumn get sizeBytes => integer()();

  /// Hex digest of the plaintext bytes. The disk name is an HMAC of this value
  /// so the file system does not expose content hashes.
  TextColumn get sha256 => text()();

  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();

  IntColumn get position => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    '''
    CHECK (
      (todo_id IS NOT NULL AND event_id IS NULL)
      OR
      (todo_id IS NULL AND event_id IS NOT NULL)
    )
    ''',
    "CHECK (kind IN ('file', 'image'))",
    'CHECK (size_bytes >= 0)',
    'CHECK (position >= 0)',
  ];
}

/// Device-local cache state for one content hash. Never synced and never part
/// of a logical backup row: a restored backup on another device must fetch or
/// import its own files.
@DataClassName('AttachmentBlob')
class AttachmentBlobs extends Table {
  TextColumn get sha256 => text()();

  IntColumn get sizeBytes => integer()();

  /// Controlled vocabulary: present, missing, downloading, failed.
  TextColumn get state => text().withDefault(const Constant('missing'))();

  BoolColumn get hasThumb => boolean().withDefault(const Constant(false))();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastAccessedAt => dateTime().nullable()();
  DateTimeColumn get orphanedAt => dateTime().nullable()();
  IntColumn get failCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {sha256};

  @override
  List<String> get customConstraints => [
    "CHECK (state IN ('present', 'missing', 'downloading', 'failed'))",
    'CHECK (size_bytes >= 0)',
    'CHECK (fail_count >= 0)',
  ];
}

/// Durable, local queue of mutations waiting to be sent to another device.
/// Rows are inserted by SQLite triggers in the same transaction as the edit.
class SyncOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()(); // upsert | delete
  TextColumn get payload => text()(); // JSON snapshot or tombstone
  TextColumn get deviceId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}

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
  static const lastQuickCheckSettingKey = 'db.last_quick_check';
  static const syncDeviceIdSettingKey = 'sync.device_id';
  static const syncSuppressOutboxSettingKey = 'sync.suppress_outbox';
  static const syncServerPairedClientsSettingKey = 'sync.server.paired_clients';
  static const syncServerEnabledSettingKey = 'sync.server.enabled';
  static const syncEpochSettingKey = 'sync.epoch';
  static const syncOutboxPrunedThroughSettingKey = 'sync.outbox.pruned_through';
  static const syncTlsCertificateSettingKey = 'sync.tls.certificate';
  static const syncTlsPrivateKeySettingKey = 'sync.tls.private_key';
  static const themeModeSettingKey = 'theme_mode';
  static const defaultLandingPageSettingKey = 'navigation.default_page';
  static const eventRemindersSettingKey = 'notifications.event_reminders';
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
    lastQuickCheckSettingKey,
    syncDeviceIdSettingKey,
    syncSuppressOutboxSettingKey,
    syncServerPairedClientsSettingKey,
    syncServerEnabledSettingKey,
    syncEpochSettingKey,
    syncOutboxPrunedThroughSettingKey,
    syncTlsCertificateSettingKey,
    syncTlsPrivateKeySettingKey,
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
    },
    beforeOpen: (details) async {
      // SQLite ignores REFERENCES / ON DELETE CASCADE unless this is switched
      // on for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
      // Keep temporary B-trees in memory so large sorts during migration or
      // reporting cannot spill plaintext rows into an OS temp file.
      await customStatement('PRAGMA temp_store = MEMORY');
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

  static const _nowMsSql =
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
            device_id = (SELECT value FROM app_settings WHERE key = '$syncDeviceIdSettingKey'),
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
            "json_object('id', NEW.id, 'todo_id', NEW.todo_id, 'event_id', NEW.event_id, 'kind', NEW.kind, 'display_name', NEW.display_name, 'mime_type', NEW.mime_type, 'size_bytes', NEW.size_bytes, 'sha256', NEW.sha256, 'width', NEW.width, 'height', NEW.height, 'position', NEW.position, 'created_at', NEW.created_at, 'updated_at', NEW.updated_at)",
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
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '$syncSuppressOutboxSettingKey'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $upsertPayload,
            (SELECT value FROM app_settings WHERE key = '$syncDeviceIdSettingKey'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER ${prefix}_update AFTER UPDATE ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '$syncSuppressOutboxSettingKey'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'NEW.${item.id}', deleted: false)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', NEW.${item.id}, 'upsert', $upsertPayload,
            (SELECT value FROM app_settings WHERE key = '$syncDeviceIdSettingKey'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
      await customStatement('''
        CREATE TRIGGER ${prefix}_delete AFTER DELETE ON ${item.table}
        WHEN COALESCE((SELECT value FROM app_settings WHERE key = '$syncSuppressOutboxSettingKey'), '0') != '1'
        BEGIN
          ${_bumpVersionSql(item.type, 'OLD.${item.id}', deleted: true)}
          INSERT INTO sync_outbox (entity_type, entity_id, operation, payload, device_id, created_at)
          VALUES ('${item.type}', OLD.${item.id}, 'delete', $deletePayload,
            (SELECT value FROM app_settings WHERE key = '$syncDeviceIdSettingKey'), CAST(strftime('%s','now') AS INTEGER) * 1000);
        END;
      ''');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_pending ON sync_outbox(id)',
    );
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
    String? notes,
    String notesFormat = 'plain',
    DateTime? startDate,
    int priority = 0,
    String tags = '[]',
    String? recurrenceRule,
    String? parentId,
    String? projectId,
    DateTime? reminderAt,
  }) async {
    final id = const Uuid().v4();
    await into(todoItems).insert(
      TodoItemsCompanion(
        id: Value(id),
        title: Value(title),
        notes: Value(notes),
        notesFormat: Value(notesFormat == 'md1' ? 'md1' : 'plain'),
        createdAt: Value(AppClock.now()),
        startDate: Value(startDate),
        dueDate: Value(dueDate),
        priority: Value(priority),
        tags: Value(tags),
        recurrenceRule: Value(recurrenceRule),
        parentId: Value(parentId),
        projectId: Value(projectId),
        reminderAt: Value(reminderAt),
      ),
    );
    return id;
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
          ..where((t) => t.title.like(pattern, escapeChar: '\\'))
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
