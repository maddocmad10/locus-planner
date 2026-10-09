// Tests for the focus timer provider. Uses an in-memory database (see the note
// in data_layer_test.dart about sqlite3 on Windows).
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/focus/providers/focus_timer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;

  FocusTimerNotifier notifier() => container.read(focusTimerProvider.notifier);
  FocusTimerState state() => container.read(focusTimerProvider);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await notifier().debugWaitForRestore();
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('starts idle at 25 minutes', () {
    expect(state().status, FocusTimerStatus.idle);
    expect(state().selectedMinutes, 25);
    expect(state().remainingSeconds, 25 * 60);
  });


  test('restores corrupted persisted values safely', () async {
    await db.setSetting(
      'focus.active_session',
      jsonEncode({
        'selectedMinutes': 0,
        'remainingSeconds': -50,
        'status': 'paused',
      }),
    );

    container.dispose();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await notifier().debugWaitForRestore();

    expect(state().selectedMinutes, 1);
    expect(state().remainingSeconds, 0);
    expect(state().progress, 0.0);
  });

  test('setDuration changes the length while idle', () {
    notifier().setDuration(50);
    expect(state().selectedMinutes, 50);
    expect(state().remainingSeconds, 50 * 60);
  });

  test('setDuration is ignored while running', () {
    notifier().start();
    notifier().setDuration(90);
    expect(state().selectedMinutes, 25);
    expect(state().isRunning, isTrue);
    notifier().reset();
  });

  test('pause keeps the remaining time; reset restores the full length', () {
    notifier().start();
    expect(state().isRunning, isTrue);

    notifier().pause();
    expect(state().status, FocusTimerStatus.paused);
    expect(state().remainingSeconds, inInclusiveRange(25 * 60 - 1, 25 * 60));

    notifier().reset();
    expect(state().status, FocusTimerStatus.idle);
    expect(state().remainingSeconds, 25 * 60);
  });

  test('completing a session saves it and returns to idle', () async {
    notifier().start();
    await notifier().debugComplete();

    final sessions = await db.select(db.focusSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.durationMinutes, 25);
    expect(sessions.single.projectId, isNull);
    expect(state().completedCount, 1);
    expect(state().status, FocusTimerStatus.idle);
    expect(state().remainingSeconds, 25 * 60);
  });

  test('a session is linked to the selected project', () async {
    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Alpha',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    notifier().setProject('p1');
    await notifier().debugComplete();

    final session = await db.select(db.focusSessions).getSingle();
    expect(session.projectId, 'p1');
    final progress = await db.getProgressLogs('p1');
    expect(progress, hasLength(1));
    expect(progress.single.value, 5);
  });

  test('a deleted project does not lose the session', () async {
    notifier().setProject('deleted-project');
    await notifier().debugComplete();

    final session = await db.select(db.focusSessions).getSingle();
    expect(session.projectId, isNull);
    expect(state().completedCount, 1);
  });
  test('recovers a pending completed session on startup', () async {
    final startedAt = DateTime(2026, 10, 8, 9);
    await db.setSetting(
      'focus.active_session',
      jsonEncode({
        'pendingCompletion': {
          'sessionId': 'pending-1',
          'durationMinutes': 25,
          'projectId': null,
          'startedAt': startedAt.toIso8601String(),
        },
      }),
    );

    container.dispose();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await notifier().debugWaitForRestore();

    final sessions = await db.select(db.focusSessions).get();
    expect(sessions, hasLength(1));
    expect(sessions.single.id, 'pending-1');
    expect(state().completedCount, 1);
    expect(await db.getSetting('focus.active_session'), isNull);
  });

  test(
    'persists a paused session and restores it in a new provider scope',
    () async {
      notifier().setDuration(50);
      notifier().start();
      notifier().pause();
      final persisted = await db.getSetting('focus.active_session');
      expect(persisted, isNotNull);

      container.dispose();
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await notifier().debugWaitForRestore();

      expect(state().status, FocusTimerStatus.paused);
      expect(state().selectedMinutes, 50);
      expect(state().remainingSeconds, inInclusiveRange(50 * 60 - 1, 50 * 60));
      notifier().reset();
    },
  );
  test('FocusTimerState defaults to not restoring', () {
    expect(const FocusTimerState().isRestoring, isFalse);
  });
}
