import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/features/diary/data/diary_repository.dart';

void main() {
  late AppDatabase db;
  late DiaryRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DiaryRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('concurrent diary saves do not create duplicate entries', () async {
    await Future.wait([
      repository.save(date: DateTime(2026, 1, 1), mood: 3, content: 'first'),
      repository.save(date: DateTime(2026, 1, 1), mood: 4, content: 'second'),
    ]);

    final entries = await db.select(db.diaryEntries).get();

    expect(entries.length, 1);
  });
}
