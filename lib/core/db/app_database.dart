import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../utils/day_math.dart';

part 'app_database.g.dart';

// ==================== TABLES ====================

class Events extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime().nullable()();
  TextColumn get category => text().withDefault(const Constant('general'))();
  BoolColumn get hasReminder => boolean().withDefault(const Constant(false))();
  IntColumn get reminderMinutes => integer().withDefault(const Constant(10))();
  TextColumn get recurrenceRule => text().nullable()();
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
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
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
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  @override
  Set<Column> get primaryKey => {id};
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Settings rows that describe this machine's current state, not the user's
  /// data. They are left out of backups and never replaced by an import.
  static const focusSessionSettingKey = 'focus.active_session';
  static const lastAutoBackupSettingKey = 'backup.last_auto';
  static const transientSettingKeys = <String>[
    focusSessionSettingKey,
    lastAutoBackupSettingKey,
  ];

  static bool isTransientSetting(String key) =>
      transientSettingKeys.contains(key);

  /// For tests: pass `NativeDatabase.memory()`.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes();
      await _createIntegrityIndexes();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(habits);
        await m.createTable(habitLogs);
        await m.createTable(focusSessions);
      }
      if (from < 3) {
        await m.addColumn(events, events.recurrenceRule);
        await m.addColumn(projects, projects.targetProgress);
        await m.createTable(tasks);
        await m.createTable(appSettings);
        await _createIndexes();
      }
      if (from < 4) {
        await m.createTable(todoItems);
      }
      if (from < 5) {
        // Foreign keys used to be unenforced, so deleting a project or habit
        // left orphaned children behind. Clean them up before enforcement.
        await _removeOrphans();
      }
      if (from < 6) {
        await _createIndexes();
      }
      if (from < 7) {
        // Prevent multiple completion records for the same habit on the same day.
        // Older databases may already contain duplicates, so keep the earliest row.
        await customStatement(
          'DELETE FROM habit_logs '
          'WHERE rowid NOT IN (SELECT MIN(rowid) FROM habit_logs GROUP BY habit_id, date)',
        );
        await _createIntegrityIndexes();
      }
    },
    beforeOpen: (details) async {
      // SQLite ignores REFERENCES / ON DELETE CASCADE unless this is switched
      // on for every connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

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

  // ==================== APP SETTINGS ====================

  Future<String?> getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
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

  Stream<List<Event>> watchEventsForDay(DateTime day) {
    final start = DayMath.dateOnly(day);
    final end = DayMath.addDays(start, 1);
    return (select(events)
          ..where(
            (t) =>
                t.startTime.isBiggerOrEqualValue(start) &
                t.startTime.isSmallerThanValue(end),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

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
      DayMath.dateOnly(DateTime.now()),
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
    return (select(habitLogs)
          ..where(
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
    final today = DayMath.dateOnly(DateTime.now());
    return (select(
      habitLogs,
    )..where((t) => t.habitId.equals(habitId) & t.date.equals(today))).get();
  }

  Future<int> completedHabitsToday() async {
    final today = DayMath.dateOnly(DateTime.now());
    final rows = await (select(
      habitLogs,
    )..where((t) => t.date.equals(today) & t.completed.equals(true))).get();
    return rows.map((row) => row.habitId).toSet().length;
  }

  Future<int> focusMinutesToday() async {
    final start = DayMath.dateOnly(DateTime.now());
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

  Future<void> toggleTask(String taskId, bool completed) async {
    await (update(tasks)..where((t) => t.id.equals(taskId))).write(
      TasksCompanion(completed: Value(completed)),
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
        timestamp: Value(DateTime.now()),
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
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
          .watch();

  Future<void> addTodoItem(String title, DateTime? dueDate) async {
    await into(todoItems).insert(
      TodoItemsCompanion(
        id: Value(const Uuid().v4()),
        title: Value(title),
        createdAt: Value(DateTime.now()),
        dueDate: Value(dueDate),
      ),
    );
  }

  Future<void> toggleTodoItem(String id, bool completed) async {
    await (update(todoItems)..where((t) => t.id.equals(id))).write(
      TodoItemsCompanion(completed: Value(completed)),
    );
  }

  Future<void> deleteTodoItem(String id) async {
    await (delete(todoItems)..where((t) => t.id.equals(id))).go();
  }

  // ==================== COMMAND PALETTE SEARCH ====================

  String _likePattern(String query) {
    final escaped = query.trim()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    return '%$escaped%';
  }

  Future<List<Event>> searchEvents(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(events)
          ..where((t) => t.title.like(pattern, escapeChar: '\\') | t.description.like(pattern, escapeChar: '\\'))
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
          ..where((t) => t.name.like(pattern, escapeChar: '\\') | t.description.like(pattern, escapeChar: '\\'))
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

  Future<List<FocusSession>> searchFocusSessions(String query, {int limit = 20}) {
    final pattern = _likePattern(query);
    return (select(focusSessions)
          ..where(
            (t) =>
                t.durationMinutes.cast<String>().like(pattern, escapeChar: '\\') |
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

  Future<List<FocusSession>> focusSessionsLastDays(int days) async {
    final dayStart = DayMath.addDays(
      DayMath.dateOnly(DateTime.now()),
      -(days - 1),
    );
    return (select(focusSessions)
          ..where((t) => t.startTime.isBiggerOrEqualValue(dayStart))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  Future<Map<String, int>> eventCategoryCounts() async {
    final allEvents = await select(events).get();
    final map = <String, int>{};
    for (final e in allEvents) {
      map[e.category] = (map[e.category] ?? 0) + 1;
    }
    return map;
  }

  Future<int> habitWeekProgress(String habitId) async {
    final weekStart = DayMath.startOfWeek(DateTime.now());
    final weekEnd = DayMath.addDays(weekStart, 7);

    final logs =
        await (select(habitLogs)..where(
              (t) =>
                  t.habitId.equals(habitId) &
                  t.date.isBiggerOrEqualValue(weekStart) &
                  t.date.isSmallerThanValue(weekEnd) &
                  t.completed.equals(true),
            ))
            .get();
    return logs.length;
  }

  Future<int> habitStreak(String habitId) async {
    final logs =
        await (select(habitLogs)..where(
              (t) => t.habitId.equals(habitId) & t.completed.equals(true),
            ))
            .get();

    if (logs.isEmpty) return 0;

    return DayMath.consecutiveDayStreak(logs.map((l) => l.date));
  }
}

// ==================== DATABASE CONNECTION ====================
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await _resolveDatabaseFile();
    return NativeDatabase.createInBackground(file);
  });
}

/// The database used to live in Documents, which Windows often redirects into
/// OneDrive; syncing a live SQLite file can lock or corrupt it. It now lives in
/// the application-support folder. An existing database is *copied* across
/// once (via a temp file) and the old file is left untouched as a backup. If
/// anything goes wrong we keep using the old location.
Future<File> _resolveDatabaseFile() async {
  const fileName = 'locus_planner.db';
  final legacy = File(
    p.join((await getApplicationDocumentsDirectory()).path, fileName),
  );
  try {
    final supportDir = await getApplicationSupportDirectory();
    await supportDir.create(recursive: true);
    final target = File(p.join(supportDir.path, fileName));
    if (!await target.exists() && await legacy.exists()) {
      final temp = await legacy.copy('${target.path}.tmp');
      await temp.rename(target.path);
    }
    return target;
  } catch (_) {
    return legacy;
  }
}
