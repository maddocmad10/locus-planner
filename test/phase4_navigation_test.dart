import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/providers/navigation_provider.dart';
import 'package:locus_planner/features/command_palette/presentation/command_palette.dart';

void main() {
  test('planning is appended after calendar without renumbering', () {
    expect(NavPage.calendar, 10);
    expect(NavPage.planning, 11);
  });

  test('navigation state can move to the planning page', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(navigationIndexProvider.notifier).setIndex(NavPage.planning);
    expect(container.read(navigationIndexProvider), NavPage.planning);
  });

  testWidgets('the command palette offers and navigates to planning', (
    tester,
  ) async {
    int? selected;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CommandPalette(onNavigate: (index) => selected = index),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.text('Go to Planning'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Go to Planning'), findsOneWidget);
    await tester.tap(find.text('Go to Planning'));
    await tester.pump();

    expect(selected, NavPage.planning);
  });
}
