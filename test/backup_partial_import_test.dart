import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('children-only backup preserves existing parent records', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Existing',
            createdAt: DateTime(2026),
          ),
        );

    await DataExportService(db).restoreFromJson(
      jsonEncode({
        'tasks': [
          {'id': 't1', 'projectId': 'p1', 'title': 'Restored task'},
        ],
      }),
    );

    final projects = await db.select(db.projects).get();
    final tasks = await db.select(db.tasks).get();

    expect(projects, isNotEmpty);
    expect(projects.any((project) => project.id == 'p1'), isTrue);
    expect(tasks, isNotEmpty);
    expect(tasks.any((task) => task.id == 't1'), isTrue);
  });

  test('empty backup is rejected before restore', () async {
    await expectLater(
      DataExportService(db).restoreFromJson(jsonEncode({})),
      throwsA(isA<FormatException>()),
    );
  });
}
