// Regression tests for the data-layer fixes (backup round-trip, foreign keys,
// addTask ordering, streaks).
//
// Run with:  flutter test test/data_layer_test.dart
//
// These use an in-memory SQLite database, which needs a native sqlite3 library
// on the machine running the tests. On Windows, put sqlite3.dll on PATH (or
// next to the test runner) if `flutter test` can't find it.
import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/auto_backup_service.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/utils/day_math.dart';
import 'package:locus_planner/core/utils/recurrence.dart';
import 'package:locus_planner/features/events/data/event_repository.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/services/notification_service.dart';

T? _presentValue<T>(Value<T> value) => value.present ? value.value : null;

extension HabitsCompanionJson on HabitsCompanion {
  Map<String, dynamic> toJson() => {
        'id': _presentValue(id),
        'name': _presentValue(name),
        'icon': _presentValue(icon),
        'createdAt': _presentValue(createdAt)?.toIso8601String(),
        'targetPerWeek': _presentValue(targetPerWeek),
      };
}

extension HabitLogsCompanionJson on HabitLogsCompanion {
  Map<String, dynamic> toJson() => {
        'id': _presentValue(id),
        'habitId': _presentValue(habitId),
        'date': _presentValue(date)?.toIso8601String(),
        'completed': _presentValue(completed),
      };
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addProject(String id, {String name = 'Project'}) {
    return db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: id,
            name: name,
            createdAt: DateTime(2026, 1, 1),
          ),
        );
  }

  group('schema migration', () {
    test('opens and upgrades a schema-version-4 database', () async {
      final dir = await Directory.systemTemp.createTemp('locus-v4-');
      final path = '${dir.path}${Platform.pathSeparator}locus.db';
      final legacy = sqlite3.open(path);
      legacy.execute('''
        CREATE TABLE events (
          id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, description TEXT,
          start_time INTEGER NOT NULL, end_time INTEGER, category TEXT NOT NULL DEFAULT 'general',
          has_reminder INTEGER NOT NULL DEFAULT 0, reminder_minutes INTEGER NOT NULL DEFAULT 10,
          recurrence_rule TEXT
        );
        CREATE TABLE projects (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, description TEXT, created_at INTEGER NOT NULL,
          target_date INTEGER, target_progress INTEGER NOT NULL DEFAULT 100
        );
        CREATE TABLE progress_logs (
          id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL, value INTEGER NOT NULL,
          note TEXT, timestamp INTEGER NOT NULL
        );
        CREATE TABLE tasks (
          id TEXT NOT NULL PRIMARY KEY, project_id TEXT NOT NULL, title TEXT NOT NULL,
          completed INTEGER NOT NULL DEFAULT 0, sort_order INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE diary_entries (
          id TEXT NOT NULL PRIMARY KEY, date INTEGER NOT NULL UNIQUE, mood INTEGER NOT NULL, content TEXT NOT NULL
        );
        CREATE TABLE habits (
          id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, icon TEXT NOT NULL DEFAULT '🔥',
          created_at INTEGER NOT NULL, target_per_week INTEGER NOT NULL DEFAULT 5
        );
        CREATE TABLE habit_logs (
          id TEXT NOT NULL PRIMARY KEY, habit_id TEXT NOT NULL, date INTEGER NOT NULL,
          completed INTEGER NOT NULL DEFAULT 1
        );
        CREATE TABLE focus_sessions (
          id TEXT NOT NULL PRIMARY KEY, project_id TEXT, start_time INTEGER NOT NULL,
          duration_minutes INTEGER NOT NULL, note TEXT
        );
        CREATE TABLE app_settings (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE todo_items (
          id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL, due_date INTEGER
        );
      ''');
      legacy.execute('PRAGMA user_version = 4');
      legacy.dispose();

      final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
      await migrated.select(migrated.projects).get();
      final version = (await migrated.customSelect('PRAGMA user_version').getSingle()).read<int>('user_version');
      expect(version, 7);
      await migrated.close();
      await dir.delete(recursive: true);
    });
  });

  group('habit log integrity', () {
    test('duplicate habit-day inserts are ignored by the toggle path', () async {
      final today = DayMath.dateOnly(DateTime.now());
      await db.into(db.habits).insert(HabitsCompanion.insert(id: 'h1', name: 'Read', createdAt: today));
      await db.into(db.habitLogs).insert(HabitLogsCompanion.insert(id: 'l1', habitId: 'h1', date: today));
      await db.into(db.habitLogs).insert(
        HabitLogsCompanion.insert(id: 'l2', habitId: 'h1', date: today),
        mode: InsertMode.insertOrIgnore,
      );
      expect(await db.select(db.habitLogs).get(), hasLength(1));
    });

    test('restore dedupes duplicate habit logs and clears transient settings', () async {
      final today = DateTime(2026, 1, 1);
      await db.setSetting('focus.active_session', 'keep-me');
      await db.into(db.habits).insert(HabitsCompanion.insert(id: 'h1', name: 'Read', createdAt: today));
      final service = DataExportService(db);
      final backup = jsonEncode({
        'habits': [HabitsCompanion.insert(id: 'h2', name: 'Write', createdAt: today).toJson()],
        'habit_logs': [
          HabitLogsCompanion.insert(id: 'l1', habitId: 'h2', date: today).toJson(),
          HabitLogsCompanion.insert(id: 'l2', habitId: 'h2', date: today).toJson(),
        ],
      });
      await service.restoreFromJson(backup);
      expect(await db.select(db.habitLogs).get(), hasLength(1));
      expect(await db.getSetting('focus.active_session'), isNull);
    });
  });

  group('addTask', () {
    test('can add more than two tasks and keeps increasing order', () async {
      await addProject('p1');
      for (var i = 1; i <= 5; i++) {
        await db.addTask('p1', 'Task $i');
      }
      final tasks = await (db.select(
        db.tasks,
      )..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();
      expect(tasks.map((t) => t.title), [
        'Task 1',
        'Task 2',
        'Task 3',
        'Task 4',
        'Task 5',
      ]);
      expect(tasks.map((t) => t.sortOrder), [1, 2, 3, 4, 5]);
    });
  });


  group('project repository invariants', () {
    test('repository task creation starts at zero and increments safely', () async {
      await addProject('p1');
      final repository = ProjectRepository(db, UndoService());
      await repository.addTask(projectId: 'p1', title: 'A');
      await repository.addTask(projectId: 'p1', title: 'B');
      final tasks = await (db.select(db.tasks)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();
      expect(tasks.map((t) => t.sortOrder), [1, 2]);
    });

    test('project progress is aggregated in one query stream', () async {
      await addProject('p1');
      await db.addTask('p1', 'A');
      await db.addTask('p1', 'B');
      await db.toggleTask((await db.select(db.tasks).get()).first.id, true);
      final progress = await db.watchProjectProgress().first;
      expect(progress['p1'], 50.0);
    });
  });

  group('backup validation', () {
    test('normalizes imported diary and habit dates to day-only values', () async {
      final service = DataExportService(db);
      await service.restoreFromJson(jsonEncode({
        'diary_entries': [
          {
            'id': 'd1',
            'date': '2026-01-02T18:45:00',
            'mood': 4,
            'content': 'Hello',
          },
        ],
        'habits': [
          {
            'id': 'h1',
            'name': 'Read',
            'createdAt': '2026-01-01T09:00:00',
            'targetPerWeek': 5,
          },
        ],
        'habit_logs': [
          {
            'id': 'l1',
            'habitId': 'h1',
            'date': '2026-01-02T23:59:00',
            'completed': true,
          },
        ],
      }));
      final diary = await db.select(db.diaryEntries).getSingle();
      final log = await db.select(db.habitLogs).getSingle();
      expect(diary.date, DateTime(2026, 1, 2));
      expect(log.date, DateTime(2026, 1, 2));
    });

    test('rejects invalid recurrence and reminder values before replacing data', () async {
      final service = DataExportService(db);
      await db.setSetting('sentinel', 'keep');
      expect(
        () => service.restoreFromJson(jsonEncode({
          'events': [
            {
              'id': 'e1',
              'title': 'Bad',
              'startTime': '2026-01-01T09:00:00',
              'hasReminder': true,
              'reminderMinutes': -1,
              'recurrenceRule': 'banana',
            },
          ],
        })),
        throwsFormatException,
      );
      expect(await db.getSetting('sentinel'), 'keep');
    });
  });

  group('query helpers', () {
    test('completedHabitsToday counts unique completed habits', () async {
      final today = DayMath.dateOnly(DateTime.now());
      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(id: 'h1', name: 'Read', createdAt: today),
          );
      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(id: 'h2', name: 'Walk', createdAt: today),
          );
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(id: 'l1', habitId: 'h1', date: today),
          );
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(id: 'l2', habitId: 'h2', date: today),
          );
      expect(await db.completedHabitsToday(), 2);
    });
  });

  group('foreign keys', () {
    test('foreign key enforcement is switched on', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(row.data.values.first, 1);
    });

    test(
      'deleteProject removes tasks and logs, unlinks focus sessions',
      () async {
        await addProject('p1');
        await addProject('p2');
        await db.addTask('p1', 'a');
        await db.addTask('p2', 'b');
        await db.logProjectProgress('p1', 10, null);
        await db
            .into(db.focusSessions)
            .insert(
              FocusSessionsCompanion.insert(
                id: 's1',
                startTime: DateTime(2026, 1, 2),
                durationMinutes: 25,
                projectId: const Value('p1'),
              ),
            );

        await db.deleteProject('p1');

        expect((await db.select(db.projects).get()).map((p) => p.id), ['p2']);
        expect((await db.select(db.tasks).get()).map((t) => t.title), ['b']);
        expect(await db.select(db.progressLogs).get(), isEmpty);
        final sessions = await db.select(db.focusSessions).get();
        expect(sessions, hasLength(1));
        expect(sessions.single.projectId, isNull);
      },
    );

    test('deleteHabit removes its logs', () async {
      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              name: 'Read',
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: 'l1',
              habitId: 'h1',
              date: DateTime(2026, 1, 2),
            ),
          );

      await db.deleteHabit('h1');

      expect(await db.select(db.habits).get(), isEmpty);
      expect(await db.select(db.habitLogs).get(), isEmpty);
    });
  });

  group('DayMath.consecutiveDayStreak', () {
    final now = DateTime(2026, 10, 5, 14, 30);

    test('empty is zero', () {
      expect(DayMath.consecutiveDayStreak([], now: now), 0);
    });

    test('counts consecutive days ending today', () {
      final days = [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 4),
        DateTime(2026, 10, 3),
      ];
      expect(DayMath.consecutiveDayStreak(days, now: now), 3);
    });

    test('streak still alive if the last entry was yesterday', () {
      final days = [DateTime(2026, 10, 4), DateTime(2026, 10, 3)];
      expect(DayMath.consecutiveDayStreak(days, now: now), 2);
    });

    test('a single missing day ends the streak (no gap tolerance)', () {
      // today, then yesterday missing, then 2 and 3 days ago
      final days = [
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 2),
      ];
      expect(DayMath.consecutiveDayStreak(days, now: now), 1);
    });

    test('last entry two days ago means no streak', () {
      expect(
        DayMath.consecutiveDayStreak([DateTime(2026, 10, 3)], now: now),
        0,
      );
    });

    test('ignores time of day and duplicates', () {
      final days = [
        DateTime(2026, 10, 5, 23, 59),
        DateTime(2026, 10, 5, 1, 0),
        DateTime(2026, 10, 4, 12, 0),
      ];
      expect(DayMath.consecutiveDayStreak(days, now: now), 2);
    });

    test('works across month boundaries and DST-change weekends', () {
      // 2026-11-01 is the US fall-back day; 2026-03-08 is spring-forward.
      expect(
        DayMath.consecutiveDayStreak([
          DateTime(2026, 11, 2),
          DateTime(2026, 11, 1),
          DateTime(2026, 10, 31),
        ], now: DateTime(2026, 11, 2, 9)),
        3,
      );
      expect(
        DayMath.consecutiveDayStreak([
          DateTime(2026, 3, 9),
          DateTime(2026, 3, 8),
          DateTime(2026, 3, 7),
        ], now: DateTime(2026, 3, 9, 9)),
        3,
      );
    });
  });

  group('DayMath helpers', () {
    test('addDays keeps midnight on DST-change days', () {
      for (final d in [DateTime(2026, 3, 9), DateTime(2026, 11, 2)]) {
        final back = DayMath.addDays(d, -1);
        expect(back.hour, 0);
        expect(back.minute, 0);
      }
    });

    test('calendarDaysBetween ignores time of day', () {
      expect(
        DayMath.calendarDaysBetween(
          DateTime(2026, 10, 4, 23, 59),
          DateTime(2026, 10, 5, 0, 1),
        ),
        1,
      );
      expect(
        DayMath.calendarDaysBetween(
          DateTime(2026, 10, 5),
          DateTime(2026, 10, 5, 23),
        ),
        0,
      );
    });

    test('startOfWeek is Monday at midnight', () {
      // 2026-10-05 is a Monday; 2026-10-11 is a Sunday.
      expect(
        DayMath.startOfWeek(DateTime(2026, 10, 11, 15)),
        DateTime(2026, 10, 5),
      );
      expect(
        DayMath.startOfWeek(DateTime(2026, 10, 5, 0, 1)),
        DateTime(2026, 10, 5),
      );
    });
  });

  group('diaryStreak', () {
    test('does not bridge a one-day gap', () async {
      final today = DayMath.dateOnly(DateTime.now());
      for (final offset in [0, 2, 3]) {
        await db
            .into(db.diaryEntries)
            .insert(
              DiaryEntriesCompanion.insert(
                id: 'e$offset',
                date: DayMath.addDays(today, -offset),
                mood: 3,
                content: 'x',
              ),
            );
      }
      expect(await db.diaryStreak(), 1);
    });
  });

  group('backup', () {
    Future<void> seed() async {
      await addProject('p1', name: 'Alpha');
      await db.addTask('p1', 'One');
      await db.addTask('p1', 'Two');
      await db.addTask('p1', 'Three');
      await db.logProjectProgress('p1', 40, 'note');
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'ev1',
              title: 'Meeting',
              startTime: DateTime(2026, 10, 5, 9, 30),
              endTime: Value(DateTime(2026, 10, 5, 10, 30)),
            ),
          );
      await db
          .into(db.habits)
          .insert(
            HabitsCompanion.insert(
              id: 'h1',
              name: 'Read',
              createdAt: DateTime(2026, 1, 1),
            ),
          );
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: 'hl1',
              habitId: 'h1',
              date: DateTime(2026, 10, 5),
            ),
          );
      await db
          .into(db.diaryEntries)
          .insert(
            DiaryEntriesCompanion.insert(
              id: 'd1',
              date: DateTime(2026, 10, 5),
              mood: 4,
              content: 'Good day',
            ),
          );
      await db
          .into(db.focusSessions)
          .insert(
            FocusSessionsCompanion.insert(
              id: 'f1',
              startTime: DateTime(2026, 10, 5, 8),
              durationMinutes: 25,
              projectId: const Value('p1'),
            ),
          );
      await db.addTodoItem('Buy milk', DateTime(2026, 10, 9));
    }

    test('export then import restores identical data', () async {
      await seed();
      final service = DataExportService(db);
      final backup = await service.buildBackupJson();

      // Restore into a fresh database.
      final db2 = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db2.close);
      await DataExportService(db2).restoreFromJson(backup);

      expect(
        await DataExportService(db2).buildBackupJson().then(_withoutExportedAt),
        _withoutExportedAt(backup),
      );

      final events = await db2.select(db2.events).get();
      expect(events.single.startTime, DateTime(2026, 10, 5, 9, 30));
      expect(await db2.select(db2.tasks).get(), hasLength(3));
    });

    test('import also accepts ISO-8601 date strings', () async {
      final json = jsonEncode({
        'projects': [
          {'id': 'p1', 'name': 'A', 'createdAt': '2026-01-01T10:00:00.000'},
        ],
        'tasks': [
          {'id': 't1', 'projectId': 'p1', 'title': 'x'},
        ],
      });
      await DataExportService(db).restoreFromJson(json);
      expect(
        (await db.select(db.projects).getSingle()).createdAt,
        DateTime(2026, 1, 1, 10),
      );
      expect(await db.select(db.tasks).get(), hasLength(1));
    });

    test('a malformed backup leaves existing data untouched', () async {
      await seed();
      final bad = jsonEncode({
        'projects': [
          {'id': 'new', 'name': 'New', 'createdAt': 'not a date'},
        ],
      });

      await expectLater(
        DataExportService(db).restoreFromJson(bad),
        throwsA(isA<FormatException>()),
      );

      expect((await db.select(db.projects).get()).single.id, 'p1');
      expect(await db.select(db.tasks).get(), hasLength(3));
    });

    test(
      'rows whose parent is missing are dropped instead of failing',
      () async {
        final json = jsonEncode({
          'projects': [
            {'id': 'p1', 'name': 'A', 'createdAt': 1767225600000},
          ],
          'tasks': [
            {'id': 't1', 'projectId': 'p1', 'title': 'keep'},
            {'id': 't2', 'projectId': 'gone', 'title': 'orphan'},
          ],
          'focus_sessions': [
            {
              'id': 'f1',
              'projectId': 'gone',
              'startTime': 1767225600000,
              'durationMinutes': 25,
            },
          ],
        });
        await DataExportService(db).restoreFromJson(json);

        expect((await db.select(db.tasks).get()).map((t) => t.id), ['t1']);
        final session = await db.select(db.focusSessions).getSingle();
        expect(session.projectId, isNull);
      },
    );

    group('app settings and habit integrity', () {
      test('app settings round-trip through the database', () async {
        await db.setSetting('example', 'value');
        expect(await db.getSetting('example'), 'value');
        await db.setSetting('example', 'updated');
        expect(await db.getSetting('example'), 'updated');
        await db.deleteSetting('example');
        expect(await db.getSetting('example'), isNull);
      });

      test('habit logs allow only one completion per habit per day', () async {
        final day = DateTime(2026, 10, 5);
        await db
            .into(db.habits)
            .insert(
              HabitsCompanion.insert(
                id: 'unique-habit',
                name: 'Read',
                createdAt: day,
              ),
            );
        await db
            .into(db.habitLogs)
            .insert(
              HabitLogsCompanion.insert(
                id: 'log-1',
                habitId: 'unique-habit',
                date: day,
              ),
            );
        expect(
          () => db
              .into(db.habitLogs)
              .insert(
                HabitLogsCompanion.insert(
                  id: 'log-2',
                  habitId: 'unique-habit',
                  date: day,
                ),
              ),
          throwsA(anything),
        );
      });
    });
  });

  group('backup compatibility', () {
    test('clamps legacy progress values and skips duplicate normalized diary rows', () async {
      await DataExportService(db).restoreFromJson(jsonEncode({
        'projects': [
          {'id': 'p1', 'name': 'Project', 'createdAt': '2026-01-01T09:00:00', 'targetProgress': 140},
        ],
        'progress_logs': [
          {'id': 'pl1', 'projectId': 'p1', 'value': 130, 'timestamp': '2026-01-01T10:00:00'},
        ],
        'diary_entries': [
          {'id': 'd1', 'date': '2026-01-02T08:00:00', 'mood': 4, 'content': 'first'},
          {'id': 'd2', 'date': '2026-01-02T18:00:00', 'mood': 5, 'content': 'duplicate'},
        ],
      }));

      expect((await db.select(db.projects).getSingle()).targetProgress, 100);
      expect((await db.select(db.progressLogs).getSingle()).value, 100);
      expect(await db.select(db.diaryEntries).get(), hasLength(1));
    });

    test('automatic backup honors the 24-hour guard', () async {
      final now = DateTime.now();
      await db.setSetting('backup.last_auto', now.toIso8601String());
      await AutoBackupService(db, DataExportService(db)).runIfDue();
      final stored = DateTime.tryParse(await db.getSetting('backup.last_auto') ?? '');
      expect(stored, now);
    });

    test('transient settings are excluded from export and import', () async {
      await db.setSetting('focus.active_session', 'stale');
      await db.setSetting('backup.last_auto', '2026-01-01T00:00:00');
      await db.setSetting('keep', 'yes');

      final backup = await DataExportService(db).buildBackupJson();
      expect(backup, isNot(contains('focus.active_session')));
      expect(backup, isNot(contains('backup.last_auto')));

      await DataExportService(db).restoreFromJson(jsonEncode({
        'app_settings': [
          {'key': 'focus.active_session', 'value': 'resurrect'},
          {'key': 'backup.last_auto', 'value': 'resurrect'},
          {'key': 'keep', 'value': 'restored'},
        ],
      }));
      expect(await db.getSetting('focus.active_session'), isNull);
      expect(await db.getSetting('backup.last_auto'), isNull);
      expect(await db.getSetting('keep'), 'restored');
    });
  });

  group('query helpers', () {
    test('command search treats percent and underscore as literal characters', () async {
      await db.into(db.todoItems).insert(
        TodoItemsCompanion.insert(
          id: 'literal',
          title: '100%_done',
          createdAt: DateTime.now(),
        ),
      );
      await db.into(db.todoItems).insert(
        TodoItemsCompanion.insert(
          id: 'other',
          title: '100x_done',
          createdAt: DateTime.now(),
        ),
      );

      final matches = await db.searchTodoItems('%_');
      expect(matches.map((item) => item.id), ['literal']);
    });

    test('focus search uses typed Drift date decoding', () async {
      await db.into(db.focusSessions).insert(
        FocusSessionsCompanion.insert(
          id: 'focus1',
          startTime: DateTime(2026, 10, 5, 9),
          durationMinutes: 25,
          note: const Value('deep work'),
        ),
      );
      final matches = await db.searchFocusSessions('25');
      expect(matches.single.startTime, DateTime(2026, 10, 5, 9));
    });
  });

  group('recurring events on a day', () {
    test('weekly event stored last week is counted today', () async {
      final today = DateTime(2026, 10, 5, 15);
      final storedStart = DateTime(2026, 9, 28, 9, 30);
      await db.into(db.events).insert(
        EventsCompanion(
          id: const Value('standup'),
          title: const Value('Standup'),
          startTime: Value(storedStart),
          recurrenceRule: const Value(Recurrence.weekly),
        ),
      );
      await db.into(db.events).insert(
        EventsCompanion(
          id: const Value('once'),
          title: const Value('One-off'),
          startTime: Value(DateTime(2026, 10, 6, 9)),
        ),
      );

      final items = await EventRepository(
        db,
        NotificationService(),
        UndoService(),
      ).watchForDay(today).first;

      expect(items, hasLength(1));
      expect(items.single.event.id, 'standup');
      expect(items.single.event.startTime, storedStart);
      expect(items.single.start, DateTime(2026, 10, 5, 9, 30));
    });
  });
}

String _withoutExportedAt(String json) {
  final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
  map.remove('exported_at');
  return jsonEncode(map);
}
