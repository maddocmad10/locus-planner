// A partial backup must keep the confirm dialog's promise — "existing data in
// other sections will be preserved" — in BOTH directions:
//
//  * a parent-only backup (projects or habits without their child sections)
//    must not destroy child rows whose parents the file never mentions, and
//  * a children-only backup must restore its rows against parents that are
//    already in the database.
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

void main() {
  const jan1 = 1767225600000; // 2026-01-01T00:00:00Z
  final jan1Date = DateTime.fromMillisecondsSinceEpoch(jan1);

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<RestoreReport> restore(Map<String, Object?> backup) =>
      DataExportService(db).restoreFromJson(jsonEncode(backup));

  Future<void> seedCurrentData() async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Old project',
            createdAt: jan1Date,
          ),
        );
    await db
        .into(db.tasks)
        .insert(TasksCompanion.insert(id: 't1', projectId: 'p1', title: 'A'));
    await db
        .into(db.progressLogs)
        .insert(
          ProgressLogsCompanion.insert(
            id: 'pl1',
            projectId: 'p1',
            value: 10,
            timestamp: jan1Date,
          ),
        );
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(id: 'h1', name: 'Read', createdAt: jan1Date),
        );
    await db
        .into(db.habitLogs)
        .insert(HabitLogsCompanion.insert(id: 'hl1', habitId: 'h1', date: jan1Date));
    await db
        .into(db.focusSessions)
        .insert(
          FocusSessionsCompanion.insert(
            id: 'f1',
            startTime: jan1Date,
            durationMinutes: 25,
          ),
        );
    await (db.update(db.focusSessions)..where((t) => t.id.equals('f1')))
        .write(const FocusSessionsCompanion(projectId: Value('p1')));
  }

  test(
    'a projects-only backup keeps tasks, progress logs and focus links',
    () async {
      await seedCurrentData();

      final report = await restore({
        'projects': [
          {'id': 'p1', 'name': 'Renamed', 'createdAt': jan1},
        ],
      });

      // Same parent id in the file: the row is updated in place and the
      // children stay attached.
      expect((await db.select(db.projects).getSingle()).name, 'Renamed');
      expect((await db.select(db.tasks).get()).map((t) => t.id), ['t1']);
      expect((await db.select(db.progressLogs).get()).map((p) => p.id), [
        'pl1',
      ]);
      final session = await db.select(db.focusSessions).getSingle();
      expect(session.projectId, 'p1');
      // Habits are not part of the backup at all: untouched.
      expect((await db.select(db.habitLogs).get()).map((l) => l.id), ['hl1']);
      expect(report.isClean, isTrue);
    },
  );

  test(
    'a projects-only backup preserves the children of unmentioned projects',
    () async {
      await seedCurrentData();

      final report = await restore({
        'projects': [
          {'id': 'p2', 'name': 'New project', 'createdAt': jan1},
        ],
      });

      // p1 is not in the file. Deleting it would destroy the tasks, progress
      // logs and focus links the dialog promised to preserve, so a partial
      // parent import merges: p1 stays and p2 is added.
      expect(
        (await db.select(db.projects).get()).map((p) => p.id),
        containsAll(['p1', 'p2']),
      );
      expect((await db.select(db.tasks).get()).map((t) => t.id), ['t1']);
      expect((await db.select(db.progressLogs).get()).map((p) => p.id), [
        'pl1',
      ]);
      final session = await db.select(db.focusSessions).getSingle();
      expect(session.projectId, 'p1');
      expect(report.isClean, isTrue);
    },
  );

  test('a habits-only backup preserves the logs of unmentioned habits',
      () async {
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(id: 'h1', name: 'Kept', createdAt: jan1Date),
        );
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(id: 'h2', name: 'Gone', createdAt: jan1Date),
        );
    await db
        .into(db.habitLogs)
        .insert(HabitLogsCompanion.insert(id: 'hl1', habitId: 'h1', date: jan1Date));
    await db
        .into(db.habitLogs)
        .insert(HabitLogsCompanion.insert(id: 'hl2', habitId: 'h2', date: jan1Date));

    final report = await restore({
      'habits': [
        {'id': 'h1', 'name': 'Kept', 'createdAt': jan1},
      ],
    });

    // h2 is not in the file; deleting it would destroy hl2, a row in a
    // section the backup never mentions. Merge: both habits and both logs
    // survive, and h1 is refreshed from the file.
    expect(
      (await db.select(db.habits).get()).map((h) => h.id),
      containsAll(['h1', 'h2']),
    );
    expect(
      (await db.select(db.habitLogs).get()).map((l) => l.id),
      containsAll(['hl1', 'hl2']),
    );
    expect(report.isClean, isTrue);
  });

  test('unassigned focus sessions survive a projects-only import', () async {
    await db.into(db.focusSessions).insert(
      FocusSessionsCompanion.insert(
        id: 'f-unassigned',
        startTime: jan1Date,
        durationMinutes: 15,
      ),
    );

    await restore({
      'projects': [
        {'id': 'p2', 'name': 'New project', 'createdAt': jan1},
      ],
    });

    final sessions = await db.select(db.focusSessions).get();
    expect(sessions.map((s) => s.id), contains('f-unassigned'));
    expect(sessions.single.projectId, isNull);
  });

  test('a tasks-only backup restores rows against existing projects', () async {
    await seedCurrentData();

    final report = await restore({
      'tasks': [
        {'id': 't9', 'projectId': 'p1', 'title': 'Imported'},
      ],
    });

    // The parent is not in the file, but it exists in the database.
    expect((await db.select(db.tasks).get()).map((t) => t.id), ['t9']);
    expect((await db.select(db.projects).get()).map((p) => p.id), ['p1']);
    expect((await db.select(db.progressLogs).get()).map((p) => p.id), ['pl1']);
    expect(report.isClean, isTrue);
  });

  test('task rows whose parent exists nowhere are skipped and reported',
      () async {
    await seedCurrentData();

    final report = await restore({
      'tasks': [
        {'id': 't9', 'projectId': 'ghost', 'title': 'Dangling'},
      ],
    });

    expect(await db.select(db.tasks).get(), isEmpty);
    expect(report.skippedRows, 1);
  });

  test('focus sessions from the file keep links to existing projects',
      () async {
    await seedCurrentData();

    final report = await restore({
      'focus_sessions': [
        {
          'id': 'f9',
          'projectId': 'p1',
          'startTime': jan1,
          'durationMinutes': 30,
        },
      ],
    });

    final session = await db.select(db.focusSessions).getSingle();
    expect(session.id, 'f9');
    expect(session.projectId, 'p1');
    expect(report.isClean, isTrue);
  });

  test('a full project-family backup still hard-replaces projects', () async {
    await seedCurrentData();

    final report = await restore({
      'projects': [
        {'id': 'p2', 'name': 'New project', 'createdAt': jan1},
      ],
      'tasks': <Object>[],
      'progress_logs': <Object>[],
      'focus_sessions': <Object>[],
    });

    // Every child section is present, so the projects replace may delete
    // unmentioned parents: p1 goes, and the file's (empty) children win.
    expect((await db.select(db.projects).get()).map((p) => p.id), ['p2']);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.progressLogs).get(), isEmpty);
    expect(report.isClean, isTrue);
  });

  test('habit logs from the file may target habits already in the database',
      () async {
    await seedCurrentData();

    final report = await restore({
      'habit_logs': [
        {'id': 'l9', 'habitId': 'h1', 'date': jan1},
      ],
    });

    expect((await db.select(db.habitLogs).get()).map((l) => l.id), ['l9']);
    expect((await db.select(db.habits).get()).map((h) => h.id), ['h1']);
    expect(report.isClean, isTrue);
  });
}
