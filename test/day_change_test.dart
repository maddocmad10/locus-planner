import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/clock_provider.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/dashboard/providers/dashboard_providers.dart';

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition was not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late DateTime now;

  ProviderContainer containerWith(AppDatabase? db) => ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now),
      dayCheckIntervalProvider.overrideWithValue(
        const Duration(milliseconds: 20),
      ),
      if (db != null) databaseProvider.overrideWithValue(db),
    ],
  );

  test(
    'dayChangeProvider emits again when the clock passes midnight',
    () async {
      now = DateTime(2026, 10, 5, 23, 59);
      final container = containerWith(null);
      addTearDown(container.dispose);

      final days = <DateTime>[];
      container.listen(dayChangeProvider, (_, next) {
        final day = next.valueOrNull;
        if (day != null) days.add(day);
      }, fireImmediately: true);

      await eventually(() => days.isNotEmpty);
      expect(days.last, DateTime(2026, 10, 5));

      now = DateTime(2026, 10, 6, 0, 1);
      await eventually(() => days.last == DateTime(2026, 10, 6));
    },
  );

  test('it does not re-emit while the day stays the same', () async {
    now = DateTime(2026, 10, 5, 9);
    final container = containerWith(null);
    addTearDown(container.dispose);

    var emissions = 0;
    container.listen(dayChangeProvider, (_, next) {
      if (next.hasValue) emissions++;
    }, fireImmediately: true);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    now = DateTime(2026, 10, 5, 21);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(emissions, 1);
  });

  test("today's events follow the clock across midnight", () async {
    now = DateTime(2026, 10, 5, 12);
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'a',
            title: 'Monday',
            startTime: DateTime(2026, 10, 5, 9),
          ),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'b',
            title: 'Tuesday',
            startTime: DateTime(2026, 10, 6, 9),
          ),
        );

    final container = containerWith(db);
    addTearDown(container.dispose);

    var titles = <String>[];
    container.listen(todayEventsProvider, (_, next) {
      final items = next.valueOrNull;
      if (items != null) titles = [for (final i in items) i.event.title];
    }, fireImmediately: true);

    await eventually(() => titles.contains('Monday'));
    expect(titles, ['Monday']);

    now = DateTime(2026, 10, 6, 0, 5);
    await eventually(() => titles.contains('Tuesday'));
    expect(titles, ['Tuesday']);
  });
}
