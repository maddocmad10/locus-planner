import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/providers/navigation_provider.dart';
import 'package:locus_planner/features/command_palette/presentation/command_palette.dart';

void main() {
  test('calendar is appended without renumbering existing pages', () {
    expect(NavPage.dashboard, 0);
    expect(NavPage.myDay, 1);
    expect(NavPage.events, 2);
    expect(NavPage.projects, 3);
    expect(NavPage.tasks, 4);
    expect(NavPage.habits, 5);
    expect(NavPage.focus, 6);
    expect(NavPage.diary, 7);
    expect(NavPage.insights, 8);
    expect(NavPage.settings, 9);
    expect(NavPage.calendar, 10);
    expect(NavPage.planning, 11);
  });

  test('navigation state can move to the calendar page', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(navigationIndexProvider), NavPage.dashboard);
    container.read(navigationIndexProvider.notifier).setIndex(NavPage.calendar);
    expect(container.read(navigationIndexProvider), NavPage.calendar);
  });

  testWidgets('the command palette offers and navigates to the calendar', (
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
      find.text('Go to Calendar'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Go to Calendar'), findsOneWidget);
    await tester.tap(find.text('Go to Calendar'));
    await tester.pump();

    expect(selected, NavPage.calendar);
  });
}
