import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/services/undo_service.dart';
import 'package:locus_planner/features/projects/data/project_repository.dart';
import 'package:locus_planner/features/projects/data/project_workflow_repository.dart';

void main() {
  late AppDatabase db;
  late Directory dir;
  late UndoService undo;
  late ProjectRepository projects;
  late ProjectWorkflowRepository workflow;

  setUp(() {
    DatabaseSecurity.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = Directory.systemTemp.createTempSync('locus-phase3-');
    undo = UndoService();
    projects = ProjectRepository(db, undo);
    workflow = ProjectWorkflowRepository(db, undo);
  });

  tearDown(() async {
    DatabaseSecurity.reset();
    undo.dispose();
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<({Project project, Task first, Task second})> seed() async {
    await projects.create(name: 'Launch');
    final project = await db.select(db.projects).getSingle();
    await projects.addTask(projectId: project.id, title: 'First');
    await projects.addTask(projectId: project.id, title: 'Second');
    final tasks = await db.select(db.tasks).get();
    final first = tasks.firstWhere((task) => task.title == 'First');
    final second = tasks.firstWhere((task) => task.title == 'Second');
    await workflow.updateTask(
      first,
      title: first.title,
      statusKey: 'in_progress',
      startDate: DateTime(2026, 5, 20),
      dueDate: DateTime(2026, 5, 22),
      estimatedMinutes: 90,
      priority: 2,
    );
    await workflow.updateTask(
      second,
      title: second.title,
      statusKey: 'todo',
      startDate: DateTime(2026, 5, 23),
      dueDate: DateTime(2026, 5, 25),
      estimatedMinutes: 30,
      priority: 1,
    );
    await workflow.addDependency(
      predecessorTaskId: first.id,
      successorTaskId: second.id,
    );
    await workflow.addMilestone(
      projectId: project.id,
      title: 'Beta',
      description: 'Ship it',
      targetDate: DateTime(2026, 6, 1),
    );
    await workflow.updateStatus(
      (await workflow.loadStatuses(project.id)).last,
      name: 'Shipped',
      colorToken: 'green',
    );
    return (project: project, first: first, second: second);
  }

  test('backup v3 exports and restores Phase 3 project data', () async {
    final data = await seed();
    final json = await DataExportService(
      db,
      backupDirectory: dir,
    ).buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    for (final section in const [
      'project_statuses',
      'project_milestones',
      'task_dependencies',
    ]) {
      expect(decoded[section], isA<List<dynamic>>(), reason: section);
      expect(
        (decoded['tables'] as Map<String, dynamic>).keys,
        contains(section),
      );
    }
    final taskRows = decoded['tasks'] as List<dynamic>;
    final firstRow =
        taskRows.firstWhere(
              (row) => (row as Map<String, dynamic>)['id'] == data.first.id,
            )
            as Map<String, dynamic>;
    expect(firstRow['statusKey'], 'in_progress');
    expect(firstRow['estimatedMinutes'], 90);
    expect(firstRow['priority'], 2);
    expect(firstRow['startDate'], DateTime(2026, 5, 20).millisecondsSinceEpoch);

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final report = await DataExportService(restored).restoreFromJson(json);
    expect(report.skippedRows, 0);

    final restoredTask = await (restored.select(
      restored.tasks,
    )..where((t) => t.id.equals(data.first.id))).getSingle();
    expect(restoredTask.statusKey, 'in_progress');
    expect(restoredTask.startDate, DateTime(2026, 5, 20));
    expect(restoredTask.dueDate, DateTime(2026, 5, 22));
    expect(restoredTask.estimatedMinutes, 90);
    expect(restoredTask.priority, 2);

    final statuses = await restored.select(restored.projectStatuses).get();
    expect(statuses, hasLength(5));
    expect(
      statuses.firstWhere((status) => status.statusKey == 'done').name,
      'Shipped',
    );
    final milestone = await restored
        .select(restored.projectMilestones)
        .getSingle();
    expect(milestone.title, 'Beta');
    expect(milestone.targetDate, DateTime(2026, 6, 1));
    final dependency = await restored
        .select(restored.taskDependencies)
        .getSingle();
    expect(dependency.predecessorTaskId, data.first.id);
    expect(dependency.successorTaskId, data.second.id);
  });

  test('a backup without Phase 3 sections still restores tasks', () async {
    await seed();
    final json = await DataExportService(
      db,
      backupDirectory: dir,
    ).buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final manifest = decoded['tables'] as Map<String, dynamic>;
    for (final section in const [
      'project_statuses',
      'project_milestones',
      'task_dependencies',
    ]) {
      decoded.remove(section);
      manifest.remove(section);
    }
    // An older backup also lacks the Phase 3 task columns.
    for (final row in decoded['tasks'] as List<dynamic>) {
      final map = row as Map<String, dynamic>;
      map.remove('statusKey');
      map.remove('startDate');
      map.remove('dueDate');
      map.remove('estimatedMinutes');
      map.remove('priority');
    }
    manifest.remove('tasks');
    decoded.remove('payload_sha256');

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final report = await DataExportService(
      restored,
    ).restoreFromJson(jsonEncode(decoded));
    expect(report.skippedRows, 0);
    expect(await restored.select(restored.tasks).get(), hasLength(2));
    expect(await restored.select(restored.projectMilestones).get(), isEmpty);
    expect(await restored.select(restored.taskDependencies).get(), isEmpty);
    final task = (await restored.select(restored.tasks).get()).first;
    expect(task.statusKey, 'todo');
    expect(task.priority, 0);
  });

  test('outbox captures Phase 3 entities and cascades tombstones', () async {
    final data = await seed();

    final upserts = await db
        .customSelect(
          'SELECT DISTINCT entity_type FROM sync_outbox WHERE operation = ?',
          variables: [Variable.withString('upsert')],
        )
        .get();
    final types = upserts.map((row) => row.read<String>('entity_type')).toSet();
    expect(
      types,
      containsAll([
        'project_status',
        'project_milestone',
        'task_dependency',
        'project_task',
      ]),
    );

    await db.customStatement('DELETE FROM tasks WHERE id = ?', [data.first.id]);
    final deletes = await db
        .customSelect(
          'SELECT entity_type FROM sync_outbox WHERE operation = ?',
          variables: [Variable.withString('delete')],
        )
        .get();
    final deletedTypes = deletes
        .map((row) => row.read<String>('entity_type'))
        .toSet();
    expect(deletedTypes, containsAll(['project_task', 'task_dependency']));

    await db.customStatement('DELETE FROM projects WHERE id = ?', [
      data.project.id,
    ]);
    final projectDeletes = await db
        .customSelect(
          'SELECT DISTINCT entity_type FROM sync_outbox WHERE operation = ?',
          variables: [Variable.withString('delete')],
        )
        .get();
    expect(
      projectDeletes.map((row) => row.read<String>('entity_type')).toSet(),
      containsAll(['project_status', 'project_milestone']),
    );
  });

  test('full state syncs Phase 3 data in dependency-safe order', () async {
    final data = await seed();
    final phone = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(phone.close);
    await phone.ensureDeviceIdentity();

    final state = await SyncChangeApplier.readFullState(db);
    final projectIndex = state.indexWhere(
      (change) => change['entityType'] == 'project',
    );
    final statusIndex = state.indexWhere(
      (change) => change['entityType'] == 'project_status',
    );
    final taskIndex = state.indexWhere(
      (change) =>
          change['entityType'] == 'project_task' &&
          change['entityId'] == data.first.id,
    );
    final dependencyIndex = state.indexWhere(
      (change) => change['entityType'] == 'task_dependency',
    );
    expect(projectIndex, greaterThanOrEqualTo(0));
    expect(statusIndex, greaterThan(projectIndex));
    expect(taskIndex, greaterThan(projectIndex));
    expect(dependencyIndex, greaterThan(taskIndex));

    final result = await SyncChangeApplier(phone).apply(state);
    expect(result.rejected, isEmpty);
    final phoneTask = await (phone.select(
      phone.tasks,
    )..where((t) => t.id.equals(data.first.id))).getSingle();
    expect(phoneTask.statusKey, 'in_progress');
    expect(phoneTask.estimatedMinutes, 90);
    expect(phoneTask.priority, 2);
    expect(await phone.select(phone.projectStatuses).get(), hasLength(5));
    expect(await phone.select(phone.projectMilestones).get(), hasLength(1));
    expect(await phone.select(phone.taskDependencies).get(), hasLength(1));

    final payload =
        state.firstWhere(
              (change) =>
                  change['entityType'] == 'project_task' &&
                  change['entityId'] == data.first.id,
            )['payload']
            as Map<String, dynamic>;
    expect(payload['sync_updated_at'], isNull);
    expect(payload['updated_at'], isA<int>());
    expect(payload['updated_at'], greaterThan(0));
  });

  test('an old peer task payload degrades to completed status', () async {
    final phone = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(phone.close);
    await phone.ensureDeviceIdentity();
    await phone
        .into(phone.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Launch',
            createdAt: DateTime(2026, 5, 1),
          ),
        );

    final result = await SyncChangeApplier(phone).apply([
      {
        'entityType': 'project_task',
        'entityId': 't1',
        'operation': 'upsert',
        'payload': {
          'id': 't1',
          'project_id': 'p1',
          'title': 'Old task',
          'completed': 1,
          'sort_order': 0,
          'updated_at': 1000,
        },
        'deviceId': 'old-peer',
      },
    ]);
    expect(result.rejected, isEmpty);
    final task = await phone.select(phone.tasks).getSingle();
    expect(task.completed, isTrue);
    expect(task.statusKey, 'done');
    expect(task.priority, 0);
  });

  test(
    'an orphan or cyclic dependency is rejected with a diagnostic',
    () async {
      await seed();
      final phone = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(phone.close);
      await phone.ensureDeviceIdentity();
      final state = await SyncChangeApplier.readFullState(db);
      await SyncChangeApplier(phone).apply(state);

      final orphan = await SyncChangeApplier(phone).apply([
        {
          'entityType': 'task_dependency',
          'entityId': 'missing-edge',
          'operation': 'upsert',
          'payload': {
            'id': 'missing-edge',
            'predecessor_task_id': 'missing-a',
            'successor_task_id': 'missing-b',
            'dependency_type': 'finish_to_start',
            'lag_minutes': 0,
            'created_at': 1000,
            'updated_at': 1000,
            'sync_updated_at': 1000,
          },
          'deviceId': 'peer',
        },
      ]);
      expect(orphan.rejected, hasLength(1));
      expect(orphan.rejected.single.reason, contains('endpoint'));

      final tasks = await phone.select(phone.tasks).get();
      final edge = await phone.select(phone.taskDependencies).getSingle();
      final cycle = await SyncChangeApplier(phone).apply([
        {
          'entityType': 'task_dependency',
          'entityId': 'cycle-edge',
          'operation': 'upsert',
          'payload': {
            'id': 'cycle-edge',
            'predecessor_task_id': edge.successorTaskId,
            'successor_task_id': edge.predecessorTaskId,
            'dependency_type': 'finish_to_start',
            'lag_minutes': 0,
            'created_at': 1000,
            'updated_at': 1000,
            'sync_updated_at': 1000,
          },
          'deviceId': 'peer',
        },
      ]);
      expect(cycle.rejected, hasLength(1));
      expect(cycle.rejected.single.reason, contains('cycle'));
      expect(tasks, hasLength(2));
    },
  );
}
