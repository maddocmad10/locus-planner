import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

void main() {
  late AppDatabase db;
  late Directory dir;

  setUp(() async {
    DatabaseSecurity.reset();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.diaryEntries)
        .insert(
          DiaryEntriesCompanion.insert(
            id: 'd1',
            date: DateTime(2026, 11, 1),
            mood: 3,
            content: 'A private line',
          ),
        );
    dir = await Directory.systemTemp.createTemp('locus-backup-v3-');
  });

  tearDown(() async {
    DatabaseSecurity.reset();
    await db.close();
    await dir.delete(recursive: true);
  });

  DataExportService service() => DataExportService(db, backupDirectory: dir);

  Map<String, dynamic> decodeBackup(String source) =>
      jsonDecode(source) as Map<String, dynamic>;

  test('buildBackupJson writes a v4 manifest and checksums', () async {
    final decoded = decodeBackup(await service().buildBackupJson());

    expect(decoded['format_version'], 4);
    expect(
      decoded['database_schema_version'],
      AppDatabase.currentSchemaVersion,
    );
    expect(decoded['payload_sha256'], isA<String>());
    final tables = decoded['tables'] as Map<String, dynamic>;
    expect(tables.keys, containsAll(<String>['diary_entries', 'tasks']));
    final diary = tables['diary_entries'] as Map<String, dynamic>;
    expect(diary['rows'], 1);
    expect(diary['sha256'], isA<String>());
    expect((decoded['diary_entries'] as List), hasLength(1));

    final plan = BackupImportPlan.parse(jsonEncode(decoded));
    expect(plan.counts['diary_entries'], 1);
  });

  test('an edited row fails the payload checksum', () async {
    final decoded = decodeBackup(await service().buildBackupJson());
    final rows = decoded['diary_entries'] as List<dynamic>;
    (rows.single as Map<String, dynamic>)['content'] = 'edited';

    expect(
      () => BackupImportPlan.parse(jsonEncode(decoded)),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
  });

  test('an edited table manifest fails verification', () async {
    final decoded = decodeBackup(await service().buildBackupJson());
    final tables = decoded['tables'] as Map<String, dynamic>;
    final diary = tables['diary_entries'] as Map<String, dynamic>;
    diary['rows'] = 2;

    expect(
      () => BackupImportPlan.parse(jsonEncode(decoded)),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'recovery backups are written durably and are valid v4 documents',
    () async {
      final path = await service().writeRecoveryBackup(directory: dir);
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(file.path, contains('manual_'));
      expect(file.path, endsWith('.json'));
      expect(decodeBackup(await file.readAsString())['format_version'], 4);

      final leftovers = dir.listSync().where(
        (entity) => entity.path.contains('.tmp-'),
      );
      expect(leftovers, isEmpty);
    },
  );

  test('automatic backups fail closed when encryption is required', () async {
    DatabaseSecurity.configure(
      DatabaseSecurityOptions.encrypted(keyStore: InMemoryDatabaseKeyStore()),
    );

    await expectLater(
      service().buildAutomaticBackup(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('must be encrypted'),
        ),
      ),
    );
  });

  test(
    'cleanup removes plaintext copies but keeps encrypted backups',
    () async {
      final dataDir = Directory('${dir.path}${Platform.pathSeparator}data');
      final backupsDir = Directory(
        '${dataDir.path}${Platform.pathSeparator}backups',
      );
      await backupsDir.create(recursive: true);
      final localService = DataExportService(db, backupDirectory: backupsDir);

      final preMigration = File(
        '${dataDir.path}${Platform.pathSeparator}'
        'legacy.db.pre-migration-v16-test.bak',
      );
      await preMigration.writeAsString('plaintext');
      final preEncryptionDir = Directory(
        '${backupsDir.path}${Platform.pathSeparator}pre-encryption',
      );
      await preEncryptionDir.create(recursive: true);
      final preEncryption = File(
        '${preEncryptionDir.path}${Platform.pathSeparator}'
        'legacy.db.pre-encryption-1.plaintext.bak',
      );
      await preEncryption.writeAsString('plaintext');
      final encrypted = File(
        '${backupsDir.path}${Platform.pathSeparator}auto_keep.locusbackup',
      );
      await encrypted.writeAsString('encrypted');
      final unrelated = File(
        '${backupsDir.path}${Platform.pathSeparator}notes.json',
      );
      await unrelated.writeAsString('{}');

      final deleted = await localService.deleteUnencryptedBackups();

      expect(deleted, 2);
      expect(await preMigration.exists(), isFalse);
      expect(await preEncryption.exists(), isFalse);
      expect(await encrypted.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );
}
