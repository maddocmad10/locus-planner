import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

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
    await _db.into(_db.projects).insert(ProjectsCompanion(
          id: Value(_uuid.v4()),
          name: Value(name),
          description: Value(description),
          createdAt: Value(DateTime.now()),
          targetDate: Value(targetDate),
          targetProgress: Value(targetProgress),
        ));
  }

  Future<void> update(Project project) async {
    await _db.update(_db.projects).replace(project);
  }

  Future<void> delete(String id) async {
    await _db.deleteProject(id);
  }

  Future<void> logProgress({
    required String projectId,
    required int value,
    String? note,
  }) async {
    await _db.into(_db.progressLogs).insert(ProgressLogsCompanion(
          id: Value(_uuid.v4()),
          projectId: Value(projectId),
          value: Value(value),
          note: Value(note),
          timestamp: Value(DateTime.now()),
        ));
  }

  Future<int> progressPercent(String projectId) =>
      _db.projectProgressPercent(projectId);

  Future<void> addTask({
    required String projectId,
    required String title,
  }) async {
    final existing = await _db.watchTasksForProject(projectId).first;
    await _db.into(_db.tasks).insert(TasksCompanion(
          id: Value(_uuid.v4()),
          projectId: Value(projectId),
          title: Value(title),
          sortOrder: Value(existing.length),
        ));
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
      value: current + increment,
      note: 'Focus session (+$increment%)',
    );
  }
}
