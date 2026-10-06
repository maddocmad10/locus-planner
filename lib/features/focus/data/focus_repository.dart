import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../projects/data/project_repository.dart';

final focusRepositoryProvider = Provider<FocusRepository>((ref) {
  return FocusRepository(
    ref.watch(databaseProvider),
    ref.watch(projectRepositoryProvider),
    ref.watch(notificationServiceProvider),
  );
});

final focusSessionsTodayProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusRepositoryProvider).watchToday();
});

final recentFocusSessionsProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusRepositoryProvider).watchRecent(limit: 5);
});

final focusMinutesLast7DaysProvider = StreamProvider<int>((ref) {
  return ref.watch(focusRepositoryProvider).watchLastDays(7).map(
    (sessions) => sessions.fold<int>(0, (sum, session) => sum + session.durationMinutes),
  );
});

class FocusRepository {
  FocusRepository(this._db, this._projects, this._notifications);
  final AppDatabase _db;
  final ProjectRepository _projects;
  final NotificationService _notifications;
  final _uuid = const Uuid();

  Stream<List<FocusSession>> watchToday() =>
      _db.watchFocusSessionsForDay(DateTime.now());

  Stream<List<FocusSession>> watchRecent({int limit = 5}) =>
      _db.watchRecentFocusSessions(limit: limit);

  Stream<List<FocusSession>> watchLastDays(int days) =>
      _db.watchFocusSessionsLastDays(days);

  Future<void> completeSession({
    String? sessionId,
    required int durationMinutes,
    String? projectId,
    String? note,
    DateTime? startedAt,
    bool notify = true,
  }) async {
    if (durationMinutes < 1 || durationMinutes > 24 * 60) {
      throw ArgumentError.value(durationMinutes, 'durationMinutes', 'must be between 1 and 1440');
    }
    String? validProjectId;
    if (projectId != null) {
      final project = await (_db.select(
        _db.projects,
      )..where((t) => t.id.equals(projectId))).getSingleOrNull();
      validProjectId = project?.id;
    }

    final id = sessionId ?? _uuid.v4();
    final existing = await (_db.select(
      _db.focusSessions,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (existing != null) return;

    await _db.transaction(() async {
      await _db
          .into(_db.focusSessions)
          .insert(
            FocusSessionsCompanion(
              id: Value(id),
              projectId: Value(validProjectId),
              startTime: Value(
                startedAt ??
                    DateTime.now().subtract(Duration(minutes: durationMinutes)),
              ),
              durationMinutes: Value(durationMinutes),
              note: Value(note ?? 'Completed focus session'),
            ),
          );
      if (validProjectId != null) {
        await _projects.addFocusProgress(validProjectId, durationMinutes);
      }
    });
    if (notify) {
      try {
        await _notifications.showFocusComplete(
          minutes: durationMinutes,
        );
      } catch (_) {
        // A notification failure must not turn a successfully saved session into
        // an application-level failure.
      }
    }
  }
}
