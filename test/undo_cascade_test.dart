
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('deleting a project removes dependent rows', () async {
    await db.into(db.projects).insert(
      ProjectsCompanion.insert(
        id: 'p1',
        name: 'Project',
        createdAt: DateTime(2026),
      ),
    );

    await db.into(db.tasks).insert(
      TasksCompanion.insert(
        id: 't1',
        projectId: 'p1',
        title: 'Task',
      ),
    );

    await (db.delete(db.projects)
          ..where((p) => p.id.equals('p1')))
        .go();

    expect(await db.select(db.tasks).get(), isEmpty);
  });
}
