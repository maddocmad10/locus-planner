import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/undo_service.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(ref.watch(databaseProvider));
});

class ProjectRepository {
  ProjectRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Project>> watchAll() => _db.watchProjects();
  Stream<List<ProgressLog>> watchProgress(String projectId) =>
      _db.watchProgressForProject(projectId);
  Stream<List<Task>> watchTasks(String projectId) =>
      _db.watchTasksForProject(projectId);

  Future<void> create({
    required String name,
    String? description,
    DateTime? targetDate,
    int targetProgress = 100,
  }) async {
    await _db
        .into(_db.projects)
        .insert(
          ProjectsCompanion(
            id: Value(_uuid.v4()),
            name: Value(name),
            description: Value(description),
            createdAt: Value(DateTime.now()),
            targetDate: Value(targetDate),
            targetProgress: Value(targetProgress),
          ),
        );
  }

  Future<void> update(Project project) async {
    await _db.update(_db.projects).replace(project);
  }

  Future<void> delete(String id) async {
    await _db.deleteProject(id);
  }

  Future<void> deleteWithUndo(String id) async {
    final project = await (_db.select(
      _db.projects,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (project == null) return;
    final tasks = await (_db.select(
      _db.tasks,
    )..where((t) => t.projectId.equals(id))).get();
    final logs = await (_db.select(
      _db.progressLogs,
    )..where((t) => t.projectId.equals(id))).get();
    final sessions = await (_db.select(
      _db.focusSessions,
    )..where((t) => t.projectId.equals(id))).get();

    await _db.deleteProject(id);
    UndoService.instance.offer(
      label: 'project',
      restore: () async {
        await _db.transaction(() async {
          await _db.into(_db.projects).insert(project);
          for (final task in tasks) {
            await _db.into(_db.tasks).insert(task);
          }
          for (final log in logs) {
            await _db.into(_db.progressLogs).insert(log);
          }
          for (final session in sessions) {
            await (_db.update(_db.focusSessions)
                  ..where((t) => t.id.equals(session.id)))
                .write(FocusSessionsCompanion(projectId: Value(id)));
          }
        });
      },
    );
  }

  Future<void> logProgress({
    required String projectId,
    required int value,
    String? note,
  }) async {
    await _db
        .into(_db.progressLogs)
        .insert(
          ProgressLogsCompanion(
            id: Value(_uuid.v4()),
            projectId: Value(projectId),
            value: Value(value),
            note: Value(note),
            timestamp: Value(DateTime.now()),
          ),
        );
  }

  Future<double> progressPercent(String projectId) =>
      _db.projectProgressPercent(projectId);

  Future<void> addTask({
    required String projectId,
    required String title,
  }) async {
    final existing = await _db.watchTasksForProject(projectId).first;
    await _db
        .into(_db.tasks)
        .insert(
          TasksCompanion(
            id: Value(_uuid.v4()),
            projectId: Value(projectId),
            title: Value(title),
            sortOrder: Value(existing.length),
          ),
        );
  }

  Future<void> toggleTask(Task task, bool completed) async {
    await _db.update(_db.tasks).replace(task.copyWith(completed: completed));
  }

  Future<void> deleteTask(String id) async {
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
  }

  Future<void> addFocusProgress(String projectId, int minutes) async {
    final current = await _db.projectProgressPercent(projectId);
    final increment = (minutes ~/ 5).clamp(1, 10);
    await logProgress(
      projectId: projectId,
      value: (current + increment).round(),
      note: 'Focus session (+$increment%)',
    );
  }
}
