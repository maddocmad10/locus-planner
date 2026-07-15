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

@DriftDatabase(tables: [Events, Projects, ProgressLogs, Tasks, DiaryEntries, Habits, HabitLogs, FocusSessions, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  @override int get schemaVersion => 3;
  @override MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async { await m.createAll(); await _createIndexes(); },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) { await m.createTable(habits); await m.createTable(habitLogs); await m.createTable(focusSessions); }
      if (from < 3) { await m.addColumn(events, events.recurrenceRule); await m.addColumn(projects, projects.targetProgress); await m.createTable(tasks); await m.createTable(appSettings); await _createIndexes(); }
    },
  );
  Future<void> _createIndexes() async {
    await customStatement('CREATE INDEX IF NOT EXISTS idx_events_start ON events(start_time)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_progress_ts ON progress_logs(timestamp)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_diary_date ON diary_entries(date)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_focus_start ON focus_sessions(start_time)');
    await customStatement('CREATE INDEX IF NOT EXISTS idx_habit_logs_date ON habit_logs(date)');
  }
  Stream<List<Event>> watchAllEvents() => select(events).watch();
  Stream<List<Event>> watchEventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(events)..where((t) => t.startTime.isBiggerOrEqualValue(start) & t.startTime.isSmallerThanValue(end))..orderBy([(t) => OrderingTerm.asc(t.startTime)])).watch();
  }
  Stream<List<Project>> watchProjects() => (select(projects)..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).watch();
  Stream<List<ProgressLog>> watchProgressForProject(String projectId) => (select(progressLogs)..where((t) => t.projectId.equals(projectId))..orderBy([(t) => OrderingTerm.asc(t.timestamp)])).watch();
  Stream<List<Task>> watchTasksForProject(String projectId) => (select(tasks)..where((t) => t.projectId.equals(projectId))..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).watch();
  Stream<List<DiaryEntry>> watchDiaryEntries() => (select(diaryEntries)..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  Stream<List<Habit>> watchHabits() => select(habits).watch();
  Stream<List<FocusSession>> watchFocusSessions() => (select(focusSessions)..orderBy([(t) => OrderingTerm.desc(t.startTime)])).watch();

  Future<List<HabitLog>> logsForHabitToday(String habitId) {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return (select(habitLogs)..where((t) => t.habitId.equals(habitId) & t.date.equals(today))).get();
  }
  Future<int> focusMinutesToday() async {
    final start = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final end = start.add(const Duration(days: 1));
    final sessions = await (select(focusSessions)..where((t) => t.startTime.isBiggerOrEqualValue(start) & t.startTime.isSmallerThanValue(end))).get();
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
      } else { break; }
    }
    return streak;
  }
  Future<int> projectProgressPercent(String projectId) async {
    final logs = await (select(progressLogs)..where((t) => t.projectId.equals(projectId))..orderBy([(t) => OrderingTerm.desc(t.timestamp)])).get();
    if (logs.isEmpty) return 0;
    final project = await (select(projects)..where((t) => t.id.equals(projectId))).getSingleOrNull();
    final target = project?.targetProgress ?? 100;
    if (target <= 0) return 0;
    return (logs.first.value * 100 ~/ target).clamp(0, 100);
  }
  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'locus.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
