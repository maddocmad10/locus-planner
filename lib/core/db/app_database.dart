import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
  @override Set<Column> get primaryKey => {id};
}

class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get targetDate => dateTime().nullable()();
  IntColumn get targetProgress => integer().withDefault(const Constant(100))();
  @override Set<Column> get primaryKey => {id};
}

class ProgressLogs extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  IntColumn get value => integer()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().customConstraint('REFERENCES projects(id) ON DELETE CASCADE')();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  @override Set<Column> get primaryKey => {id};
}

class DiaryEntries extends Table {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime().unique()();
  IntColumn get mood => integer()();
  TextColumn get content => text()();
  @override Set<Column> get primaryKey => {id};
}

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text().withDefault(const Constant('🔥'))();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get targetPerWeek => integer().withDefault(const Constant(5))();
  @override Set<Column> get primaryKey => {id};
}

class HabitLogs extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text().customConstraint('REFERENCES habits(id) ON DELETE CASCADE')();
  DateTimeColumn get date => dateTime()();
  BoolColumn get completed => boolean().withDefault(const Constant(true))();
  @override Set<Column> get primaryKey => {id};
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().nullable().customConstraint('NULL REFERENCES projects(id) ON DELETE SET NULL')();
  DateTimeColumn get startTime => dateTime()();
  IntColumn get durationMinutes => integer()();
  TextColumn get note => text().nullable()();
  @override Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override Set<Column> get primaryKey => {key};
}

// NEW: Global To-Do List Table
class TodoItems extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  @override Set<Column> get primaryKey => {id};
}

// ==================== DATABASE ====================

