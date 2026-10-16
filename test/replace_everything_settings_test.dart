// "Replace everything" empties the user's data that the file lacks, but never
// the app's settings unless the file carries them.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

void main() {
  const jan1 = 1767225600000; // 2026-01-01T00:00:00Z

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.setSetting('theme', 'dark');

    final day = DateTime(2026, 1, 1);
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(id: 'p1', name: 'Alpha', createdAt: day),
        );
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(id: 't1', projectId: 'p1', title: 'task'),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(id: 'e1', title: 'Event', startTime: day),
        );
    await db
        .into(db.habits)
        .insert(HabitsCompanion.insert(id: 'h1', name: 'Read', createdAt: day));
    await db
        .into(db.habitLogs)
        .insert(HabitLogsCompanion.insert(id: 'hl1', habitId: 'h1', date: day));
  });
  tearDown(() => db.close());

  String oldFile(Map<String, Object?> extra) => jsonEncode({
    'projects': [
      {'id': 'p2', 'name': 'Beta', 'createdAt': jan1},
    ],
    ...extra,
  });

  test('missing data is emptied, but settings are kept', () async {
    await DataExportService(
      db,
    ).restoreFromJson(oldFile({}), replaceEverything: true);

    expect((await db.select(db.projects).get()).map((p) => p.id), ['p2']);
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(await db.select(db.events).get(), isEmpty);
    expect(await db.select(db.habits).get(), isEmpty);
    expect(await db.select(db.habitLogs).get(), isEmpty);
    expect(await db.getSetting('theme'), 'dark');
  });

  test('settings in the file are still replaced', () async {
    await db.setSetting('old', '1');

    await DataExportService(db).restoreFromJson(
      oldFile({
        'app_settings': [
          {'key': 'theme', 'value': 'light'},
        ],
      }),
      replaceEverything: true,
    );

    expect(await db.getSetting('theme'), 'light');
    expect(await db.getSetting('old'), isNull);
  });

  test('the plan does not count or replace settings the file lacks', () {
    final plan = BackupImportPlan.parse(oldFile({}), replaceEverything: true);

    expect(plan.sections, isNot(contains('app_settings')));
    expect(plan.counts.containsKey('app_settings'), isFalse);
    expect(plan.untouchedSections, {'app_settings'});
    expect(plan.sections.containsAll(BackupImportPlan.dataSections), isTrue);
  });

  test('without it, the same file leaves the rest alone', () async {
    await DataExportService(db).restoreFromJson(oldFile({}));

    // Merged: nothing deleted, because the file has no project children.
    final projects = await db.select(db.projects).get();
    expect(projects.map((p) => p.id).toSet(), {'p1', 'p2'});
    expect((await db.select(db.tasks).getSingle()).id, 't1');
    expect((await db.select(db.events).getSingle()).id, 'e1');
    expect(await db.getSetting('theme'), 'dark');
  });

  test('it is refused for a current-format file', () async {
    await expectLater(
      DataExportService(db).restoreFromJson(
        oldFile({'format_version': 2}),
        replaceEverything: true,
      ),
      throwsA(isA<FormatException>()),
    );
    expect((await db.select(db.events).getSingle()).id, 'e1');
  });
}
