import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/main.dart';

void main() {
  testWidgets('startup error screen exposes an exit action', (tester) async {
    await tester.pumpWidget(
      const StartupErrorApp(error: 'startup failed', backupsPath: 'backups'),
    );

    expect(find.text('Locus could not start'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Exit'), findsOneWidget);
  });
}
