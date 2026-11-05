import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/features/projects/presentation/project_timeline.dart';

Task task({
  required String id,
  required String title,
  DateTime? start,
  DateTime? due,
  String status = 'todo',
  bool completed = false,
  int priority = 0,
}) {
  return Task(
    id: id,
    projectId: 'p1',
    title: title,
    completed: completed,
    statusKey: status,
    startDate: start,
    dueDate: due,
    estimatedMinutes: null,
    priority: priority,
    sortOrder: 0,
  );
}

ProjectMilestone milestone({
  required String id,
  required String title,
  DateTime? target,
  DateTime? completedAt,
}) {
  return ProjectMilestone(
    id: id,
    projectId: 'p1',
    title: title,
    targetDate: target,
    completedAt: completedAt,
    position: 0,
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  );
}

void main() {
  testWidgets(
    'timeline shows scheduled, overdue, milestone and unscheduled rows',
    (tester) async {
      Task? openedTask;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProjectTimeline(
                today: DateTime(2026, 5, 20),
                tasks: [
                  task(
                    id: 't1',
                    title: 'Scheduled',
                    start: DateTime(2026, 5, 20),
                    due: DateTime(2026, 5, 22),
                  ),
                  task(
                    id: 't2',
                    title: 'Overdue',
                    due: DateTime(2026, 5, 10),
                    status: 'in_progress',
                    priority: 3,
                  ),
                  task(id: 't3', title: 'Unscheduled'),
                ],
                milestones: [
                  milestone(
                    id: 'm1',
                    title: 'Beta',
                    target: DateTime(2026, 5, 25),
                  ),
                ],
                dependencies: [
                  TaskDependency(
                    id: 'd1',
                    predecessorTaskId: 't1',
                    successorTaskId: 't2',
                    dependencyType: 'finish_to_start',
                    lagMinutes: 0,
                    createdAt: DateTime(2026, 5, 1),
                    updatedAt: DateTime(2026, 5, 1),
                  ),
                ],
                statuses: const [],
                onOpenTask: (task) => openedTask = task,
                onOpenMilestone: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Scheduled'), findsWidgets);
      expect(find.text('Overdue'), findsWidgets);
      expect(find.text('Beta'), findsWidgets);
      expect(find.text('Unscheduled'), findsWidgets);

      await tester.tap(find.byType(ActionChip));
      expect(openedTask?.id, 't3');

      await tester.tap(find.text('Day'));
      await tester.pump();
      expect(find.text('Day'), findsOneWidget);

      await tester.tap(find.text('Scheduled').last);
      expect(openedTask?.id, 't1');
    },
  );
}
