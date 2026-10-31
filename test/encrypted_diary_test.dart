import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/encrypted_diary_service.dart';
import 'package:locus_planner/core/utils/day_math.dart';

void main() {
  late AppDatabase db;
  late EncryptedDiaryService service;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    service = EncryptedDiaryService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addEntry(
    String id,
    DateTime day,
    String content, {
    int mood = 3,
  }) => db
      .into(db.diaryEntries)
      .insert(
        DiaryEntriesCompanion.insert(
          id: id,
          date: day,
          mood: mood,
          content: content,
        ),
      );

  Future<DiaryEntry?> entryOn(DateTime day) => (db.select(
    db.diaryEntries,
  )..where((t) => t.date.equals(DayMath.dateOnly(day)))).getSingleOrNull();

  test('round-trips diary entries without exposing their text', () async {
    await addEntry('d1', DateTime(2026, 10, 30), 'A very private day');
    await addEntry('d2', DateTime(2026, 10, 31), 'Another secret', mood: 5);

    final document = await service.buildEncryptedExport('correct horse');

    expect(document, isNot(contains('A very private day')));
    expect(document, isNot(contains('Another secret')));
    final envelope = jsonDecode(document) as Map<String, dynamic>;
    expect(envelope['format'], EncryptedDiaryService.format);
    expect(envelope['cipher'], 'AES-256-GCM');
    expect((envelope['kdf'] as Map)['algorithm'], 'PBKDF2-HMAC-SHA256');
    expect((envelope['kdf'] as Map)['iterations'], 210000);
    expect(base64Decode(envelope['nonce'] as String), hasLength(12));

    await db.delete(db.diaryEntries).go();
    final report = await service.restoreFromEncrypted(
      document: document,
      passphrase: 'correct horse',
    );

    expect(report.restored, 2);
    expect(report.skipped, 0);
    expect(
      (await entryOn(DateTime(2026, 10, 30)))!.content,
      'A very private day',
    );
    expect((await entryOn(DateTime(2026, 10, 31)))!.content, 'Another secret');
    expect((await entryOn(DateTime(2026, 10, 31)))!.mood, 5);
  });

  test('a wrong passphrase cannot decrypt the backup', () async {
    await addEntry('d1', DateTime(2026, 10, 30), 'A very private day');
    final document = await service.buildEncryptedExport('correct horse');

    await expectLater(
      service.restoreFromEncrypted(
        document: document,
        passphrase: 'wrong horse',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('passphrase is wrong'),
        ),
      ),
    );
  });

  test('tampering with the ciphertext is detected', () async {
    await addEntry('d1', DateTime(2026, 10, 30), 'A very private day');
    final document = await service.buildEncryptedExport('correct horse');
    final envelope = jsonDecode(document) as Map<String, dynamic>;
    final bytes = base64Decode(envelope['ciphertext'] as String);
    bytes[0] ^= 1;
    envelope['ciphertext'] = base64Encode(bytes);

    await expectLater(
      service.restoreFromEncrypted(
        document: jsonEncode(envelope),
        passphrase: 'correct horse',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('a plain JSON backup is rejected', () async {
    await expectLater(
      service.restoreFromEncrypted(
        document: '{"format":"locus.diary-backup","version":1}',
        passphrase: 'whatever',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('not an encrypted'),
        ),
      ),
    );
  });

  test('restore merges by date and keeps unrelated diary entries', () async {
    await addEntry('old-1', DateTime(2026, 10, 28), 'before backup');
    await addEntry('old-2', DateTime(2026, 10, 29), 'will be replaced');
    await addEntry('keep', DateTime(2026, 10, 27), 'not in backup');
    final document = await service.buildEncryptedExport('passphrase');

    // After exporting, change the backup-covered day and add an unrelated one.
    await (db.update(db.diaryEntries)..where((t) => t.id.equals('old-2')))
        .write(const DiaryEntriesCompanion(content: Value('changed later')));
    await addEntry('other', DateTime(2026, 10, 31), 'newer local entry');

    final report = await service.restoreFromEncrypted(
      document: document,
      passphrase: 'passphrase',
    );

    expect(report.restored, 3);
    expect((await entryOn(DateTime(2026, 10, 28)))!.content, 'before backup');
    expect(
      (await entryOn(DateTime(2026, 10, 29)))!.content,
      'will be replaced',
    );
    expect((await entryOn(DateTime(2026, 10, 27)))!.content, 'not in backup');
    expect(
      (await entryOn(DateTime(2026, 10, 31)))!.content,
      'newer local entry',
    );
  });

  test('an empty passphrase is refused', () async {
    await expectLater(
      service.buildEncryptedExport('   '),
      throwsA(isA<FormatException>()),
    );
  });
}
