part of 'app_database.dart';

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

  /// Optional user-provided alt text for accessibility.
  TextColumn get altText => text().nullable()();

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
