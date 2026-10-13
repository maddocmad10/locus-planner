import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

final diaryRepositoryProvider = Provider<DiaryRepository>((ref) {
  return DiaryRepository(ref.watch(databaseProvider));
});

class DiaryRepository {
  DiaryRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<DiaryEntry>> watchAll() => _db.watchDiaryEntries();

  Future<DiaryEntry?> forDate(DateTime day) => _db.entryForDate(day);

  Future<int> streak() => _db.diaryStreak();

  Future<void> save({
    required DateTime date,
    required int mood,
    required String content,
  }) async {
    if (mood < 1 || mood > 5) {
      throw ArgumentError.value(mood, 'mood', 'must be between 1 and 5');
    }

    final d = DateTime(date.year, date.month, date.day);

    // Serialize the read/modify/write sequence. The diary table has a unique
    // constraint on date, not id. Without this transaction two concurrent
    // writers can both observe no existing row and create different ids,
    // causing a UNIQUE(date) failure before the id conflict handler runs.
    await _db.transaction(() async {
      final existing = await _db.entryForDate(d);

      await _db.into(_db.diaryEntries).insertOnConflictUpdate(
        DiaryEntriesCompanion(
          id: Value(existing?.id ?? _uuid.v4()),
          date: Value(d),
          mood: Value(mood),
          content: Value(content),
        ),
      );
    });
  }

  Future<void> saveReview({
    required String win,
    required String blocker,
    required String tomorrow,
  }) async {
    final today = DateTime.now();
    final content =
        '**Win:** $win\n\n**Blocker:** $blocker\n\n**Tomorrow:** $tomorrow';
    final existing = await _db.entryForDate(today);
    await save(
      date: today,
      mood: existing?.mood ?? 3,
      content: existing != null
          ? '${existing.content}\n\n---\n$content'
          : content,
    );
  }
}
