import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/database_maintenance.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/database_bootstrap.dart';
import 'package:locus_planner/core/security/database_identity.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_metadata.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/security/recovery_envelope.dart';
import 'package:locus_planner/core/security/recovery_package_service.dart';
import 'package:locus_planner/core/security/recovery_restore_service.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_key_store.dart';
import 'package:path/path.dart' as p;

const _passphrase = 'correct horse battery staple';
const _iterations = 100000;

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

Future<void> _seedDatabase(
  DatabasePaths paths,
  DatabaseKeyRecord key,
  Uint8List attachKey,
  Uint8List attachmentPlain,
) async {
  final db = SqliteRuntime.open(paths.databaseFile.path);
  try {
    SqliteCipherRuntime.applyKey(db, CipherProfiles.active, key.bytes);
    db.execute('CREATE TABLE probe (id TEXT PRIMARY KEY, value TEXT NOT NULL)');
    db.execute("INSERT INTO probe VALUES ('p1', 'alpha')");
    db.execute('CREATE TABLE attachments (sha256 TEXT NOT NULL)');
    db.execute(
      'CREATE TABLE attachment_blobs ('
      'sha256 TEXT NOT NULL, state TEXT NOT NULL)',
    );
    final sha = crypto.sha256.convert(attachmentPlain).toString();
    db.execute('INSERT INTO attachments VALUES (?)', <Object?>[sha]);
    db.execute('INSERT INTO attachment_blobs VALUES (?, ?)', <Object?>[
      sha,
      'present',
    ]);
    db.execute('PRAGMA user_version = $currentDatabaseSchemaVersion');
  } finally {
    db.dispose();
  }

  final api = AttachmentCrypto(attachKey);
  final fileId = api.fileId(crypto.sha256.convert(attachmentPlain).toString());
  final blob = File(
    p.join(paths.dataDirectory.path, 'attachments', 'ab', fileId),
  );
  await blob.parent.create(recursive: true);
  await blob.writeAsBytes(api.sealBytes(attachmentPlain), flush: true);
  final thumb = File(
    p.join(paths.dataDirectory.path, 'attachments', 'thumbs', '$fileId.t'),
  );
  await thumb.parent.create(recursive: true);
  await thumb.writeAsBytes(
    api.sealBytes(Uint8List.fromList(<int>[1, 2, 3, 4])),
    flush: true,
  );
}

