import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/core/providers/service_providers.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/mobile/data/mobile_reminder_service.dart';
import 'package:locus_planner/features/mobile/data/mobile_sync_client.dart';
import 'package:locus_planner/features/mobile/mobile_app.dart';

import 'helpers/fake_reminder_platform.dart';
import 'helpers/memory_app_lock_store.dart';

class _FakeMobileSyncClient extends MobileSyncClient {
  _FakeMobileSyncClient(super.db);

  @override
  Future<MobileSyncStatus> status() async =>
      const MobileSyncStatus(paired: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Initialize the in-memory database before the widget subscribes to streams.
    await db.customSelect('SELECT 1').get();
  });

  testWidgets('mobile app renders its shell and navigation', (tester) async {
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appLockServiceProvider.overrideWithValue(testAppLockService()),
            mobileSyncClientProvider.overrideWith(
              (ref) => _FakeMobileSyncClient(db),
            ),
          ],
          child: const LocusMobileApp(),
        ),
      );

      // Avoid pumpAndSettle: Material widgets can keep scheduling frames while
      // an async stream is loading (e.g. an indeterminate progress indicator).
      // A bounded pump lets the database-backed providers emit their first data.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Locus'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Tasks'), findsWidgets);
      expect(find.text('Diary'), findsWidgets);
      expect(find.text('Sync'), findsWidgets);
    } finally {
      // Dispose Riverpod stream subscriptions while the test can still pump
      // Drift's zero-duration close timers, then close the backing database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    }
  });

  group('event reminders on the phone', () {
    late FakeReminderPlatform platform;

    setUp(() => platform = FakeReminderPlatform());
    tearDown(() => AppClock.now = DateTime.now);

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appLockServiceProvider.overrideWithValue(testAppLockService()),
            reminderPlatformProvider.overrideWithValue(platform),
            mobileSyncClientProvider.overrideWith(
              (ref) => _FakeMobileSyncClient(db),
            ),
          ],
          child: const LocusMobileApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> closeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    }

    Future<void> openCapture(WidgetTester tester, String title) async {
      await tester.tap(find.byTooltip('Quick capture'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        title,
      );
    }

    testWidgets('capture refuses a reminder time that has passed', (
      tester,
    ) async {
      try {
        await pumpApp(tester);
        await openCapture(tester, 'Call mum');

        // The event starts now, so a reminder 5 minutes before it is gone.
        await tester.tap(find.text('5 min before'));
        await tester.pump();
        await tester.tap(find.text('Save locally'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('already passed'), findsOneWidget);
        expect(await db.select(db.events).get(), isEmpty);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('capture without a reminder saves a plain event', (
      tester,
    ) async {
      try {
        await pumpApp(tester);
        await openCapture(tester, 'Call mum');

        await tester.tap(find.text('Save locally'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        final events = await db.select(db.events).get();
        expect(events, hasLength(1));
        expect(events.single.title, 'Call mum');
        expect(events.single.hasReminder, isFalse);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('Today marks an event that has a reminder', (tester) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                id: 'e1',
                title: 'Dentist',
                startTime: DateTime(2026, 10, 28, 9),
                hasReminder: const Value(true),
              ),
            );
        await pumpApp(tester);
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Dentist'), findsOneWidget);
        expect(
          find.byIcon(Icons.notifications_active_outlined),
          findsOneWidget,
        );
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('opening the app plans the stored reminders', (tester) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                id: 'e1',
                title: 'Dentist',
                startTime: DateTime(2026, 10, 28, 9),
                hasReminder: const Value(true),
              ),
            );
        await pumpApp(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );

        expect(platform.replaced, isNotEmpty);
        expect(platform.replaced.last.single.title, 'Dentist');
      } finally {
        await closeApp(tester);
      }
    });
  });

  group('Android MVP gaps', () {
    tearDown(() => AppClock.now = DateTime.now);

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            appLockServiceProvider.overrideWithValue(testAppLockService()),
            mobileSyncClientProvider.overrideWith(
              (ref) => _FakeMobileSyncClient(db),
            ),
          ],
          child: const LocusMobileApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> closeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    }

    testWidgets('Today shows the current occurrence of a recurring event', (
      tester,
    ) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                id: 'standup',
                title: 'Standup',
                startTime: DateTime(2026, 10, 26, 9),
                recurrenceRule: const Value('daily'),
              ),
            );
        await pumpApp(tester);

        expect(find.text('Standup'), findsOneWidget);
        expect(find.textContaining('Daily'), findsOneWidget);
        expect(find.byIcon(Icons.repeat), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('upcoming days can be browsed and habits toggled', (
      tester,
    ) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await db
            .into(db.habits)
            .insert(
              HabitsCompanion.insert(
                id: 'h1',
                name: 'Read',
                createdAt: DateTime(2026, 10, 1),
              ),
            );
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                id: 'e2',
                title: 'Planning',
                startTime: DateTime(2026, 10, 29, 9),
              ),
            );
        await pumpApp(tester);

        // Tomorrow is not on the agenda until its chip is selected.
        expect(find.text('Planning'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('agenda-day-1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Planning'), findsOneWidget);
        expect(find.text('Habits on Thu 29 Oct'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const ValueKey('habit-h1')));
        await tester.tap(find.byKey(const ValueKey('habit-h1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final logs = await db.select(db.habitLogs).get();
        expect(logs, hasLength(1));
        expect(logs.single.habitId, 'h1');
        expect(logs.single.date, DateTime(2026, 10, 29));
        expect(logs.single.completed, isTrue);

        // Tapping the same upcoming day again clears the log.
        await tester.tap(find.byKey(const ValueKey('habit-h1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(await db.select(db.habitLogs).get(), isEmpty);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('the phone can create a habit locally', (tester) async {
      try {
        await pumpApp(tester);

        await tester.ensureVisible(find.text('New habit'));
        await tester.tap(find.text('New habit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          'Stretch',
        );
        await tester.tap(find.text('Create'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final habits = await db.select(db.habits).get();
        expect(habits, hasLength(1));
        expect(habits.single.name, 'Stretch');
        expect(find.text('Stretch'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('a task can be deleted and restored', (tester) async {
      try {
        await db.addTodoItem('Buy milk', null);
        await pumpApp(tester);

        await tester.tap(find.text('Tasks'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Buy milk'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(await db.select(db.todoItems).get(), isEmpty);
        expect(find.text('Undo'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('a diary entry is saved without tapping Save', (tester) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await pumpApp(tester);

        await tester.tap(find.text('Diary'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.enterText(find.byType(TextField), 'A quiet day');

        // Longer than the autosave debounce, plus time for the database write.
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final entries = await db.select(db.diaryEntries).get();
        await tester.pump();
        expect(entries, hasLength(1));
        expect(entries.single.content, 'A quiet day');
        expect(find.textContaining('Saved at'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('an event can be moved to another day', (tester) async {
      AppClock.now = () => DateTime(2026, 10, 28, 8);
      try {
        await db
            .into(db.events)
            .insert(
              EventsCompanion.insert(
                id: 'e1',
                title: 'Dentist',
                startTime: DateTime(2026, 10, 28, 9),
              ),
            );
        await pumpApp(tester);

        await tester.tap(find.text('Dentist'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Edit event'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.schedule));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('15'));
        await tester.pump();
        await tester.tap(find.text('OK'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('OK'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final events = await db.select(db.events).get();
        expect(events.single.startTime.day, 15);
        expect(events.single.title, 'Dentist');
      } finally {
        await closeApp(tester);
      }
    });
  });
}
