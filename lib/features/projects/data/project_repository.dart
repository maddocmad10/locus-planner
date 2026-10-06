import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

final projectsStreamProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).watchAll();
});

final projectProgressStreamProvider = StreamProvider<Map<String, double>>((ref) {
  return ref.watch(databaseProvider).watchProjectProgress();
});

final projectTasksProvider = StreamProvider.family<List<Task>, String>((ref, projectId) {
  return ref.watch(projectRepositoryProvider).watchTasks(projectId);
});

final projectProgressLogsProvider = StreamProvider.family<List<ProgressLog>, String>((ref, projectId) {
  return ref.watch(projectRepositoryProvider).watchProgress(projectId);
});

class ProjectRepository {
  ProjectRepository(this._db, this._undo);
  final AppDatabase _db;
  final UndoService _undo;
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
    if (targetProgress < 0 || targetProgress > 100) {
      throw ArgumentError.value(targetProgress, 'targetProgress', 'must be between 0 and 100');
    }
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
    _undo.offer(
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
    if (value < 0 || value > 100) {
      throw ArgumentError.value(value, 'value', 'must be between 0 and 100');
    }
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
    await _db.addTask(projectId, title);
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
    final next = (current + increment).round().clamp(0, 100);
    await logProgress(
      projectId: projectId,
      value: next,
      note: 'Focus session (+$increment%)',
    );
  }
}
