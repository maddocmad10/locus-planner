import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/auto_backup_service.dart';
import 'package:locus_planner/core/services/backup_encryption_service.dart';
import 'package:locus_planner/core/services/crypto/encrypted_envelope.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

Future<Uint8List> _derive(
  String secret,
  Uint8List salt,
  int iterations,
) async => KeyDerivation.deriveSync(secret, salt, iterations);

class _MemoryPassphraseStore implements BackupPassphraseStore {
  String? value;
  bool failReads = false;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('vault unavailable');
    return value;
  }

  @override
  Future<void> write(String newValue) async => value = newValue;

  @override
  Future<void> delete() async => value = null;
}

void main() {
  late AppDatabase db;
  late Directory dir;
  late _MemoryPassphraseStore store;
  late BackupEncryptionService encryption;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    await db
        .into(db.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            id: 'd1',
            date: DateTime(2026, 11, 1),
            mood: 3,
            content: 'A very private diary line',
          ),
        );
    dir = await Directory.systemTemp.createTemp('locus-backup-enc-');
    store = _MemoryPassphraseStore();
    encryption = BackupEncryptionService(store: store);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  DataExportService service() => DataExportService(
    db,
    backupDirectory: dir,
    backupEncryption: encryption,
    derive: _derive,
  );

  test('without a passphrase automatic backups stay plain JSON', () async {
    final backup = await service().buildAutomaticBackup();
    expect(backup.extension, '.json');
    expect(backup.content, contains('A very private diary line'));
  });

  test('a configured passphrase produces an encrypted backup', () async {
    await encryption.setPassphrase('correct horse battery');
    final backup = await service().buildAutomaticBackup();
    expect(backup.extension, '.locusbackup');
    expect(backup.content, isNot(contains('A very private diary line')));
    expect(EncryptedEnvelope.looksEncrypted(backup.content), isTrue);

    final opened = await EncryptedEnvelope.open(
      backup.content,
      'correct horse battery',
      derive: _derive,
    );
    expect(opened.payloadType, EncryptedEnvelope.payloadFullBackup);
    expect(opened.plaintext, contains('A very private diary line'));
  });

  test('a failing passphrase store fails closed and writes no file', () async {
    store.failReads = true;
    await expectLater(
      service().createRecoveryBackup(),
      throwsA(isA<StateError>()),
    );
    expect(await dir.list().toList(), isEmpty);
  });

  test('recovery backups follow the encryption setting', () async {
    final plain = await service().createRecoveryBackup();
    expect(plain, endsWith('.json'));

    await encryption.setPassphrase('correct horse battery');
    final encrypted = await service().createRecoveryBackup();
    expect(encrypted, endsWith('.locusbackup'));
    final content = await File(encrypted).readAsString();
    expect(content, isNot(contains('A very private diary line')));
  });

  test('deleteUnencryptedBackups removes only old plain JSON files', () async {
    final plain = File('${dir.path}${Platform.pathSeparator}auto_old.json');
    final manual = File(
      '${dir.path}${Platform.pathSeparator}pre_import_old.json',
    );
    final encrypted = File(
      '${dir.path}${Platform.pathSeparator}auto_old.locusbackup',
    );
    final unrelated = File('${dir.path}${Platform.pathSeparator}notes.json');
    for (final file in [plain, manual, encrypted, unrelated]) {
      await file.writeAsString('{}');
    }

    final deleted = await service().deleteUnencryptedBackups();
    expect(deleted, 2);
    expect(await plain.exists(), isFalse);
    expect(await manual.exists(), isFalse);
    expect(await encrypted.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('readBackupFile retries a wrong passphrase', () async {
    final plain = await service().buildBackupJson();
    final document = await EncryptedEnvelope.seal(
      plain,
      'correct horse battery',
      payloadType: EncryptedEnvelope.payloadFullBackup,
      derive: _derive,
    );
    final file = File('${dir.path}${Platform.pathSeparator}backup.locusbackup');
    await file.writeAsString(document);

    final answers = <String>[
      'wrong one',
      'still wrong',
      'correct horse battery',
    ];
    var index = 0;
    final text = await service().readBackupFile(
      file,
      prompt: (_) async => answers[index++],
    );
    expect(text, contains('A very private diary line'));
    expect(index, 3);
  });

  test(
    'automatic backup writes the chosen extension and prunes to seven',
    () async {
      await encryption.setPassphrase('correct horse battery');
      for (var i = 0; i < 10; i++) {
        final extension = i.isEven ? '.json' : '.locusbackup';
        await File(
          '${dir.path}${Platform.pathSeparator}auto_old_$i$extension',
        ).writeAsString('{}');
      }

      await AutoBackupService(db, service(), backupDirectory: dir).runIfDue();

      final files = await dir
          .list()
          .where((entity) => entity is File && entity.path.contains('auto_'))
          .toList();
      expect(files, hasLength(7));
      final newest = files.whereType<File>().where(
        (file) => file.path.endsWith('.locusbackup'),
      );
      expect(newest, isNotEmpty);
      final stored = await db.getSetting(AppDatabase.lastAutoBackupSettingKey);
      expect(stored, isNotNull);
    },
  );

  test('automatic backup fails closed when the store cannot be read', () async {
    store.failReads = true;
    await expectLater(
      AutoBackupService(db, service(), backupDirectory: dir).runIfDue(),
      throwsA(isA<StateError>()),
    );
    final files = await dir.list().toList();
    expect(files, isEmpty);
  });

  test('the sealed full backup is valid JSON after opening', () async {
    await encryption.setPassphrase('correct horse battery');
    final backup = await service().buildAutomaticBackup();
    final opened = await EncryptedEnvelope.open(
      backup.content,
      'correct horse battery',
      derive: _derive,
    );
    final decoded = jsonDecode(opened.plaintext) as Map<String, dynamic>;
    expect(decoded['format_version'], 4);
    expect(decoded['backup_encryption'], contains('locus.encrypted'));
    expect(decoded['payload_sha256'], isA<String>());
    expect(decoded['tables'], isA<Map<String, dynamic>>());
  });
}
