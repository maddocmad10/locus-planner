import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/features/planning_intelligence/data/planning_snapshot_repository.dart';
import 'package:locus_planner/features/planning_intelligence/domain/planning_models.dart';
import 'package:locus_planner/features/planning_intelligence/presentation/planning_page.dart';

void main() {
  testWidgets('planning page shows the suggestion, matrix and review tabs', (
    tester,
  ) async {
    const result = PlanningResult(
      suggestions: [],
      matrix: EisenhowerResult(
        doFirst: [],
        schedule: [],
        delegate: [],
        eliminate: [],
        urgencyWindowDays: 3,
      ),
      weeklyReview: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [planningResultProvider.overrideWith((ref) async => result)],
        child: const MaterialApp(home: PlanningPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Planning suggestions'), findsOneWidget);
    expect(find.text('No suggestions right now'), findsOneWidget);

    await tester.tap(find.text('Eisenhower'));
    await tester.pumpAndSettle();
    expect(find.text('Do first (0)'), findsOneWidget);
    expect(find.text('Schedule (0)'), findsOneWidget);

    await tester.tap(find.text('Weekly review'));
    await tester.pumpAndSettle();
    expect(find.text('No weekly data yet'), findsOneWidget);
  });
}
