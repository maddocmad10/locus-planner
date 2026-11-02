import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';

/// An unsaved diary editor state, kept in a transient setting so a crash or a
/// forced process kill does not lose the text.
class DiaryDraft {
  const DiaryDraft({
    required this.date,
    required this.mood,
    required this.text,
  });

  final DateTime date;
  final int mood;
  final String text;

  Map<String, dynamic> toJson() => {
    'date': _dayKey(date),
    'mood': mood,
    'text': text,
  };

  static DiaryDraft? fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final mood = json['mood'];
    final text = json['text'];
    if (date is! String || mood is! int || text is! String) return null;
    final parsed = DateTime.tryParse(date);
    if (parsed == null || mood < 1 || mood > 5) return null;
    return DiaryDraft(
      date: DateTime(parsed.year, parsed.month, parsed.day),
      mood: mood,
      text: text,
    );
  }

  static String _dayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

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

  Future<DiaryDraft?> loadDraft() async {
    final raw = await _db.getSetting(AppDatabase.diaryDraftSettingKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return DiaryDraft.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveDraft({
    required DateTime date,
    required int mood,
    required String text,
  }) async {
    await _db.setSetting(
      AppDatabase.diaryDraftSettingKey,
      jsonEncode(DiaryDraft(date: date, mood: mood, text: text).toJson()),
    );
  }

  Future<void> clearDraft() =>
      _db.deleteSetting(AppDatabase.diaryDraftSettingKey);

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

      await _db
          .into(_db.diaryEntries)
          .insertOnConflictUpdate(
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
    final today = AppClock.now();
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
