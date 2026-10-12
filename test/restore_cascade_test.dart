// A partial backup that replaces a parent section must not silently destroy
// child rows the backup never mentioned (foreign-key cascades). The confirm
// dialog promises "existing data in other sections will be preserved" — these
// tests keep that promise true.
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

      // Same parent id survives, so all children stay attached.
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
    'children whose parent the replace removed are skipped, not lost silently',
    () async {
      await seedCurrentData();

      final report = await restore({
        'projects': [
          {'id': 'p2', 'name': 'New project', 'createdAt': jan1},
        ],
      });

      // The old task and progress log pointed at p1, which the replace
      // removed: they cannot survive the foreign key, and they are reported.
      expect(await db.select(db.tasks).get(), isEmpty);
      expect(await db.select(db.progressLogs).get(), isEmpty);
      // The session itself survives; only the dead link is gone.
      final session = await db.select(db.focusSessions).getSingle();
      expect(session.projectId, isNull);
      // Habit data was never part of the backup: untouched.
      expect((await db.select(db.habitLogs).get()).map((l) => l.id), ['hl1']);
      expect(report.skippedRows, 2);
      expect(report.adjustedValues, 1);
    },
  );

  test('a habits-only backup keeps the logs whose habit survives', () async {
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

    expect((await db.select(db.habits).get()).map((h) => h.id), ['h1']);
    expect((await db.select(db.habitLogs).get()).map((l) => l.id), ['hl1']);
    expect(report.skippedRows, 1);
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

}
