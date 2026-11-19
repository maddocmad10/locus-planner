import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/database_bootstrap.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_metadata.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/security/logical_restore_service.dart';
import 'package:locus_planner/core/security/recovery_restore_service.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';
import 'package:locus_planner/core/services/attachments/attachment_key_store.dart';
import 'package:locus_planner/core/services/crypto/encrypted_envelope.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:path/path.dart' as p;

bool _runtimeSupported() {
  if (Platform.isAndroid) return true;
  if (!Platform.isWindows) return false;
  return File(
    p.join(
      Directory.current.path,
      'third_party',
      'sqlite3mc',
      'windows',
      Sqlite3mcLoader.windowsFileName,
    ),
  ).existsSync();
}

Future<DatabasePaths> _newEncryptedInstall(
  Directory directory,
  InMemoryDatabaseKeyStore keyStore,
) async {
  DatabaseSecurity.configure(
    DatabaseSecurityOptions.encrypted(
      dataDirectory: directory,
      keyStore: keyStore,
    ),
  );
  final executor = await DatabaseBootstrap.open();
  await executor.close();
  DatabaseRuntimeContext.current = null;
  return DatabasePathsResolver.resolve();
}

Future<String> _sourceBackup() async {
  final source = AppDatabase.forTesting(NativeDatabase.memory());
  try {
    await source.addTodoItem('Restored task', null);
    await source.setSetting('theme_mode', 'dark');
    return await DataExportService(source).buildBackupJson();
  } finally {
    await source.close();
  }
}

void main() {
  final supported = _runtimeSupported();
  if (supported) Sqlite3mcLoader.ensureConfigured();

  group('C2 logical restore', () {
    late Directory directory;
    late InMemoryDatabaseKeyStore keyStore;
    late InMemoryAttachmentKeyStore attachmentKeyStore;
    late DatabasePaths paths;
    late DatabaseMetadata previousMetadata;

    setUp(() async {
      if (!supported) return;
      directory = await Directory.systemTemp.createTemp('locus-logical-');
      keyStore = InMemoryDatabaseKeyStore();
      attachmentKeyStore = InMemoryAttachmentKeyStore();
      paths = await _newEncryptedInstall(directory, keyStore);
      previousMetadata = (await DatabaseMetadataStore(
        paths.metadataFile,
      ).read())!;
    });

    tearDown(() async {
      DatabaseRuntimeContext.current = null;
      DatabaseSecurity.reset();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    Future<File> writeBackup(String json, {String name = 'backup.json'}) async {
      final file = File(p.join(directory.path, name));
      await file.writeAsString(json, flush: true);
      return file;
    }

    test('stages a new encrypted identity and applies it on restart', () async {
      if (!supported) return;
      final json = await _sourceBackup();
      final backup = await writeBackup(json);
      final plan = BackupImportPlan.parse(json);

      final result = await const LogicalRestoreService().stage(
        paths: paths,
        backup: backup,
        passphrase: null,
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
      );
      expect(result.report.isClean, isTrue);
      expect(await keyStore.readStaged(result.journal.keyId), isNotNull);

      final applied = await const RecoveryRestoreService().applyStagedLocked(
        paths: paths,
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
      );
      expect(applied, isTrue);

      final metadata = (await DatabaseMetadataStore(
        paths.metadataFile,
      ).read())!;
      expect(metadata.databaseId, isNot(previousMetadata.databaseId));
      expect(metadata.activeKeyId, result.journal.keyId);
      expect(metadata.keyGeneration, previousMetadata.keyGeneration + 1);
      expect(await keyStore.read(metadata.activeKeyId), isNotNull);

      final key = await keyStore.read(metadata.activeKeyId);
      final db = SqliteRuntime.open(paths.databaseFile.path);
      try {
        SqliteCipherRuntime.applyKey(db, CipherProfiles.active, key!.bytes);
        expect(
          db.select('SELECT title FROM todo_items').map((row) => row['title']),
          contains('Restored task'),
        );
        final settings = <String, String>{
          for (final row in db.select('SELECT key, value FROM app_settings'))
            row['key'] as String: row['value'] as String,
        };
        expect(settings['sync.device_id'], isNotEmpty);
        expect(settings['sync.epoch'], isNotEmpty);
        expect(settings['sync.rebase_required'], '1');
        expect(settings['sync.server.enabled'], '0');
        expect(settings['sync.server.paired_clients'], '[]');
        expect(settings['restore.generation'], '1');
        expect(settings['restore.timestamp'], isNotEmpty);
        expect(settings['restore.source_backup_sha256'], isNotEmpty);
        expect(
          db
              .select('SELECT COUNT(*) AS count FROM sync_outbox')
              .single['count'],
          0,
        );
        final outbox = db.select('SELECT COUNT(*) AS count FROM sync_outbox');
        expect(outbox.single['count'], 0);
        expect(settings['theme_mode'], 'dark');
      } finally {
        db.dispose();
      }

      expect(plan.counts['todo_items'], greaterThan(0));
      final quarantine = Directory(paths.quarantineDirectory.path);
      expect(await quarantine.exists(), isTrue);
      expect(
        await quarantine
            .list(recursive: true)
            .where((entity) => entity is File)
            .any(
              (entity) =>
                  p.basename(entity.path) ==
                  p.basename(paths.databaseFile.path),
            ),
        isTrue,
      );

      DatabaseRuntimeContext.current = null;
      final reopened = await DatabaseBootstrap.open();
      expect(DatabaseSecurity.actualEncryptionEnabled, isTrue);
      await reopened.close();
    });

    test('an encrypted backup needs the right passphrase', () async {
      if (!supported) return;
      final json = await _sourceBackup();
      final encrypted = await EncryptedEnvelope.seal(
        json,
        'backup passphrase',
        payloadType: EncryptedEnvelope.payloadFullBackup,
        iterations: 210000,
      );
      final backup = await writeBackup(encrypted, name: 'backup.locusbackup');

      await expectLater(
        const LogicalRestoreService().stage(
          paths: paths,
          backup: backup,
          passphrase: 'wrong passphrase',
          keyStore: keyStore,
          attachmentKeyStore: attachmentKeyStore,
        ),
        throwsA(isA<Object>()),
      );
      expect(await File(paths.restoreJournalFile.path).exists(), isFalse);

      final result = await const LogicalRestoreService().stage(
        paths: paths,
        backup: backup,
        passphrase: 'backup passphrase',
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
      );
      expect(result.journal.databaseId, isNotEmpty);
    });

    test('unencrypted backups do not need a passphrase', () async {
      if (!supported) return;
      final json = await _sourceBackup();
      final backup = await writeBackup(json);
      final result = await const LogicalRestoreService().stage(
        paths: paths,
        backup: backup,
        passphrase: null,
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
      );
      expect(result.journal.attachmentsIncluded, isFalse);
      expect(result.journal.replaceAttachmentStore, isFalse);
    });

    test('refuses a second staged restore', () async {
      if (!supported) return;
      final json = await _sourceBackup();
      final backup = await writeBackup(json);
      await const LogicalRestoreService().stage(
        paths: paths,
        backup: backup,
        passphrase: null,
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
      );
      await expectLater(
        const LogicalRestoreService().stage(
          paths: paths,
          backup: backup,
          passphrase: null,
          keyStore: keyStore,
          attachmentKeyStore: attachmentKeyStore,
        ),
        throwsA(isA<Object>()),
      );
    });
  }, skip: supported ? null : 'SQLite3MC binary is not available here.');
}
