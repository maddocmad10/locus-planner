import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/core/providers/service_providers.dart';
import 'package:locus_planner/core/services/notification_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/core/widgets/quick_add_preview.dart';
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

    testWidgets('exact reminder timing can be turned off', (tester) async {
      try {
        await pumpApp(tester);
        await tester.tap(find.text('Sync'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Exact reminder timing'), findsOneWidget);
        await tester.tap(find.text('Exact reminder timing'));
        await tester.pump();

        expect(platform.exactAlarmsEnabledRequests, <bool>[false]);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        await db.close();
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
            notificationServiceProvider.overrideWithValue(
              NotificationService(
                showOverride: ({required title, required body}) async {},
              ),
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

        // A future day cannot be ticked.
        expect(await db.select(db.habitLogs).get(), isEmpty);

        // Return to today and tick it there.
        await tester.tap(find.byKey(const ValueKey('agenda-day-0')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.ensureVisible(find.byKey(const ValueKey('habit-h1')));
        await tester.tap(find.byKey(const ValueKey('habit-h1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final logs = await db.select(db.habitLogs).get();
        expect(logs, hasLength(1));
        expect(logs.single.habitId, 'h1');
        expect(logs.single.date, DateTime(2026, 10, 28));
        expect(logs.single.completed, isTrue);

        // Tapping the same day again clears the log.
        await tester.tap(find.byKey(const ValueKey('habit-h1')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(await db.select(db.habitLogs).get(), isEmpty);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('day navigation moves to yesterday and back to today', (
      tester,
    ) async {
      try {
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);

        await tester.tap(find.byTooltip('Previous day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Yesterday'), findsOneWidget);
        expect(find.text('Agenda for Tue 27 Oct'), findsOneWidget);

        await tester.tap(find.widgetWithText(TextButton, 'Today'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Your agenda'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('quick capture starts on the viewed day', (tester) async {
      try {
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);

        await tester.tap(find.byTooltip('Previous day'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.byTooltip('Quick capture'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.textContaining('Tue 27 Oct, 9:00'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('quick capture previews and saves a natural-language event', (
      tester,
    ) async {
      try {
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);
        await tester.tap(find.byTooltip('Quick capture'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          'Team standup tomorrow 9am',
        );
        await tester.pump();

        expect(find.byType(QuickAddPreview), findsOneWidget);
        expect(find.textContaining('Thu 29 Oct, 9:00'), findsWidgets);

        await tester.tap(find.text('Save locally'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final events = await db.select(db.events).get();
        expect(events.single.title, 'Team standup');
        expect(events.single.startTime, DateTime(2026, 10, 29, 9));
        expect(events.single.allDay, isFalse);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('quick capture saves a recurring task with priority', (
      tester,
    ) async {
      try {
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);
        await tester.tap(find.byTooltip('Quick capture'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('Task'),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(TextField),
          ),
          'Review draft every Monday !',
        );
        await tester.pump();

        expect(find.text('Weekly'), findsOneWidget);
        expect(find.text('Low priority'), findsOneWidget);

        await tester.tap(find.text('Save locally'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final tasks = await db.select(db.todoItems).get();
        expect(tasks.single.title, 'Review draft');
        expect(tasks.single.dueDate, DateTime(2026, 11, 2));
        expect(tasks.single.recurrenceRule, 'weekly');
        expect(tasks.single.priority, 1);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('swiping changes the viewed day', (tester) async {
      try {
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);

        await tester.fling(
          find.text('Your agenda'),
          const Offset(-300, 0),
          1000,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Tomorrow'), findsWidgets);
        expect(find.text('Agenda for Thu 29 Oct'), findsOneWidget);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('a habit can be edited and deleted with Undo', (tester) async {
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
        AppClock.now = () => DateTime(2026, 10, 28, 8);
        await pumpApp(tester);
        await tester.ensureVisible(find.byKey(const ValueKey('habit-h1')));

        await tester.tap(find.byTooltip('Habit actions'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Edit'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(
          find.byKey(const ValueKey('habit-name')),
          'Read more',
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect((await db.select(db.habits).get()).single.name, 'Read more');

        await tester.ensureVisible(find.byKey(const ValueKey('habit-h1')));
        await tester.tap(find.byTooltip('Habit actions'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Delete'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(await db.select(db.habits).get(), isEmpty);

        await tester.tap(find.text('Undo'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect((await db.select(db.habits).get()).single.name, 'Read more');
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
          find.byKey(const ValueKey('habit-name')),
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

    testWidgets('editing a task keeps its notes, dates and metadata', (
      tester,
    ) async {
      AppClock.now = () => DateTime(2026, 11, 1, 8);
      try {
        // A past reminder is preserved by the edit but arms no timer, so the
        // widget test does not end with a scheduled callback still pending.
        final reminderAt = DateTime(2026, 10, 31, 9);
        await db.addTodoItem(
          'Prepare report',
          DateTime(2026, 11, 3, 17),
          notes: 'Collect numbers',
          startDate: DateTime(2026, 11, 1, 9),
          priority: 3,
          tags: '["work"]',
          reminderAt: reminderAt,
        );
        await pumpApp(tester);

        await tester.tap(find.text('Tasks'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(find.text('Prepare report'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        await tester.enterText(
          find.byType(TextField).first,
          'Prepare final report',
        );
        await tester.tap(find.text('Save'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final task = await db.select(db.todoItems).getSingle();
        expect(task.title, 'Prepare final report');
        expect(task.notes, 'Collect numbers');
        expect(task.startDate, DateTime(2026, 11, 1, 9));
        expect(task.dueDate, DateTime(2026, 11, 3, 17));
        expect(task.priority, 3);
        expect(task.tags, '["work"]');
        expect(task.reminderAt, reminderAt);
      } finally {
        await closeApp(tester);
      }
    });

    testWidgets('subtasks and unscheduled tasks are shown distinctly', (
      tester,
    ) async {
      try {
        final parentId = await db.addTodoItem(
          'Plan week',
          DateTime(2026, 11, 2),
        );
        await db.addTodoItem('Pick goals', null, parentId: parentId);
        await pumpApp(tester);

        await tester.tap(find.text('Tasks'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Plan week'), findsOneWidget);
        expect(find.text('Pick goals'), findsOneWidget);
        expect(find.byIcon(Icons.subdirectory_arrow_right), findsOneWidget);
        expect(find.textContaining('Unscheduled'), findsOneWidget);
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
