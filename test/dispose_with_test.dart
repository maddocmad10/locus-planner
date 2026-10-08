import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/widgets/dispose_with.dart';

void main() {
  testWidgets('controllers outlive the dialog closing animation, then are disposed', (tester) async {
    late TextEditingController controller;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  controller = TextEditingController(text: 'hello');
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => DisposeWith(
                      disposables: [controller],
                      child: AlertDialog(
                        content: TextField(controller: controller, autofocus: true),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed');

    await tester.tap(find.text('Close'));
    await tester.pump(); // popped; the closing animation is now running
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-animation the TextField is still on screen and still uses it.
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    void noop() {}
    controller.addListener(noop); // throws if already disposed
    controller.removeListener(noop);
    expect(controller.text, 'typed');

    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(() => controller.addListener(noop), throwsFlutterError);
  });
}
