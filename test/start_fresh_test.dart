import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/database_bootstrap.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_metadata.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/security/quarantine_service.dart';
import 'package:locus_planner/core/security/recovery_envelope.dart';
import 'package:locus_planner/core/security/recovery_envelope_store.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';
import 'package:locus_planner/core/security/start_fresh_service.dart';
import 'package:locus_planner/core/services/attachments/attachment_key_store.dart';
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

void main() {
  final supported = _runtimeSupported();
  if (supported) Sqlite3mcLoader.ensureConfigured();

  group('C3 start fresh', () {
    late Directory directory;
    late InMemoryDatabaseKeyStore keyStore;
    late DatabasePaths paths;
    late DatabaseMetadata oldMetadata;
    late DatabaseKeyRecord oldKey;

    setUp(() async {
      if (!supported) return;
      directory = await Directory.systemTemp.createTemp('locus-fresh-');
      keyStore = InMemoryDatabaseKeyStore();
      DatabaseSecurity.configure(
        DatabaseSecurityOptions.encrypted(
          dataDirectory: directory,
          keyStore: keyStore,
        ),
      );
      final executor = await DatabaseBootstrap.open();
      await executor.close();
      DatabaseRuntimeContext.current = null;
      paths = await DatabasePathsResolver.resolve();
      oldMetadata = (await DatabaseMetadataStore(paths.metadataFile).read())!;
      oldKey = (await keyStore.read(oldMetadata.activeKeyId))!;

      final db = SqliteRuntime.open(paths.databaseFile.path);
      try {
        SqliteCipherRuntime.applyKey(db, CipherProfiles.active, oldKey.bytes);
        db.execute('CREATE TABLE probe (id INTEGER PRIMARY KEY)');
        db.execute('INSERT INTO probe DEFAULT VALUES');
      } finally {
        db.dispose();
      }
    });

    tearDown(() async {
      DatabaseRuntimeContext.current = null;
      DatabaseSecurity.reset();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test(
      'quarantines the old database, preserves keys, creates a new identity',
      () async {
        if (!supported) return;
        final request = await const StartFreshService().request(paths: paths);
        expect(request.previousDatabaseId, oldMetadata.databaseId);

        final executor = await DatabaseBootstrap.open();
        await executor.close();

        final newMetadata = (await DatabaseMetadataStore(
          paths.metadataFile,
        ).read())!;
        expect(newMetadata.databaseId, isNot(oldMetadata.databaseId));
        expect(newMetadata.keyGeneration, oldMetadata.keyGeneration + 1);
        expect(await keyStore.read(oldMetadata.activeKeyId), isNotNull);

        expect(await File(paths.startFreshRequestFile.path).exists(), isFalse);

        final quarantine = Directory(paths.quarantineDirectory.path);
        expect(await quarantine.exists(), isTrue);
        final artifact = (await const QuarantineService().list(paths)).single;
        expect(artifact.name, startsWith('start-fresh-'));
        expect(
          await File(p.join(artifact.path, 'manifest.json')).exists(),
          isTrue,
        );
        expect(
          await File(
            p.join(artifact.path, p.basename(paths.databaseFile.path)),
          ).exists(),
          isTrue,
        );

        final newKey = await keyStore.read(newMetadata.activeKeyId);
        final db = SqliteRuntime.open(paths.databaseFile.path);
        try {
          SqliteCipherRuntime.applyKey(
            db,
            CipherProfiles.active,
            newKey!.bytes,
          );
          final tables = db.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'probe'",
          );
          expect(tables, isEmpty);
          expect(db.select('PRAGMA user_version').first['user_version'], 0);
        } finally {
          db.dispose();
        }

        await const QuarantineService().delete(paths, artifact.path);
        expect(await const QuarantineService().list(paths), isEmpty);
      },
    );

    test('refuses to stage while a restore journal exists', () async {
      if (!supported) return;
      await File(
        paths.restoreJournalFile.path,
      ).writeAsString('{}', flush: true);
      await expectLater(
        const StartFreshService().request(paths: paths),
        throwsA(isA<Object>()),
      );
    });
  }, skip: supported ? null : 'SQLite3MC binary is not available here.');

  group('C3 recovery envelope store', () {
    test('rewraps the same DEK and retires the old envelope', () async {
      final directory = await Directory.systemTemp.createTemp('locus-env-');
      addTearDown(() => directory.delete(recursive: true));
      final store = RecoveryEnvelopeStore(directory);
      final dek = List<int>.generate(32, (index) => index).toList();
      final attachmentKey = List<int>.generate(
        32,
        (index) => 255 - index,
      ).toList();
      final attachmentStore = InMemoryAttachmentKeyStore()
        ..value = Uint8List.fromList(attachmentKey);

      final bundle = await RecoveryEnvelopeService.seal(
        dek: Uint8List.fromList(dek),
        databaseId: 'db-test',
        keyId: 'key-0001',
        keyGeneration: 1,
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        passphrase: 'old passphrase',
        attachmentKey: Uint8List.fromList(attachmentKey),
        iterations: 100000,
      );
      await store.write(bundle);
      expect(await store.current(), isNotNull);

      await store.changePassphrase(
        oldPassphrase: 'old passphrase',
        newPassphrase: 'new passphrase',
        attachmentKeyStore: attachmentStore,
      );
      final files = await store.list();
      expect(files, hasLength(2));
      expect(
        files.where((file) => p.basename(file.path).startsWith('retired-')),
        hasLength(1),
      );
      final current = await store.current();
      expect(current, isNotNull);
      final opened = await RecoveryEnvelopeService.open(
        current!,
        'new passphrase',
      );
      expect(opened.dek.toList(), dek);
      expect(opened.attachmentKey?.toList(), attachmentKey);
      await expectLater(
        RecoveryEnvelopeService.open(current, 'old passphrase'),
        throwsA(isA<Object>()),
      );

      await store.write(bundle, retireExisting: true);
      expect(
        (await store.list()).where(
          (file) => p.basename(file.path).startsWith('envelope-'),
        ),
        hasLength(1),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