void main() {
  final supported = _runtimeSupported();
  if (supported) Sqlite3mcLoader.ensureConfigured();

  group('C1 raw recovery packages', () {
    late Directory directory;
    late InMemoryDatabaseKeyStore keyStore;
    late InMemoryAttachmentKeyStore attachmentStore;
    late DatabasePaths paths;
    late DatabaseMetadata metadata;
    late DatabaseKeyRecord activeKey;
    late Uint8List attachKey;
    late Uint8List attachmentPlain;

    setUp(() async {
      if (!supported) return;
      directory = await Directory.systemTemp.createTemp('locus-recovery-');
      keyStore = InMemoryDatabaseKeyStore();
      attachmentStore = InMemoryAttachmentKeyStore();
      attachKey = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );
      attachmentStore.value = attachKey;
      attachmentPlain = Uint8List.fromList(utf8.encode('attachment payload'));
      paths = await _newEncryptedInstall(directory, keyStore);
      metadata = (await DatabaseMetadataStore(paths.metadataFile).read())!;
      activeKey = (await keyStore.listVersions()).single;
      await _seedDatabase(paths, activeKey, attachKey, attachmentPlain);
    });

    tearDown(() async {
      DatabaseRuntimeContext.current = null;
      DatabaseSecurity.reset();
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    Future<RecoveryPackageCreateResult> createPackage({
      bool includeAttachments = true,
    }) => const RecoveryPackageService().create(
      paths: paths,
      metadata: metadata,
      dek: activeKey.bytes,
      passphrase: _passphrase,
      target: File(p.join(directory.path, 'package.locusrecovery')),
      attachmentKeyStore: attachmentStore,
      includeAttachments: includeAttachments,
      iterations: _iterations,
    );

    test(
      'creates and verifies a package with the database and attachments',
      () async {
        if (!supported) return;
        // Keep a second keyed connection open while the package is created;
        // this mirrors the Settings flow where the planner database is live.
        final live = SqliteRuntime.open(paths.databaseFile.path);
        SqliteCipherRuntime.applyKey(
          live,
          CipherProfiles.active,
          activeKey.bytes,
        );
        live.select('SELECT 1');
        final RecoveryPackageCreateResult result;
        try {
          result = await createPackage();
        } finally {
          live.dispose();
        }
        expect(result.manifest.databaseId, metadata.databaseId);
        expect(result.manifest.keyId, metadata.activeKeyId);
        expect(result.manifest.schemaVersion, currentDatabaseSchemaVersion);
        expect(result.manifest.attachmentsIncluded, isTrue);
        expect(result.manifest.attachmentFileCount, 2);
        expect(result.manifest.skippedAttachmentCount, 0);
        expect(result.archiveBytes, greaterThan(0));

        final verified = await const RecoveryPackageService().verify(
          archive: result.file,
          passphrase: _passphrase,
        );
        expect(verified.databaseSha256, result.manifest.databaseSha256);
      },
    );

    test('rejects a wrong passphrase without writing anything', () async {
      if (!supported) return;
      final result = await createPackage();
      await expectLater(
        const RecoveryPackageService().verify(
          archive: result.file,
          passphrase: 'wrong passphrase',
        ),
        throwsA(isA<RecoveryPackageException>()),
      );
    });

    test('rejects a truncated package', () async {
      if (!supported) return;
      final result = await createPackage();
      final bytes = await result.file.readAsBytes();
      await result.file.writeAsBytes(
        bytes.sublist(0, bytes.length ~/ 2),
        flush: true,
      );
      await expectLater(
        const RecoveryPackageService().verify(
          archive: result.file,
          passphrase: _passphrase,
        ),
        throwsA(isA<RecoveryPackageException>()),
      );
    });

    test('can omit attachments', () async {
      if (!supported) return;
      final result = await createPackage(includeAttachments: false);
      expect(result.manifest.attachmentsIncluded, isFalse);
      expect(result.manifest.attachmentFileCount, 0);
      await const RecoveryPackageService().verify(
        archive: result.file,
        passphrase: _passphrase,
      );
    });

    test('the envelope carries the attachment key', () async {
      if (!supported) return;
      final result = await createPackage();
      final extracted = await Directory.systemTemp.createTemp(
        'locus-recovery-extract-',
      );
      addTearDown(() => extracted.delete(recursive: true));
      await const RecoveryPackageService().extractAndVerify(
        archive: result.file,
        passphrase: _passphrase,
        destination: extracted,
      );
      final bundle = RecoveryBundle.decode(
        await File(p.join(extracted.path, 'recovery.json')).readAsString(),
      );
      final opened = await RecoveryEnvelopeService.open(bundle, _passphrase);
      expect(opened.attachmentKey, attachKey);
    });

    test(
      'a clean install applies the staged package and reads the blobs',
      () async {
        if (!supported) return;
        final result = await createPackage();

        final clean = await Directory.systemTemp.createTemp('locus-clean-');
        addTearDown(() async {
          DatabaseRuntimeContext.current = null;
          DatabaseSecurity.reset();
          if (await clean.exists()) await clean.delete(recursive: true);
        });
        final cleanKeys = InMemoryDatabaseKeyStore();
        final cleanAttachments = InMemoryAttachmentKeyStore();
        final cleanPaths = await _newEncryptedInstall(clean, cleanKeys);

        await const RecoveryRestoreService().stage(
          paths: cleanPaths,
          package: result.file,
          passphrase: _passphrase,
          keyStore: cleanKeys,
          attachmentKeyStore: cleanAttachments,
        );
        final applied = await const RecoveryRestoreService().applyStagedLocked(
          paths: cleanPaths,
          keyStore: cleanKeys,
          attachmentKeyStore: cleanAttachments,
        );
        expect(applied, isTrue);

        final restoredMetadata = await DatabaseMetadataStore(
          cleanPaths.metadataFile,
        ).read();
        expect(restoredMetadata!.databaseId, metadata.databaseId);
        expect(restoredMetadata.activeKeyId, metadata.activeKeyId);
        expect(await cleanAttachments.read(), attachKey);

        final restoredKey = await cleanKeys.read(metadata.activeKeyId);
        expect(restoredKey, isNotNull);
        final db = SqliteRuntime.open(cleanPaths.databaseFile.path);
        try {
          SqliteCipherRuntime.applyKey(
            db,
            CipherProfiles.active,
            restoredKey!.bytes,
          );
          expect(db.select('SELECT value FROM probe').single['value'], 'alpha');
          final identity = DatabaseIdentityStore.read(db);
          expect(identity!.databaseId, metadata.databaseId);
        } finally {
          db.dispose();
        }

        final api = AttachmentCrypto(attachKey);
        final fileId = api.fileId(
          crypto.sha256.convert(attachmentPlain).toString(),
        );
        final restoredBlob = File(
          p.join(cleanPaths.dataDirectory.path, 'attachments', 'ab', fileId),
        );
        expect(await restoredBlob.exists(), isTrue);
        expect(
          api.openBytes(await restoredBlob.readAsBytes()),
          attachmentPlain,
        );

        DatabaseRuntimeContext.current = null;
        final reopened = await DatabaseBootstrap.open();
        expect(DatabaseSecurity.actualEncryptionEnabled, isTrue);
        await reopened.close();
      },
    );

    test('sealed file verification detects a flipped byte', () async {
      if (!supported) return;
      final api = AttachmentCrypto(attachKey);
      final sealed = api.sealBytes(attachmentPlain);
      sealed[sealed.length - 1] ^= 0xFF;
      final file = File(p.join(directory.path, 'tampered.bin'));
      await file.writeAsBytes(sealed, flush: true);
      await expectLater(
        api.sealedFileSha256(file),
        throwsA(isA<AttachmentBlobCorruptException>()),
      );
    });
  }, skip: supported ? null : 'SQLite3MC binary is not available here.');
}
