import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/database_maintenance.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/database_bootstrap.dart';
import 'package:locus_planner/core/security/database_identity.dart';
import 'package:locus_planner/core/security/database_key_service.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_metadata.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/database_security_errors.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/security/migration_journal.dart';
import 'package:locus_planner/core/security/recovery_envelope.dart';
import 'package:locus_planner/core/security/rotation_journal.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _profileId = 'locus-sqlcipher4-raw-v1';

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
  if (supported) {
    // Must happen before any sqlite3 access in this isolate.
    Sqlite3mcLoader.ensureConfigured();
  }

  group('B-NATIVE runtime', () {
    test('bundled SQLite3MC passes the encrypted round trip', () async {
      if (!supported) return;
      Sqlite3mcLoader.resetVerificationForTesting();
      final report = await Sqlite3mcLoader.requireVerified(
        profile: CipherProfiles.active,
      );
      expect(report.passed, isTrue);
      expect(report.runtime.version, contains('2.6.1'));
      expect(report.runtime.cipherPragmaAvailable, isTrue);
      expect(report.encryptedHeader, isTrue);
      expect(report.reopenedWithKey, isTrue);
      expect(report.wrongKeyRejected, isTrue);
      expect(report.tempStore, 2);
      expect(report.pageSize, 4096);
    });

    test('the profile is an explicit raw-key SQLCipher v4 configuration', () {
      final profile = CipherProfiles.byId(_profileId);
      expect(profile, isNotNull);
      expect(profile!.usesRawKey, isTrue);
      expect(profile.cipher, 'sqlcipher');
      expect(profile.legacy, 4);
      expect(profile.configurationStatements(), <String>[
        "PRAGMA cipher = 'sqlcipher'",
        'PRAGMA legacy = 4',
        'PRAGMA page_size = 4096',
        'PRAGMA temp_store = MEMORY',
        'PRAGMA memory_security = FILL',
      ]);
      expect(profile.rawKeyLiteral('ab' * 32), "x'${'ab' * 32}'");
      expect(
        profile.rekeyOnlyStatement(Uint8List(32)),
        startsWith('PRAGMA rekey'),
      );
    });
  });

  group('B-CIPHER and B-CONV', () {
    late Directory directory;
    late DatabaseKeyStore keyStore;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-enc-');
      keyStore = InMemoryDatabaseKeyStore();
    });

    tearDown(() async {
      DatabaseRuntimeContext.current = null;
      DatabaseSecurity.reset();
      await directory.delete(recursive: true);
    });

    DatabasePaths pathsOf(Directory dir) => DatabasePaths(
      dataDirectory: dir,
      databaseFile: File(p.join(dir.path, DatabasePaths.databaseFileName)),
    );

    void createPlaintext(File file) {
      final db = sqlite3.sqlite3.open(file.path);
      try {
        db.execute(
          'CREATE TABLE events (id TEXT PRIMARY KEY, title TEXT NOT NULL)',
        );
        db.execute("INSERT INTO events (id, title) VALUES ('e1', 'Alpha')");
        db.execute("INSERT INTO events (id, title) VALUES ('e2', 'Béta ✓')");
        db.execute(
          'CREATE TABLE app_settings (key TEXT PRIMARY KEY, '
          'value TEXT NOT NULL)',
        );
        db.execute(
          "INSERT INTO app_settings (key, value) VALUES ('theme', 'dark')",
        );
        db.execute('CREATE INDEX events_title ON events (title)');
        db.execute('PRAGMA user_version = $currentDatabaseSchemaVersion');
      } finally {
        db.dispose();
      }
    }

    Future<DatabaseKey> keyFor(
      DatabaseMetadata metadata, {
      DatabaseKeyStore? store,
    }) async {
      final key = await DatabaseKeyService(
        store ?? keyStore,
      ).load(metadata.activeKeyId);
      expect(key, isNotNull);
      return key!;
    }

    sqlite3.Database openKeyed(File file, DatabaseKey key) {
      final db = sqlite3.sqlite3.open(file.path);
      SqliteCipherRuntime.applyKey(db, CipherProfiles.active, key.bytes);
      return db;
    }

    test(
      'converts a schema-16 plaintext database and verifies parity',
      () async {
        if (!supported) return;
        final paths = pathsOf(directory);
        createPlaintext(paths.databaseFile);

        DatabaseSecurity.configure(
          DatabaseSecurityOptions.encrypted(
            dataDirectory: directory,
            keyStore: keyStore,
            allowAutomaticConversion: true,
          ),
        );
        final executor = await DatabaseBootstrap.open();
        await executor.close();

        expect(await paths.metadataFile.exists(), isTrue);
        final metadata = await DatabaseMetadataStore(paths.metadataFile).read();
        expect(metadata, isNotNull);
        expect(metadata!.encryptionEnabled, isTrue);
        expect(metadata.cipherProfileId, _profileId);

        final header = (await paths.databaseFile.readAsBytes())
            .take(16)
            .toList();
        expect(String.fromCharCodes(header), isNot('SQLite format 3\u0000'));

        final key = await keyFor(metadata);
        final encrypted = openKeyed(paths.databaseFile, key);
        try {
          final rows = encrypted.select(
            'SELECT id, title FROM events ORDER BY id',
          );
          expect(rows.map((row) => row['title']), <String>['Alpha', 'Béta ✓']);
          expect(
            encrypted.select('PRAGMA user_version').first['user_version'],
            currentDatabaseSchemaVersion,
          );
        } finally {
          encrypted.dispose();
        }

        // The original plaintext is retained in quarantine.
        final quarantine = Directory(p.join(directory.path, 'quarantine'));
        final quarantined = quarantine
            .listSync()
            .whereType<Directory>()
            .expand(
              (dir) => dir.listSync().whereType<File>().where(
                (file) =>
                    p.basename(file.path) ==
                    p.basename(paths.databaseFile.path),
              ),
            )
            .toList();
        expect(quarantined, isNotEmpty);

        final plaintext = sqlite3.sqlite3.open(quarantined.single.path);
        final converted = sqlite3.sqlite3.open(paths.databaseFile.path);
        try {
          SqliteCipherRuntime.applyKey(
            converted,
            CipherProfiles.active,
            key.bytes,
          );
          final left = plaintext.select('SELECT * FROM events ORDER BY id');
          final right = converted.select('SELECT * FROM events ORDER BY id');
          expect(
            right.map((row) => row['title']),
            left.map((row) => row['title']),
          );
        } finally {
          plaintext.dispose();
          converted.dispose();
        }

        // Reopen through the normal startup path.
        final reopened = await DatabaseBootstrap.open();
        await reopened.close();

        // A wrong key must not open the file.
        final wrong = sqlite3.sqlite3.open(paths.databaseFile.path);
        try {
          expect(
            () => SqliteCipherRuntime.applyKey(
              wrong,
              CipherProfiles.active,
              KeyDerivation.randomBytes(32),
            ),
            throwsA(anything),
          );
        } finally {
          wrong.dispose();
        }
      },
    );

    test('refuses automatic conversion unless explicitly allowed', () async {
      if (!supported) return;
      final paths = pathsOf(directory);
      createPlaintext(paths.databaseFile);
      final original = await paths.databaseFile.readAsBytes();

      DatabaseSecurity.configure(
        DatabaseSecurityOptions.encrypted(
          dataDirectory: directory,
          keyStore: keyStore,
        ),
      );

      await expectLater(
        DatabaseBootstrap.open(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.recoveryRequired,
          ),
        ),
      );
      expect(await paths.databaseFile.readAsBytes(), original);
      expect(await paths.metadataFile.exists(), isFalse);
      expect(await paths.migrationJournalFile.exists(), isFalse);
      expect(await keyStore.listVersions(), isEmpty);
    });

    test(
      'rejects a different cipher profile and a passphrase-shaped key',
      () async {
        if (!supported) return;
        final file = File(p.join(directory.path, 'profile-probe.db'));
        final key = KeyDerivation.randomBytes(32);

        final created = SqliteRuntime.open(file.path);
        try {
          SqliteCipherRuntime.applyKey(
            created,
            CipherProfiles.sqlCipher4RawV1,
            key,
          );
          created.execute('CREATE TABLE probe (id INTEGER)');
        } finally {
          created.dispose();
        }

        final wrongProfile = SqliteRuntime.open(file.path);
        try {
          expect(
            () => SqliteCipherRuntime.applyKey(
              wrongProfile,
              CipherProfiles.sqleetRawV1,
              key,
            ),
            throwsA(anything),
          );
        } finally {
          wrongProfile.dispose();
        }

        // A 32-character passphrase is still a passphrase, not a raw key.
        final passphraseShaped = Uint8List.fromList(
          'abcdefghijklmnopqrstuvwxyz012345'.codeUnits,
        );
        expect(passphraseShaped, hasLength(32));
        final wrongKey = SqliteRuntime.open(file.path);
        try {
          expect(
            () => SqliteCipherRuntime.applyKey(
              wrongKey,
              CipherProfiles.sqlCipher4RawV1,
              passphraseShaped,
            ),
            throwsA(anything),
          );
        } finally {
          wrongKey.dispose();
        }
      },
    );

    test('resumes a conversion that crashed before metadata commit', () async {
      if (!supported) return;
      final paths = pathsOf(directory);
      createPlaintext(paths.databaseFile);

      DatabaseSecurity.configure(
        DatabaseSecurityOptions.encrypted(
          dataDirectory: directory,
          keyStore: keyStore,
          allowAutomaticConversion: true,
        ),
      );
      final executor = await DatabaseBootstrap.open();
      await executor.close();

      final metadata = (await DatabaseMetadataStore(
        paths.metadataFile,
      ).read())!;
      final key = await keyFor(metadata);

      // Simulate: replacement completed, then the process died.
      await DatabaseMetadataStore(paths.metadataFile).file.delete();
      await MigrationJournalStore(paths.migrationJournalFile).write(
        MigrationJournal(
          migrationId: 'migration-crash',
          databaseId: metadata.databaseId,
          stage: MigrationStage.replacementCompleted,
          sourcePath: paths.databaseFile.path,
          sourceSidecars: const <String>[],
          newKeyId: key.keyId,
          newKeyGeneration: key.generation,
          cipherProfileId: _profileId,
          quarantinePath: p.join(directory.path, 'quarantine', 'old'),
          startedAt: DateTime.utc(2026, 11, 4),
          updatedAt: DateTime.utc(2026, 11, 4),
        ),
      );

      final recovered = await DatabaseBootstrap.open();
      await recovered.close();

      final restored = await DatabaseMetadataStore(paths.metadataFile).read();
      expect(restored, isNotNull);
      expect(restored!.databaseId, metadata.databaseId);
      expect(restored.activeKeyId, key.keyId);
      expect(await paths.migrationJournalFile.exists(), isFalse);

      final db = openKeyed(paths.databaseFile, key);
      try {
        expect(db.select('SELECT COUNT(*) AS c FROM events').first['c'], 2);
        expect(DatabaseIdentityStore.read(db)!.keyId, key.keyId);
      } finally {
        db.dispose();
      }
    });
  }, skip: supported ? null : 'SQLite3MC binary is not available here.');

  group('B-ROT rotation', () {
    late Directory directory;
    late InMemoryDatabaseKeyStore keyStore;
    late DatabasePaths paths;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-rot-');
      keyStore = InMemoryDatabaseKeyStore();
      paths = DatabasePaths(
        dataDirectory: directory,
        databaseFile: File(
          p.join(directory.path, DatabasePaths.databaseFileName),
        ),
      );
      final db = sqlite3.sqlite3.open(paths.databaseFile.path);
      try {
        db.execute(
          'CREATE TABLE events (id TEXT PRIMARY KEY, title TEXT NOT NULL)',
        );
        db.execute("INSERT INTO events (id, title) VALUES ('e1', 'Alpha')");
        db.execute("INSERT INTO events (id, title) VALUES ('e2', 'Beta')");
        db.execute('PRAGMA user_version = $currentDatabaseSchemaVersion');
      } finally {
        db.dispose();
      }
      DatabaseSecurity.configure(
        DatabaseSecurityOptions.encrypted(
          dataDirectory: directory,
          keyStore: keyStore,
          allowAutomaticConversion: true,
        ),
      );
      final executor = await DatabaseBootstrap.open();
      await executor.close();
      // Simulate a restart into a rotation window: the process no longer has a
      // live database handle registered.
      DatabaseRuntimeContext.current = null;
    });

    tearDown(() async {
      DatabaseRuntimeContext.current = null;
      DatabaseSecurity.reset();
      await directory.delete(recursive: true);
    });

    Future<DatabaseMetadata> metadata() async =>
        (await DatabaseMetadataStore(paths.metadataFile).read())!;

    Future<DatabaseKey> key(String keyId) async =>
        (await DatabaseKeyService(keyStore).load(keyId))!;

    test('rekeys to a new generation and preserves the old pair', () async {
      if (!supported) return;
      final before = await metadata();
      final oldKey = await key(before.activeKeyId);

      final after = await DatabaseBootstrap.rotateKey();

      expect(after.databaseId, before.databaseId);
      expect(after.activeKeyId, isNot(before.activeKeyId));
      expect(after.keyGeneration, before.keyGeneration + 1);
      expect(await paths.rotationJournalFile.exists(), isFalse);

      final fresh = await key(after.activeKeyId);
      final stale = await key(before.activeKeyId);
      expect(fresh.bytes, isNot(oldKey.bytes));

      // New key opens the database; old key does not.
      final newOpen = sqlite3.sqlite3.open(paths.databaseFile.path);
      try {
        SqliteCipherRuntime.applyKey(
          newOpen,
          CipherProfiles.active,
          fresh.bytes,
        );
        expect(
          newOpen.select('SELECT COUNT(*) AS c FROM events').first['c'],
          2,
        );
        expect(DatabaseIdentityStore.read(newOpen)!.keyId, fresh.keyId);
      } finally {
        newOpen.dispose();
      }

      final oldOpen = sqlite3.sqlite3.open(paths.databaseFile.path);
      try {
        expect(
          () => SqliteCipherRuntime.applyKey(
            oldOpen,
            CipherProfiles.active,
            stale.bytes,
          ),
          throwsA(anything),
        );
      } finally {
        oldOpen.dispose();
      }

      // The old key record is retained but inactive.
      final records = await keyStore.listVersions();
      expect(
        records.firstWhere((record) => record.keyId == stale.keyId).active,
        isFalse,
      );
      expect(
        records.firstWhere((record) => record.keyId == fresh.keyId).active,
        isTrue,
      );

      // A pre-rotation encrypted copy remains available.
      final backups = Directory(p.join(directory.path, 'backups', 'rotation'));
      expect(backups.listSync().whereType<File>(), isNotEmpty);

      // The normal startup path still works.
      final reopened = await DatabaseBootstrap.open();
      await reopened.close();
    });

    test(
      'is blocked while the application database handle is registered',
      () async {
        if (!supported) return;
        final open = await DatabaseBootstrap.open();
        await open.close();

        await expectLater(
          DatabaseBootstrap.rotateKey(),
          throwsA(
            isA<DatabaseSecurityException>().having(
              (error) => error.code,
              'code',
              DatabaseSecurityErrorCode.lifecycleBusy,
            ),
          ),
        );
        DatabaseRuntimeContext.current = null;
      },
    );

    test('recovers after replacement before metadata activation', () async {
      if (!supported) return;
      final before = await metadata();
      final oldKey = await key(before.activeKeyId);
      final after = await DatabaseBootstrap.rotateKey();
      final newKey = await key(after.activeKeyId);

      // Simulate: the replacement is live but metadata/activation were not
      // committed, and the process died.
      await DatabaseMetadataStore(paths.metadataFile).write(before);
      await keyStore.markActive(oldKey.keyId);
      await RotationJournalStore(paths.rotationJournalFile).write(
        RotationJournal(
          rotationId: 'rotation-crash',
          databaseId: before.databaseId,
          stage: RotationStage.replacementCompleted,
          sourcePath: paths.databaseFile.path,
          oldKeyId: oldKey.keyId,
          oldGeneration: oldKey.generation,
          newKeyId: newKey.keyId,
          newGeneration: newKey.generation,
          cipherProfileId: _profileId,
          startedAt: DateTime.utc(2026, 11, 4),
          updatedAt: DateTime.utc(2026, 11, 4),
        ),
      );

      final recovered = await DatabaseBootstrap.open();
      await recovered.close();

      final restored = await metadata();
      expect(restored.activeKeyId, newKey.keyId);
      expect(restored.keyGeneration, newKey.generation);
      expect(await paths.rotationJournalFile.exists(), isFalse);
      final active = (await keyStore.listVersions())
          .where((record) => record.active)
          .toList();
      expect(active.single.keyId, newKey.keyId);
    });

    test('rolls back a candidate that was never replaced', () async {
      if (!supported) return;
      final before = await metadata();
      final oldKey = await key(before.activeKeyId);
      final newKey = await DatabaseKeyService(keyStore).createFresh(
        databaseId: before.databaseId,
        cipherProfileId: _profileId,
        activate: false,
      );

      final candidate = File('${paths.databaseFile.path}.rotating-crash');
      await paths.databaseFile.copy(candidate.path);
      await RotationJournalStore(paths.rotationJournalFile).write(
        RotationJournal(
          rotationId: 'rotation-crash',
          databaseId: before.databaseId,
          stage: RotationStage.candidateCreated,
          sourcePath: paths.databaseFile.path,
          candidatePath: candidate.path,
          oldKeyId: oldKey.keyId,
          oldGeneration: oldKey.generation,
          newKeyId: newKey.keyId,
          newGeneration: newKey.generation,
          cipherProfileId: _profileId,
          startedAt: DateTime.utc(2026, 11, 4),
          updatedAt: DateTime.utc(2026, 11, 4),
        ),
      );

      final recovered = await DatabaseBootstrap.open();
      await recovered.close();

      expect(await candidate.exists(), isFalse);
      expect(await paths.rotationJournalFile.exists(), isFalse);
      final restored = await metadata();
      expect(restored.activeKeyId, oldKey.keyId);
      final active = (await keyStore.listVersions())
          .where((record) => record.active)
          .toList();
      expect(active.single.keyId, oldKey.keyId);

      final db = sqlite3.sqlite3.open(paths.databaseFile.path);
      try {
        SqliteCipherRuntime.applyKey(db, CipherProfiles.active, oldKey.bytes);
        expect(db.select('SELECT COUNT(*) AS c FROM events').first['c'], 2);
      } finally {
        db.dispose();
      }
    });
  }, skip: supported ? null : 'SQLite3MC binary is not available here.');

  group('release configuration', () {
    tearDown(DatabaseSecurity.reset);

    test('encryption and automatic migration are separate switches', () {
      DatabaseSecurity.configureFromEnvironment(
        environment: <String, String>{'LOCUS_DB_ENCRYPTION': '1'},
      );
      expect(DatabaseSecurity.liveEncryptionEnabled, isTrue);
      expect(DatabaseSecurity.current.allowAutomaticConversion, isFalse);

      DatabaseSecurity.configureFromEnvironment(
        environment: <String, String>{
          'LOCUS_DB_ENCRYPTION': 'true',
          'LOCUS_DB_MIGRATION': 'true',
        },
      );
      expect(DatabaseSecurity.liveEncryptionEnabled, isTrue);
      expect(DatabaseSecurity.current.allowAutomaticConversion, isTrue);

      DatabaseSecurity.configureFromEnvironment(
        environment: <String, String>{'LOCUS_DB_MIGRATION': 'true'},
      );
      expect(DatabaseSecurity.liveEncryptionEnabled, isFalse);
    });
  });

  group('B-ROT recovery material', () {
    test(
      'an old envelope is stale after rotation, a reseal reuses the DEK',
      () async {
        final dek = KeyDerivation.randomBytes(32);
        final bundle = await RecoveryEnvelopeService.seal(
          dek: dek,
          databaseId: 'db-test',
          keyId: 'key-0001',
          keyGeneration: 1,
          cipherProfileId: _profileId,
          passphrase: 'correct horse battery staple',
          iterations: 100000,
          createdAt: DateTime.utc(2026, 11, 4),
        );
        final metadata = DatabaseMetadata(
          databaseId: 'db-test',
          activeKeyId: 'key-0001',
          keyGeneration: 1,
          cipherProfileId: _profileId,
          encryptionEnabled: true,
          databaseFile: 'locus_planner.db',
          createdAt: DateTime.utc(2026, 11, 4),
        );
        expect(bundle.isCurrentFor(metadata), isTrue);

        final rotated = DatabaseMetadata(
          databaseId: 'db-test',
          activeKeyId: 'key-0002',
          keyGeneration: 2,
          cipherProfileId: _profileId,
          encryptionEnabled: true,
          databaseFile: 'locus_planner.db',
          createdAt: DateTime.utc(2026, 11, 4),
        );
        expect(bundle.isCurrentFor(rotated), isFalse);

        // A passphrase change (reseal) keeps the same DEK and produces current
        // material for the same key generation.
        final resealed = await RecoveryEnvelopeService.seal(
          dek: dek,
          databaseId: 'db-test',
          keyId: 'key-0001',
          keyGeneration: 1,
          cipherProfileId: _profileId,
          passphrase: 'a new passphrase',
          iterations: 100000,
          createdAt: DateTime.utc(2026, 11, 4),
        );
        final opened = await RecoveryEnvelopeService.open(
          resealed,
          'a new passphrase',
        );
        expect(opened.dek, dek);
        expect(resealed.isCurrentFor(metadata), isTrue);
      },
    );
  });
}
