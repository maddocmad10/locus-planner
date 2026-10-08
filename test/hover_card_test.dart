import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/widgets/hover_card.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('a tap activates the card', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        HoverCard(
          onTap: () => taps++,
          padding: const EdgeInsets.all(16),
          child: const Text('Card'),
        ),
      ),
    );
    await tester.tap(find.text('Card'));
    expect(taps, 1);
  });

  testWidgets('the keyboard can focus and activate the card', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(HoverCard(onTap: () => taps++, child: const Text('Card'))),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('buttons inside the card still get their own taps', (tester) async {
    var cardTaps = 0;
    var buttonTaps = 0;
    await tester.pumpWidget(
      _app(
        HoverCard(
          onTap: () => cardTaps++,
          child: TextButton(onPressed: () => buttonTaps++, child: const Text('Inner')),
        ),
      ),
    );
    await tester.tap(find.text('Inner'));
    expect(buttonTaps, 1);
    expect(cardTaps, 0);
  });

  testWidgets('without onTap it is not an interactive target', (tester) async {
    await tester.pumpWidget(_app(const HoverCard(child: Text('Static'))));
    expect(find.byType(InkWell), findsNothing);
    expect(find.text('Static'), findsOneWidget);
  });
}
