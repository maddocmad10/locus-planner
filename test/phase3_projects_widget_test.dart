import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/features/projects/data/project_workflow_repository.dart';
import 'package:locus_planner/features/projects/presentation/projects_page.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seed() async {
    final undo = UndoService();
    final projects = ProjectRepository(db, undo);
    final workflow = ProjectWorkflowRepository(db, undo);
    await projects.create(name: 'Launch');
    final project = await db.select(db.projects).getSingle();
    await projects.addTask(projectId: project.id, title: 'First');
    await projects.addTask(projectId: project.id, title: 'Second');
    final first = await (db.select(
      db.tasks,
    )..where((t) => t.title.equals('First'))).getSingle();
    await workflow.moveTaskToStatus(first, 'in_progress');
  }

  testWidgets('list and Kanban show the same tasks and statuses', (
    tester,
  ) async {
    await seed();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ProjectsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsOneWidget);
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();

    expect(find.text('Checklist'), findsWidgets);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    await tester.tap(find.byTooltip('Kanban board'));
    await tester.pumpAndSettle();

    expect(find.text('Backlog (0)'), findsOneWidget);
    expect(find.text('To do (1)'), findsOneWidget);
    expect(find.text('In Progress (1)'), findsOneWidget);
    expect(find.text('Waiting (0)'), findsOneWidget);
    expect(find.text('Done (0)'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    // Unmount explicitly so Drift's stream-close timers run while the test
    // binding is still pumping frames.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 10));
  });
}