@DriftDatabase(tables: [
  Events, Projects, ProgressLogs, Tasks, DiaryEntries,
  Habits, HabitLogs, FocusSessions, AppSettings, TodoItems
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createIndexes();
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
    },
  );

  Future<void> _createIndexes() async {
    await customStatement('CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_progress_ts ON progress_logs(timestamp)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_diary_date ON diary_entries(date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_sessions(start_time)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_habit_logs_date ON habit_logs(date)');
  }

  // ==================== EXISTING METHODS ====================
  Stream<List<Event>> watchAllEvents() => select(events).watch();

  Stream<List<Event>> watchEventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(events)
          ..where((t) => t.startTime.isBiggerOrEqualValue(start) & t.startTime.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

  Stream<List<Project>> watchProjects() =>
      (select(projects)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();

  Stream<List<ProgressLog>> watchProgressForProject(String projectId) =>
      (select(progressLogs)..where((t) => t.projectId.equals(projectId))
        ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).watch();

  Stream<List<Task>> watchTasksForProject(String projectId) =>
      (select(tasks)..where((t) => t.projectId.equals(projectId))
        ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();

  Stream<List<DiaryEntry>> watchDiaryEntries() =>
      (select(diaryEntries)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();

  Stream<List<Habit>> watchHabits() => select(habits).watch();

  Stream<List<FocusSession>> watchFocusSessions() =>
      (select(focusSessions)..orderBy([(t) => OrderingTerm.desc(t.startTime)])).watch();

  Future<List<HabitLog>> logsForHabitToday(String habitId) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return (select(habitLogs)..where((t) => t.habitId.equals(habitId) & t.date.equals(today))).get();
  }

  Future<int> focusMinutesToday() async {
    final start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final end = start.add(const Duration(days: 1));
    final sessions = await (select(focusSessions)
          ..where((t) => t.startTime.isBiggerOrEqualValue(start) & t.startTime.isSmallerThanValue(end)))
        .get();
    return sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);
  }

  Future<DiaryEntry?> entryForDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return (select(diaryEntries)..where((t) => t.date.equals(d))).getSingleOrNull();
  }

  Future<int> diaryStreak() async {
    final entries = await (select(diaryEntries)..orderBy([(t) => OrderingTerm.desc(t.date)])).get();
    if (entries.isEmpty) return 0;
    var streak = 0;
    var check = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    for (final e in entries) {
      final ed = DateTime(e.date.year, e.date.month, e.date.day);
      if (ed == check || ed == check.subtract(const Duration(days: 1))) {
        streak++;
        check = ed.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  Future<double> projectProgressPercent(String projectId) async {
    final taskList = await (select(tasks)..where((t) => t.projectId.equals(projectId))).get();
    if (taskList.isEmpty) return 0.0;
    final completedCount = taskList.where((t) => t.completed).length;
    return (completedCount / taskList.length) * 100;
  }
  
    // ==================== PROJECT HELPER METHODS ====================
  Future<void> deleteProject(String projectId) async {
    await (delete(projects)..where((t) => t.id.equals(projectId))).go();
  }

  Future<void> addTask(String projectId, String title) async {
    final maxOrder = await (select(tasks)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.sortOrder)]))
        .getSingleOrNull();

    final newOrder = (maxOrder?.sortOrder ?? 0) + 1;

    await into(tasks).insert(TasksCompanion(
      id: Value(Uuid().v4()),
      projectId: Value(projectId),
      title: Value(title),
      sortOrder: Value(newOrder),
    ));
  }

  Future<void> toggleTask(String taskId, bool completed) async {
    await (update(tasks)..where((t) => t.id.equals(taskId)))
        .write(TasksCompanion(completed: Value(completed)));
  }

  Future<void> logProjectProgress(String projectId, int value, String? note) async {
    await into(progressLogs).insert(ProgressLogsCompanion(
      id: Value(Uuid().v4()),
      projectId: Value(projectId),
      value: Value(value),
      note: Value(note),
      timestamp: Value(DateTime.now()),
    ));
  }

  Future<List<ProgressLog>> getProgressLogs(String projectId) async {
    return (select(progressLogs)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
  }
  
  // ==================== TODO LIST METHODS ====================
  Stream<List<TodoItem>> watchAllTodoItems() =>
      (select(todoItems)
            ..orderBy([
              (t) => OrderingTerm.asc(t.completed),
              (t) => OrderingTerm.desc(t.createdAt)
            ]))
          .watch();

  Future<void> addTodoItem(String title, DateTime? dueDate) async {
    await into(todoItems).insert(TodoItemsCompanion(
      id: Value(Uuid().v4()),
      title: Value(title),
      createdAt: Value(DateTime.now()),
      dueDate: Value(dueDate),
    ));
  }

  Future<void> toggleTodoItem(String id, bool completed) async {
    await (update(todoItems)..where((t) => t.id.equals(id)))
        .write(TodoItemsCompanion(completed: Value(completed)));
  }

  Future<void> deleteTodoItem(String id) async {
    await (delete(todoItems)..where((t) => t.id.equals(id))).go();
  }

  // ==================== INSIGHTS & HABIT HELPERS ====================

  Future<List<FocusSession>> focusSessionsLastDays(int days) async {
    final start = DateTime.now().subtract(Duration(days: days - 1));
    final dayStart = DateTime(start.year, start.month, start.day);
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
    final now = DateTime.now();
    final weekStart = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));

    final logs = await (select(habitLogs)
          ..where((t) =>
              t.habitId.equals(habitId) &
              t.date.isBiggerOrEqualValue(weekStart) &
              t.date.isSmallerThanValue(weekEnd) &
              t.completed.equals(true)))
        .get();
    return logs.length;
  }

  Future<int> habitStreak(String habitId) async {
    final logs = await (select(habitLogs)
          ..where((t) => t.habitId.equals(habitId) & t.completed.equals(true)))
        .get();

    if (logs.isEmpty) return 0;

    final dates = logs
        .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    var streak = 0;
    var expected = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    if (!dates.contains(expected)) {
      expected = expected.subtract(const Duration(days: 1));
    }

    for (final d in dates) {
      if (d == expected) {
        streak++;
        expected = expected.subtract(const Duration(days: 1));
      } else if (d.isBefore(expected)) {
        break;
      }
    }
    return streak;
  }
}

// ==================== DATABASE CONNECTION ====================
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'locus_planner.db'));
    return NativeDatabase.createInBackground(file);
  });
}
