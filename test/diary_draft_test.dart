import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/diary/data/diary_repository.dart';
import 'package:locus_planner/features/diary/presentation/diary_page.dart';

void main() {
  late AppDatabase db;
  late DiaryRepository repository;
  late DateTime Function() originalClock;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    repository = DiaryRepository(db);
    originalClock = AppClock.now;
    AppClock.now = () => DateTime(2026, 11, 1, 12);
  });

  tearDown(() async {
    AppClock.now = originalClock;
    await db.close();
  });

  test('drafts save, load and clear', () async {
    expect(await repository.loadDraft(), isNull);
    await repository.saveDraft(
      date: DateTime(2026, 11, 1, 18),
      mood: 4,
      text: 'Unsaved thoughts',
    );

    final draft = await repository.loadDraft();
    expect(draft, isNotNull);
    expect(draft!.date, DateTime(2026, 11, 1));
    expect(draft.mood, 4);
    expect(draft.text, 'Unsaved thoughts');

    await repository.clearDraft();
    expect(await repository.loadDraft(), isNull);
  });

  test('the draft is transient and never exported', () async {
    expect(
      AppDatabase.isTransientSetting(AppDatabase.diaryDraftSettingKey),
      isTrue,
    );
    await repository.saveDraft(
      date: DateTime(2026, 11, 1),
      mood: 3,
      text: 'A secret draft',
    );
    final backup = await DataExportService(db).buildBackupJson();
    expect(backup, isNot(contains('A secret draft')));
    expect(backup, isNot(contains(AppDatabase.diaryDraftSettingKey)));
  });

  testWidgets('an existing draft is recovered with Keep and Discard', (
    tester,
  ) async {
    await repository.saveDraft(
      date: DateTime(2026, 11, 1),
      mood: 5,
      text: 'Recovered draft text',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DiaryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Recovered unsaved draft'), findsOneWidget);
    expect(find.text('Recovered draft text'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pump();
    expect(find.text('Recovered unsaved draft'), findsNothing);
    expect(find.text('Recovered draft text'), findsNothing);
    expect(await repository.loadDraft(), isNull);
  });

  testWidgets('saving clears the draft', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: DiaryPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), 'A saved entry');
    await tester.pump(const Duration(milliseconds: 1100));
    expect(await repository.loadDraft(), isNotNull);

    await tester.tap(find.text('Save Entry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(await repository.loadDraft(), isNull);
    expect(
      (await repository.forDate(DateTime(2026, 11, 1)))!.content,
      'A saved entry',
    );
  });
}
