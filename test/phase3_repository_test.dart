import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/domain/project_status.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/core/utils/sync_ids.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/features/projects/data/project_workflow_repository.dart';

void main() {
  late AppDatabase db;
  late UndoService undo;
  late ProjectRepository projects;
  late ProjectWorkflowRepository workflow;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    undo = UndoService();
    projects = ProjectRepository(db, undo);
    workflow = ProjectWorkflowRepository(db, undo);
  });

  tearDown(() async {
    undo.dispose();
    await db.close();
  });

  Future<Project> createProject(String name) async {
    await projects.create(name: name);
    return (db.select(
      db.projects,
    )..where((p) => p.name.equals(name))).getSingle();
  }

  Future<Task> addTask(String projectId, String title) async {
    await projects.addTask(projectId: projectId, title: title);
    return (db.select(
      db.tasks,
    )..where((t) => t.title.equals(title))).getSingle();
  }

  test('a new project seeds the five canonical statuses once', () async {
    final project = await createProject('Launch');

    final statuses = await workflow.loadStatuses(project.id);
    expect(statuses.map((status) => status.statusKey), [
      'backlog',
      'todo',
      'in_progress',
      'waiting',
      'done',
    ]);
    expect(statuses.map((status) => status.position), [0, 1, 2, 3, 4]);
    expect(statuses.last.isDone, isTrue);
    for (final status in statuses) {
      expect(status.id, SyncIds.projectStatusId(project.id, status.statusKey));
    }

    await db.ensureProjectStatuses(project.id);
    expect(await db.select(db.projectStatuses).get(), hasLength(5));
  });

  test('status and completed stay in sync through every edit path', () async {
    final project = await createProject('Launch');
    var task = await addTask(project.id, 'Write');

    await workflow.updateTask(
      task,
      title: 'Write the plan',
      statusKey: ProjectStatusCatalog.inProgress.key,
      startDate: DateTime(2026, 5, 20, 14),
      dueDate: DateTime(2026, 5, 22),
      estimatedMinutes: 90,
      priority: 2,
    );
    task = await db.select(db.tasks).getSingle();
    expect(task.title, 'Write the plan');
    expect(task.statusKey, 'in_progress');
    expect(task.completed, isFalse);
    expect(task.startDate, DateTime(2026, 5, 20));
    expect(task.dueDate, DateTime(2026, 5, 22));
    expect(task.estimatedMinutes, 90);
    expect(task.priority, 2);

    await workflow.moveTaskToStatus(task, ProjectStatusCatalog.done.key);
    task = await db.select(db.tasks).getSingle();
    expect(task.statusKey, 'done');
    expect(task.completed, isTrue);

    await workflow.toggleTask(task, false);
    task = await db.select(db.tasks).getSingle();
    expect(task.statusKey, 'todo');
    expect(task.completed, isFalse);
  });

  test('task edit validation rejects invalid ranges', () async {
    final project = await createProject('Launch');
    final task = await addTask(project.id, 'Write');

    await expectLater(
      workflow.updateTask(
        task,
        title: 'Write',
        statusKey: 'todo',
        startDate: DateTime(2026, 5, 22),
        dueDate: DateTime(2026, 5, 20),
        estimatedMinutes: null,
        priority: 0,
      ),
      throwsArgumentError,
    );
    await expectLater(
      workflow.updateTask(
        task,
        title: 'Write',
        statusKey: 'todo',
        estimatedMinutes: 0,
        priority: 0,
      ),
      throwsArgumentError,
    );
    await expectLater(
      workflow.updateTask(
        task,
        title: '   ',
        statusKey: 'todo',
        estimatedMinutes: null,
        priority: 0,
      ),
      throwsArgumentError,
    );
  });

  test('deleting and restoring a task keeps its dependency edges', () async {
    final project = await createProject('Launch');
    final first = await addTask(project.id, 'First');
    final second = await addTask(project.id, 'Second');
    await workflow.addDependency(
      predecessorTaskId: first.id,
      successorTaskId: second.id,
    );

    await workflow.deleteTaskWithUndo(first);
    expect(await db.select(db.tasks).get(), hasLength(1));
    expect(await db.select(db.taskDependencies).get(), isEmpty);

    expect(await undo.undo(), isTrue);
    expect(await db.select(db.tasks).get(), hasLength(2));
    final dependencies = await workflow.loadDependencies(project.id);
    expect(dependencies, hasLength(1));
    expect(dependencies.single.predecessorTaskId, first.id);
    expect(dependencies.single.successorTaskId, second.id);
  });

  test('milestones round-trip and survive undo', () async {
    final project = await createProject('Launch');
    final id = await workflow.addMilestone(
      projectId: project.id,
      title: 'Beta',
      description: '  Ship it  ',
      targetDate: DateTime(2026, 6, 1, 15),
    );
    var milestone = (await workflow.watchMilestones(project.id).first).single;
    expect(milestone.id, id);
    expect(milestone.description, 'Ship it');
    expect(milestone.targetDate, DateTime(2026, 6, 1));

    await workflow.updateMilestone(
      milestone,
      title: 'Public beta',
      targetDate: DateTime(2026, 6, 2),
    );
    milestone = (await workflow.watchMilestones(project.id).first).single;
    expect(milestone.title, 'Public beta');
    expect(milestone.targetDate, DateTime(2026, 6, 2));

    await workflow.setMilestoneCompleted(milestone, true);
    milestone = (await workflow.watchMilestones(project.id).first).single;
    expect(milestone.completedAt, isNotNull);

    await workflow.deleteMilestone(milestone);
    expect(await db.select(db.projectMilestones).get(), isEmpty);
    expect(await undo.undo(), isTrue);
    expect(await db.select(db.projectMilestones).get(), hasLength(1));
  });

  test(
    'dependencies reject self, duplicates, cross-project and cycles',
    () async {
      final project = await createProject('Launch');
      final other = await createProject('Other');
      final a = await addTask(project.id, 'A');
      final b = await addTask(project.id, 'B');
      final c = await addTask(project.id, 'C');
      final foreign = await addTask(other.id, 'Foreign');

      await expectLater(
        workflow.addDependency(predecessorTaskId: a.id, successorTaskId: a.id),
        throwsArgumentError,
      );
      await expectLater(
        workflow.addDependency(
          predecessorTaskId: a.id,
          successorTaskId: foreign.id,
        ),
        throwsArgumentError,
      );
      await workflow.addDependency(
        predecessorTaskId: a.id,
        successorTaskId: b.id,
      );
      await expectLater(
        workflow.addDependency(predecessorTaskId: a.id, successorTaskId: b.id),
        throwsStateError,
      );
      await workflow.addDependency(
        predecessorTaskId: b.id,
        successorTaskId: c.id,
      );
      await expectLater(
        workflow.addDependency(predecessorTaskId: c.id, successorTaskId: a.id),
        throwsStateError,
      );
    },
  );

  test('dependency warnings are advisory and date based', () async {
    final project = await createProject('Launch');
    final first = await addTask(project.id, 'First');
    final second = await addTask(project.id, 'Second');
    await workflow.updateTask(
      first,
      title: first.title,
      statusKey: 'todo',
      dueDate: DateTime(2026, 5, 22),
      estimatedMinutes: null,
      priority: 0,
    );
    await workflow.updateTask(
      second,
      title: second.title,
      statusKey: 'todo',
      startDate: DateTime(2026, 5, 20),
      estimatedMinutes: null,
      priority: 0,
    );
    await workflow.addDependency(
      predecessorTaskId: first.id,
      successorTaskId: second.id,
    );

    var tasks = await db.select(db.tasks).get();
    var dependencies = await workflow.loadDependencies(project.id);
    var target = tasks.firstWhere((task) => task.id == second.id);
    var warnings = workflow.dependencyWarnings(
      task: target,
      projectTasks: tasks,
      dependencies: dependencies,
    );
    expect(warnings, hasLength(2));
    expect(warnings.first, contains('Blocked by'));
    expect(warnings.last, contains('Suggested earliest start'));

    await workflow.moveTaskToStatus(
      tasks.firstWhere((task) => task.id == first.id),
      'done',
    );
    tasks = await db.select(db.tasks).get();
    dependencies = await workflow.loadDependencies(project.id);
    target = tasks.firstWhere((task) => task.id == second.id);
    warnings = workflow.dependencyWarnings(
      task: target,
      projectTasks: tasks,
      dependencies: dependencies,
    );
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('Suggested earliest start'));
  });

  test(
    'project delete and undo restore statuses, milestones and edges',
    () async {
      final project = await createProject('Launch');
      final first = await addTask(project.id, 'First');
      final second = await addTask(project.id, 'Second');
      await workflow.addDependency(
        predecessorTaskId: first.id,
        successorTaskId: second.id,
      );
      await workflow.addMilestone(
        projectId: project.id,
        title: 'Beta',
        targetDate: DateTime(2026, 6, 1),
      );
      await workflow.updateStatus(
        (await workflow.loadStatuses(project.id)).last,
        name: 'Shipped',
        colorToken: 'green',
      );

      await projects.deleteWithUndo(project.id);
      expect(await db.select(db.projects).get(), isEmpty);
      expect(await db.select(db.projectStatuses).get(), isEmpty);
      expect(await db.select(db.projectMilestones).get(), isEmpty);
      expect(await db.select(db.taskDependencies).get(), isEmpty);

      expect(await undo.undo(), isTrue);
      expect(await db.select(db.projects).get(), hasLength(1));
      expect(await db.select(db.projectStatuses).get(), hasLength(5));
      expect(await db.select(db.projectMilestones).get(), hasLength(1));
      expect(await db.select(db.taskDependencies).get(), hasLength(1));
      final restored = await workflow.loadStatuses(project.id);
      expect(restored.last.name, 'Shipped');
    },
  );
}
