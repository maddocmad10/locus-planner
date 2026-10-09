import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/dashboard/providers/dashboard_providers.dart';
import 'package:locus_planner/features/insights/providers/insights_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('dashboard stats refresh when planner data changes', () async {
    final updated = Completer<DashboardStats>();
    final subscription = container.listen(dashboardStatsProvider, (_, next) {
      if (next.hasValue &&
          next.value!.habitsTotal == 1 &&
          !updated.isCompleted) {
        updated.complete(next.value!);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: 'h1',
            name: 'Read',
            createdAt: DateTime.now(),
          ),
        );

    final stats = await updated.future.timeout(const Duration(seconds: 2));
    expect(stats.habitsTotal, 1);
  });

  test('insights summary refreshes when planner data changes', () async {
    final updated = Completer<InsightsSummary>();
    final subscription = container.listen(insightsSummaryProvider, (_, next) {
      if (next.hasValue &&
          next.value!.projects.length == 1 &&
          !updated.isCompleted) {
        updated.complete(next.value!);
      }
    }, fireImmediately: true);
    addTearDown(subscription.close);

    await db
        .into(db.projects)
        .insert(
          ProjectsCompanion.insert(
            id: 'p1',
            name: 'Project',
            createdAt: DateTime.now(),
          ),
        );

    final summary = await updated.future.timeout(const Duration(seconds: 2));
    expect(summary.projects, hasLength(1));
  });
}
