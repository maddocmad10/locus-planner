import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../projects/data/project_repository.dart';

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  return FocusRepository(
    ref.watch(databaseProvider),
    ref.watch(projectRepositoryProvider),
  );
});

final focusSessionsStreamProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusRepositoryProvider).watchAll();
});

final focusMinutesTodayProvider = FutureProvider<int>((ref) {
  return ref.watch(focusRepositoryProvider).minutesToday();
});

class FocusRepository {
  FocusRepository(this._db, this._projects);
  final AppDatabase _db;
  final ProjectRepository _projects;
  final _uuid = const Uuid();

  Stream<List<FocusSession>> watchAll() => _db.watchFocusSessions();

  Future<int> minutesToday() => _db.focusMinutesToday();

  Future<void> completeSession({
    required int durationMinutes,
    String? projectId,
    String? note,
    DateTime? startedAt,
  }) async {
    String? validProjectId;
    if (projectId != null) {
      final project = await (_db.select(_db.projects)
            ..where((t) => t.id.equals(projectId)))
          .getSingleOrNull();
      validProjectId = project?.id;
    }

    await _db.into(_db.focusSessions).insert(FocusSessionsCompanion(
          id: Value(_uuid.v4()),
          projectId: Value(validProjectId),
          startTime: Value(
            startedAt ?? DateTime.now().subtract(Duration(minutes: durationMinutes)),
          ),
          durationMinutes: Value(durationMinutes),
          note: Value(note ?? 'Completed focus session'),
        ));
    if (validProjectId != null) {
      await _projects.addFocusProgress(validProjectId, durationMinutes);
    }
    try {
      await NotificationService.instance.showNow(
        title: 'Focus Complete',
        body: '$durationMinutes min logged',
      );
    } catch (_) {
      // A notification failure must not turn a successfully saved session into
      // an application-level failure.
    }
  }
}
