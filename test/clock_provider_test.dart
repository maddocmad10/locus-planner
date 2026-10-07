import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/clock_provider.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/dashboard/providers/dashboard_providers.dart';

void main() {
  test('dashboard stats use fake clock', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.events).insert(
      EventsCompanion.insert(
        id: 'today',
        title: 'Today',
        startTime: DateTime(2024, 1, 1, 9),
      ),
    );
    await db.into(db.events).insert(
      EventsCompanion.insert(
        id: 'tomorrow',
        title: 'Tomorrow',
        startTime: DateTime(2024, 1, 2, 9),
      ),
    );

    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime(2024, 1, 1)),
        dayCheckIntervalProvider.overrideWithValue(
          const Duration(hours: 1),
        ),
      ],
    );
    addTearDown(container.dispose);

    // Keep the auto-dispose provider alive while its stream initializes.
    final subscription = container.listen(
      dashboardStatsProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final stats = await container.read(dashboardStatsProvider.future);

    expect(stats.eventsToday, 1);
  });
}
