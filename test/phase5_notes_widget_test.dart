import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:locus_planner/core/providers/service_providers.dart';
import 'package:locus_planner/core/widgets/attachment_strip.dart';
import 'package:locus_planner/core/widgets/notes_field.dart';

String _selectablePlainText(WidgetTester tester) {
  return tester
      .widgetList<SelectableText>(find.byType(SelectableText))
      .map((widget) => widget.textSpan?.toPlainText() ?? widget.data ?? '')
      .join('\n');
}

void main() {
  testWidgets('md1 renders emphasis, tasks and image references', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Md1Text(
            '# Heading\n\n'
            'Some **bold**, *italic* and ~~gone~~ text.\n\n'
            '- [x] Done\n'
            '- [ ] Open\n\n'
            '![Diagram](locus-att://attachment-1)',
          ),
        ),
      ),
    );

    final plain = _selectablePlainText(tester);
    expect(plain, contains('Heading'));
    expect(plain, contains('bold'));
    expect(plain, contains('italic'));
    expect(plain, contains('gone'));
    expect(plain, contains('Done'));
    expect(plain, contains('Open'));
    expect(plain, contains('Image: Diagram'));
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
  });

  testWidgets('a local locus-att image resolves to an inline preview', (
    tester,
  ) async {
    final png = img.encodePng(img.Image(width: 2, height: 2));
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md1Text(
            '![Diagram](locus-att://attachment-1)',
            imageResolver: (id) async {
              requested = id;
              return png;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requested, 'attachment-1');
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a missing local attachment keeps a labelled placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Md1Text(
            '![Diagram](locus-att://attachment-1)',
            imageResolver: (id) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_selectablePlainText(tester), contains('Image: Diagram'));
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('raw HTML is shown as text, never interpreted', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Md1Text('<b>unsafe</b>'))),
    );

    expect(_selectablePlainText(tester), contains('<b>unsafe</b>'));
  });

  testWidgets('preview marks a plain note as md1', (tester) async {
    final controller = TextEditingController(text: '**bold** note');
    addTearDown(controller.dispose);
    var format = 'plain';

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          home: Scaffold(
            body: NotesField(
              controller: controller,
              format: format,
              onFormatChanged: (value) => setState(() => format = value),
            ),
          ),
        ),
      ),
    );

    expect(format, 'plain');
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(format, 'md1');
    expect(_selectablePlainText(tester), contains('bold note'));
  });

  testWidgets('a new item explains that it must be saved first', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AttachmentStrip())),
    );

    expect(find.textContaining('Save this item first'), findsOneWidget);
  });

  testWidgets('a failed attachment service offers a retry', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          attachmentServiceProvider.overrideWith(
            (ref) async => throw StateError('no key'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: AttachmentStrip(todoId: 'todo-1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Attachments are unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
