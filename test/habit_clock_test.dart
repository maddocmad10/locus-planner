// The 84-day habit window and the toggle/streak paths must follow the
// injected clock: a tray-resident app crosses midnight while it runs, and
// tests must be able to freeze time instead of racing the real calendar.
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/clock_provider.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/habits/data/habit_repository.dart';

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition was not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late DateTime now;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    now = DateTime(2026, 10, 5, 9);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        dayCheckIntervalProvider.overrideWithValue(
          const Duration(milliseconds: 20),
        ),
        databaseProvider.overrideWithValue(db),
      ],
    );
  });

  tearDown(() async {
    await container.dispose();
    await db.close();
  });

  Future<Habit> seedHabit() async {
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: 'h1',
            name: 'Read',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
    return (db.select(db.habits)..where((t) => t.id.equals('h1'))).getSingle();
  }

  test("toggleToday writes the log under the clock's today", () async {
    // Freeze a date far from the machine's real today: if the repository
    // still read DateTime.now() internally, this would write the wrong day.
    now = DateTime(2024, 3, 10, 8);
    final repo = container.read(habitRepositoryProvider);
    final habit = await seedHabit();

    await repo.toggleToday(habit, false);

    final logs = await (db.select(
      db.habitLogs,
    )..where((t) => t.habitId.equals(habit.id))).get();
    expect(logs, hasLength(1));
    expect(logs.single.date, DateTime(2024, 3, 10));
  });

  test('the 84-day window follows the clock across midnight', () async {
    final habit = await seedHabit();
    await db
        .into(db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: 'l1',
            habitId: habit.id,
            date: DateTime(2026, 10, 5),
          ),
        );

    List<HabitLog> window() =>
        container.read(habitLogsLast84DaysProvider).valueOrNull ??
        const <HabitLog>[];
    await eventually(() => window().any((l) => l.id == 'l1'));

    // Cross midnight: the day-change heartbeat re-emits, the provider
    // re-derives its window from the clock, and a log written on the new
    // day becomes visible. The old window ended at Oct 6, so this also
    // proves the query itself was rebuilt, not just re-emitted.
    now = DateTime(2026, 10, 6, 0, 1);
    await db
        .into(db.habitLogs)
        .insert(
          HabitLogsCompanion.insert(
            id: 'l2',
            habitId: habit.id,
            date: DateTime(2026, 10, 6),
          ),
        );
    await eventually(() => window().any((l) => l.id == 'l2'));
  });

  test('the streak counts history older than the 84-day window', () async {
    final habit = await seedHabit();
    // 100 consecutive completed days ending on the frozen "today"; only the
    // last 84 can ever fit the heatmap window.
    for (var i = 0; i < 100; i++) {
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion.insert(
              id: 'l$i',
              habitId: habit.id,
              date: DateTime(2026, 10, 5).subtract(Duration(days: i)),
            ),
          );
    }

    final streak = await container.read(habitStreakProvider(habit.id).future);
    expect(streak, 100);
  });
}
