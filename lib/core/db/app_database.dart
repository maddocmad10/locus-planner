import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

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

@DriftDatabase(tables: [
  Events,
  Projects,
  ProgressLogs,
  Tasks,
  DiaryEntries,
  Habits,
  HabitLogs,
  FocusSessions,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 3;

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
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_progress_ts ON progress_logs(timestamp)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_diary_date ON diary_entries(date)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_sessions(start_time)');
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_habit_logs_date ON habit_logs(date)');
  }

  // --- Events ---
  Stream<List<Event>> watchAllEvents() => select(events).watch();
  Stream<List<Event>> watchEventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(events)
          ..where((t) =>
              t.startTime.isBiggerOrEqualValue(start) &
              t.startTime.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }

  Future<List<Event>> eventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(events)
          ..where((t) =>
              t.startTime.isBiggerOrEqualValue(start) &
              t.startTime.isSmallerThanValue(end))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  // --- Projects ---
  Stream<List<Project>> watchProjects() =>
      (select(projects)..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Stream<List<ProgressLog>> watchProgressForProject(String projectId) =>
      (select(progressLogs)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
          .watch();

  Stream<List<Task>> watchTasksForProject(String projectId) =>
      (select(tasks)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .watch();

  Future<int> projectProgressPercent(String projectId) async {
    final logs = await (select(progressLogs)
          ..where((t) => t.projectId.equals(projectId))
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]))
        .get();
    if (logs.isEmpty) return 0;
    final project = await (select(projects)..where((t) => t.id.equals(projectId))).getSingleOrNull();
    final target = project?.targetProgress ?? 100;
    if (target <= 0) return 0;
    return (logs.last.value * 100 ~/ target).clamp(0, 100);
  }

  // --- Diary ---
  Stream<List<DiaryEntry>> watchDiaryEntries() =>
      (select(diaryEntries)..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  Future<DiaryEntry?> entryForDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return (select(diaryEntries)..where((t) => t.date.equals(d))).getSingleOrNull();
  }

  Future<int> diaryStreak() async {
    final entries = await (select(diaryEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
    if (entries.isEmpty) return 0;
    var streak = 0;
    var check = DateTime.now();
    check = DateTime(check.year, check.month, check.day);
    for (final e in entries) {
      final ed = DateTime(e.date.year, e.date.month, e.date.day);
      if (ed == check || ed == check.subtract(const Duration(days: 1))) {
        if (ed == check) {
          streak++;
        } else {
          streak++;
          check = ed;
        }
        check = check.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // --- Habits ---
  Stream<List<Habit>> watchHabits() => select(habits).watch();

  Future<List<HabitLog>> logsForHabitToday(String habitId) {
    final today = _dayStart(DateTime.now());
    return (select(habitLogs)
          ..where((t) => t.habitId.equals(habitId) & t.date.equals(today)))
        .get();
  }

  Future<int> habitWeekProgress(String habitId) async {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final start = _dayStart(weekStart);
    final logs = await (select(habitLogs)
          ..where((t) =>
              t.habitId.equals(habitId) &
              t.date.isBiggerOrEqualValue(start) &
              t.completed.equals(true)))
        .get();
    return logs.length;
  }

  Future<int> habitStreak(String habitId) async {
    final logs = await (select(habitLogs)
          ..where((t) => t.habitId.equals(habitId) & t.completed.equals(true))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
    if (logs.isEmpty) return 0;
    var streak = 0;
    var check = _dayStart(DateTime.now());
    for (final log in logs) {
      final ld = _dayStart(log.date);
      if (ld == check) {
        streak++;
        check = check.subtract(const Duration(days: 1));
      } else if (ld == check.subtract(const Duration(days: 1)) && streak == 0) {
        streak++;
        check = ld.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // --- Focus ---
  Stream<List<FocusSession>> watchFocusSessions() =>
      (select(focusSessions)..orderBy([(t) => OrderingTerm.desc(t.startTime)]))
          .watch();

  Future<int> focusMinutesToday() async {
    final start = _dayStart(DateTime.now());
    final end = start.add(const Duration(days: 1));
    final sessions = await (select(focusSessions)
          ..where((t) =>
              t.startTime.isBiggerOrEqualValue(start) &
              t.startTime.isSmallerThanValue(end)))
        .get();
    return sessions.fold<int>(0, (sum, s) => sum + s.durationMinutes);
  }

  Future<List<FocusSession>> focusSessionsLastDays(int days) async {
    final start = _dayStart(DateTime.now().subtract(Duration(days: days - 1)));
    return (select(focusSessions)
          ..where((t) => t.startTime.isBiggerOrEqualValue(start))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  // --- Settings ---
  Future<String?> getSetting(String key) async {
    final row = await (select(appSettings)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion(key: Value(key), value: Value(value)),
    );
  }

  // --- Insights ---
  Future<Map<String, int>> eventCategoryCounts() async {
    final all = await select(events).get();
    final counts = <String, int>{};
    for (final e in all) {
      counts[e.category] = (counts[e.category] ?? 0) + 1;
    }
    return counts;
  }

  static DateTime _dayStart(DateTime d) =>
      DateTime(d.year, d.month, d.day);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'locus.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
