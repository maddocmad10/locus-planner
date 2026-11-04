import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/security/atomic_file.dart';
import 'package:locus_planner/core/security/backup_passphrase_store.dart';
import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/database_file_inspector.dart';
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
import 'package:locus_planner/core/services/crypto/key_derivation.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

Future<Uint8List> _derive(
  String secret,
  Uint8List salt,
  int iterations,
) async => KeyDerivation.deriveSync(secret, salt, iterations);

DatabaseMetadata _metadata({
  String databaseId = 'db-test',
  String keyId = 'key-0001',
  int generation = 1,
  String profile = 'locus-sqlcipher4-raw-v1',
}) => DatabaseMetadata(
  databaseId: databaseId,
  activeKeyId: keyId,
  keyGeneration: generation,
  cipherProfileId: profile,
  encryptionEnabled: true,
  databaseFile: 'locus_planner.db',
  createdAt: DateTime.utc(2026, 11, 3),
);

void main() {
  group('cipher profiles', () {
    test('the default profile uses a raw SQLCipher v4 key', () {
      final profile = CipherProfiles.byId('locus-sqlcipher4-raw-v1');
      expect(profile, isNotNull);
      expect(profile!.usesRawKey, isTrue);
      expect(profile.rawKeyLiteral('ab' * 32), "x'${'ab' * 32}'");
      expect(
        profile.configurationStatements(),
        containsAll(<String>[
          "PRAGMA cipher = 'sqlcipher'",
          'PRAGMA legacy = 4',
          'PRAGMA page_size = 4096',
          'PRAGMA temp_store = MEMORY',
        ]),
      );
      final statements = profile.keyStatements(Uint8List(32));
      expect(statements.last, startsWith('PRAGMA key = "x\''));
    });

    test('an unknown profile is rejected instead of guessed', () {
      expect(CipherProfiles.byId('unknown-profile'), isNull);
    });
  });

  group('database metadata', () {
    test('round-trips through an atomic file', () async {
      final dir = await Directory.systemTemp.createTemp('locus-meta-');
      addTearDown(() => dir.delete(recursive: true));
      final store = DatabaseMetadataStore(
        File('${dir.path}${Platform.pathSeparator}db.meta.json'),
      );

      await store.write(_metadata());
      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.databaseId, 'db-test');
      expect(read.encryptionEnabled, isTrue);

      await store.touch(at: DateTime.utc(2026, 11, 4));
      expect((await store.read())!.lastOpenedAt, DateTime.utc(2026, 11, 4));

      final leftovers = dir.listSync().where(
        (entity) => entity.path.contains('.tmp-'),
      );
      expect(leftovers, isEmpty);
    });

    test('damaged metadata fails closed', () async {
      final dir = await Directory.systemTemp.createTemp('locus-meta-bad-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}${Platform.pathSeparator}bad.meta.json');
      await file.writeAsString('{not json');
      final store = DatabaseMetadataStore(file);

      await expectLater(
        store.read(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.metadataCorrupt,
          ),
        ),
      );
    });
  });

  group('identity anchor', () {
    test('is written and read inside the database', () {
      final db = sqlite3.sqlite3.openInMemory();
      addTearDown(db.dispose);
      DatabaseIdentityStore.ensureTable(db);

      final identity = DatabaseIdentity(
        databaseId: 'db-test',
        keyId: 'key-0001',
        keyGeneration: 1,
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        createdAt: _fixedDate,
      );
      DatabaseIdentityStore.write(db, identity);

      final read = DatabaseIdentityStore.read(db);
      expect(read, isNotNull);
      expect(read!.databaseId, 'db-test');
      expect(read.keyId, 'key-0001');
      read.requireMatches(_metadata());

      final other = _metadata(databaseId: 'db-other');
      expect(
        () => read.requireMatches(other),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.identityMismatch,
          ),
        ),
      );
    });
  });

  group('file inspector', () {
    test('classifies empty, plaintext, short and unknown files', () async {
      final dir = await Directory.systemTemp.createTemp('locus-inspect-');
      addTearDown(() => dir.delete(recursive: true));

      final missing = File('${dir.path}${Platform.pathSeparator}missing.db');
      expect(
        await DatabaseFileInspector.classify(missing),
        DatabaseFileKind.missing,
      );

      final empty = File('${dir.path}${Platform.pathSeparator}empty.db');
      await empty.writeAsBytes(const <int>[]);
      expect(
        await DatabaseFileInspector.classify(empty),
        DatabaseFileKind.empty,
      );

      final short = File('${dir.path}${Platform.pathSeparator}short.db');
      await short.writeAsString('SQLite');
      expect(
        await DatabaseFileInspector.classify(short),
        DatabaseFileKind.corrupt,
      );

      final plain = File('${dir.path}${Platform.pathSeparator}plain.db');
      await plain.writeAsBytes(utf8.encode(DatabaseFileInspector.sqliteHeader));
      expect(
        await DatabaseFileInspector.classify(plain),
        DatabaseFileKind.plaintext,
      );

      final encrypted = File('${dir.path}${Platform.pathSeparator}enc.db');
      await encrypted.writeAsBytes(utf8.encode('not a SQLite header at all'));
      expect(
        await DatabaseFileInspector.classify(encrypted),
        DatabaseFileKind.encryptedOrUnknown,
      );
    });

    test('quarantines the database and every sidecar together', () async {
      final dir = await Directory.systemTemp.createTemp('locus-quarantine-');
      addTearDown(() => dir.delete(recursive: true));
      final database = File('${dir.path}${Platform.pathSeparator}locus.db');
      final wal = File('${database.path}-wal');
      final shm = File('${database.path}-shm');
      for (final file in [database, wal, shm]) {
        await file.writeAsString('x');
      }

      await DatabaseFileInspector.quarantine(
        database,
        Directory('${dir.path}${Platform.pathSeparator}moved'),
      );

      expect(await database.exists(), isFalse);
      expect(await wal.exists(), isFalse);
      expect(await shm.exists(), isFalse);
      expect(
        await File(
          '${dir.path}${Platform.pathSeparator}moved'
          '${Platform.pathSeparator}locus.db',
        ).exists(),
        isTrue,
      );
      expect(
        await File(
          '${dir.path}${Platform.pathSeparator}moved'
          '${Platform.pathSeparator}locus.db-wal',
        ).exists(),
        isTrue,
      );
    });
  });

  group('migration journal', () {
    test('advances through durable stages and survives a restart', () async {
      final dir = await Directory.systemTemp.createTemp('locus-journal-');
      addTearDown(() => dir.delete(recursive: true));
      final store = MigrationJournalStore(
        File('${dir.path}${Platform.pathSeparator}db.migration.json'),
      );

      var journal = MigrationJournal(
        databaseId: 'db-test',
        stage: MigrationStage.notStarted,
        sourcePath: 'locus_planner.db',
        sourceSidecars: const <String>['locus_planner.db-wal'],
        newKeyId: 'key-0001',
        newKeyGeneration: 1,
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        startedAt: DateTime.utc(2026, 11, 3),
        updatedAt: DateTime.utc(2026, 11, 3),
      );
      await store.write(journal);
      journal = journal.advance(MigrationStage.snapshotCreated);
      await store.write(journal);

      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.stage, MigrationStage.snapshotCreated);
      expect(read.sourceSidecars.single, endsWith('-wal'));
      expect(read.reached(MigrationStage.precheckOk), isTrue);
      expect(read.reached(MigrationStage.migrationComplete), isFalse);
    });

    test('an unknown stage is a recovery error, not a best guess', () {
      expect(
        () => MigrationJournal.decode(
          jsonEncode(<String, Object?>{
            'formatVersion': 1,
            'stage': 'teleported',
            'startedAt': '2026-11-03T00:00:00Z',
            'updatedAt': '2026-11-03T00:00:00Z',
          }),
        ),
        throwsA(isA<DatabaseSecurityException>()),
      );
    });
  });

  group('key store and key service', () {
    test('creates versioned keys and never reuses a generation', () async {
      final store = InMemoryDatabaseKeyStore();
      final service = DatabaseKeyService(store);

      final first = await service.createFresh(
        databaseId: 'db-test',
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
      );
      expect(first.keyId, 'key-0001');
      expect(first.generation, 1);
      expect(first.bytes, hasLength(32));

      final second = await service.createFresh(
        databaseId: 'db-test',
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
      );
      expect(second.keyId, 'key-0002');
      expect(second.generation, 2);

      final loaded = await service.load('key-0001');
      expect(loaded!.hex, first.hex);
      expect((await store.read('key-0001'))!.active, isFalse);
      expect((await store.read('key-0002'))!.active, isTrue);

      await service.activate('key-0001');
      expect((await store.read('key-0001'))!.active, isTrue);

      await service.retire('key-0002');
      expect(await service.load('key-0002'), isNull);
    });

    test('a damaged key record is reported as corrupt', () {
      expect(
        () => DatabaseKeyRecord.decode(
          jsonEncode(<String, Object?>{
            'keyId': 'key-0001',
            'generation': 1,
            'databaseId': 'db-test',
            'cipherProfileId': 'locus-sqlcipher4-raw-v1',
            'createdAt': '2026-11-03T00:00:00Z',
            'key': base64Encode(<int>[1, 2, 3]),
          }),
        ),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.keyStoreCorrupt,
          ),
        ),
      );
    });
  });

  group('recovery envelope', () {
    test('unwraps the DEK and the backup credential', () async {
      final dek = KeyDerivation.randomBytes(32);
      final bundle = await RecoveryEnvelopeService.seal(
        dek: dek,
        databaseId: 'db-test',
        keyId: 'key-0001',
        keyGeneration: 1,
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        passphrase: 'correct horse battery',
        backupPassphrase: 'backup passphrase',
        backupFormatVersion: 3,
        iterations: 100000,
        derive: _derive,
      );

      final opened = await RecoveryEnvelopeService.open(
        RecoveryBundle.decode(bundle.encode()),
        'correct horse battery',
        backupFormatVersion: 3,
        derive: _derive,
      );
      expect(opened.dek, dek);
      expect(opened.backupPassphrase, 'backup passphrase');
      expect(opened.databaseId, 'db-test');

      await RecoveryEnvelopeService.verify(
        bundle: bundle,
        passphrase: 'correct horse battery',
        expectedDek: dek,
        backupFormatVersion: 3,
        derive: _derive,
      );
    });

    test('a wrong passphrase or edited AAD fails authentication', () async {
      final dek = KeyDerivation.randomBytes(32);
      final bundle = await RecoveryEnvelopeService.seal(
        dek: dek,
        databaseId: 'db-test',
        keyId: 'key-0001',
        keyGeneration: 1,
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        passphrase: 'correct horse battery',
        iterations: 100000,
        derive: _derive,
      );

      await expectLater(
        RecoveryEnvelopeService.open(
          bundle,
          'wrong passphrase',
          derive: _derive,
        ),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.unlockFailed,
          ),
        ),
      );

      final edited = RecoveryBundle(
        databaseId: 'db-other',
        keyId: bundle.keyId,
        keyGeneration: bundle.keyGeneration,
        cipherProfileId: bundle.cipherProfileId,
        createdAt: bundle.createdAt,
        entries: bundle.entries,
      );
      await expectLater(
        RecoveryEnvelopeService.open(
          edited,
          'correct horse battery',
          derive: _derive,
        ),
        throwsA(isA<DatabaseSecurityException>()),
      );
    });
  });

  group('atomic file', () {
    test('replaces a file and leaves no temporary sibling', () async {
      final dir = await Directory.systemTemp.createTemp('locus-atomic-');
      addTearDown(() => dir.delete(recursive: true));
      final target = File('${dir.path}${Platform.pathSeparator}target.txt');

      await AtomicFile.writeString(target, 'first');
      await AtomicFile.writeString(target, 'second');

      expect(await target.readAsString(), 'second');
      expect(
        dir.listSync().where((entity) => entity.path.contains('.tmp-')),
        isEmpty,
      );
    });
  });
  group('startup decision model', () {
    test('does not recreate a missing encrypted database', () async {
      final dir = await Directory.systemTemp.createTemp('locus-bootstrap-');
      addTearDown(() => dir.delete(recursive: true));
      final metadataStore = DatabaseMetadataStore(
        File('${dir.path}${Platform.pathSeparator}locus_planner.db.meta.json'),
      );
      await metadataStore.write(_metadata());

      DatabaseSecurity.configure(
        DatabaseSecurityOptions.plaintext(dataDirectory: dir),
      );
      addTearDown(DatabaseSecurity.reset);

      await expectLater(
        DatabaseBootstrap.open(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.databaseMissing,
          ),
        ),
      );
      expect(
        await File(
          '${dir.path}${Platform.pathSeparator}locus_planner.db',
        ).exists(),
        isFalse,
      );
    });

    test('rejects plaintext bytes under an encrypted identity', () async {
      final dir = await Directory.systemTemp.createTemp('locus-downgrade-');
      addTearDown(() => dir.delete(recursive: true));
      final database = File(
        '${dir.path}${Platform.pathSeparator}locus_planner.db',
      );
      await database.writeAsBytes(
        utf8.encode(DatabaseFileInspector.sqliteHeader),
      );
      final metadataStore = DatabaseMetadataStore(
        File('${database.path}.meta.json'),
      );
      await metadataStore.write(_metadata());

      DatabaseSecurity.configure(
        DatabaseSecurityOptions.plaintext(dataDirectory: dir),
      );
      addTearDown(DatabaseSecurity.reset);

      await expectLater(
        DatabaseBootstrap.open(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
          ),
        ),
      );
    });
  });

  group('database path resolver', () {
    Future<Directory> tempDir(String prefix) async {
      final dir = await Directory.systemTemp.createTemp('locus-$prefix-');
      addTearDown(() => dir.delete(recursive: true));
      return dir;
    }

    File databaseIn(Directory dir) => File(
      '${dir.path}${Platform.pathSeparator}${DatabasePaths.databaseFileName}',
    );

    Future<void> createPlaintextDatabase(File file) async {
      await file.parent.create(recursive: true);
      final db = sqlite3.sqlite3.open(file.path);
      try {
        db.execute('CREATE TABLE marker (value TEXT NOT NULL)');
        db.execute("INSERT INTO marker (value) VALUES ('legacy')");
      } finally {
        db.dispose();
      }
    }

    Future<DatabasePaths> resolve({
      required Directory target,
      required Directory support,
      required Directory documents,
    }) => DatabasePathsResolver.resolve(
      options: DatabaseSecurityOptions.plaintext(dataDirectory: target),
      legacySupportDirectory: support,
      legacyDocumentsDirectory: documents,
    );

    test('moves a plaintext support database with its metadata', () async {
      final target = await tempDir('target');
      final support = await tempDir('support');
      final documents = await tempDir('documents');
      final legacy = databaseIn(support);
      await createPlaintextDatabase(legacy);
      await File('${legacy.path}.meta.json').writeAsString('{"v":1}');

      final paths = await resolve(
        target: target,
        support: support,
        documents: documents,
      );

      expect(paths.databaseFile.path, databaseIn(target).path);
      expect(
        await DatabaseFileInspector.classify(paths.databaseFile),
        DatabaseFileKind.plaintext,
      );
      expect(paths.metadataFile.path, '${databaseIn(target).path}.meta.json');
      expect(await paths.metadataFile.readAsString(), '{"v":1}');
      expect(
        target.listSync().where((entry) => entry.path.contains('.move-')),
        isEmpty,
      );
      final db = sqlite3.sqlite3.open(paths.databaseFile.path);
      try {
        expect(db.select('SELECT value FROM marker').single['value'], 'legacy');
      } finally {
        db.dispose();
      }
      // The plaintext original stays behind for explicit user cleanup.
      expect(await legacy.exists(), isTrue);
      // In the normal case the new directory owns the security sidecars.
      expect(paths.dataDirectory.path, target.path);
      expect(paths.legacyDocumentsFile, isNull);
    });

    test('falls back to the Documents copy when support is empty', () async {
      final target = await tempDir('target');
      final support = await tempDir('support');
      final documents = await tempDir('documents');
      final legacy = databaseIn(documents);
      await createPlaintextDatabase(legacy);

      final paths = await resolve(
        target: target,
        support: support,
        documents: documents,
      );

      expect(paths.databaseFile.path, databaseIn(target).path);
      expect(await paths.databaseFile.exists(), isTrue);
      expect(paths.legacyDocumentsFile?.path, legacy.path);
      expect(await legacy.exists(), isTrue);
    });

    test('keeps a legacy database with a journal in place', () async {
      final target = await tempDir('target');
      final support = await tempDir('support');
      final documents = await tempDir('documents');
      final legacy = databaseIn(support);
      await createPlaintextDatabase(legacy);
      await File('${legacy.path}.migration.json').writeAsString('{}');

      final paths = await resolve(
        target: target,
        support: support,
        documents: documents,
      );

      // The journal stores absolute paths, so recovery must find the database,
      // metadata and journal together in the legacy directory.
      expect(paths.databaseFile.path, legacy.path);
      expect(paths.dataDirectory.path, support.path);
      expect(paths.metadataFile.path, '${legacy.path}.meta.json');
      expect(paths.migrationJournalFile.path, '${legacy.path}.migration.json');
      expect(await databaseIn(target).exists(), isFalse);
    });

    test('leaves an existing new database and legacy copy untouched', () async {
      final target = await tempDir('target');
      final support = await tempDir('support');
      final documents = await tempDir('documents');
      await createPlaintextDatabase(databaseIn(target));
      final legacy = databaseIn(support);
      await createPlaintextDatabase(legacy);

      final paths = await resolve(
        target: target,
        support: support,
        documents: documents,
      );

      expect(paths.databaseFile.path, databaseIn(target).path);
      expect(paths.dataDirectory.path, target.path);
      expect(await legacy.exists(), isTrue);
    });
  });

  group('backup passphrase store', () {
    Future<Directory> tempDir(String prefix) async {
      final dir = await Directory.systemTemp.createTemp('locus-$prefix-');
      addTearDown(() => dir.delete(recursive: true));
      return dir;
    }

    test('Windows DPAPI store round-trips and preserves damage', () async {
      if (!Platform.isWindows) return;
      final dir = await tempDir('passphrase');
      final store = WindowsDpapiBackupPassphraseStore(directory: dir);
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${WindowsDpapiBackupPassphraseStore.fileName}',
      );

      expect(await store.read(), isNull);
      await store.write('correct horse battery');
      expect(await store.read(), 'correct horse battery');
      expect(await file.exists(), isTrue);
      expect(
        utf8.decode(await file.readAsBytes(), allowMalformed: true),
        isNot(contains('correct horse battery')),
      );

      await store.write('a second long passphrase');
      expect(await store.read(), 'a second long passphrase');

      await file.writeAsBytes(<int>[9, 9, 9]);
      await expectLater(store.read(), throwsA(isA<FormatException>()));
      expect(await file.exists(), isTrue);

      await store.delete();
      expect(await file.exists(), isFalse);
    });

    test('a legacy passphrase migrates on first read', () async {
      final legacy = _TestPassphraseStore()..value = 'legacy passphrase';
      final primary = _TestPassphraseStore();
      final store = MigratingBackupPassphraseStore(
        primary: primary,
        legacy: legacy,
      );

      expect(await store.read(), 'legacy passphrase');
      expect(primary.value, 'legacy passphrase');
      expect(legacy.value, isNull);

      await store.write('a newer passphrase');
      expect(primary.value, 'a newer passphrase');
      expect(await store.read(), 'a newer passphrase');

      await store.delete();
      expect(primary.value, isNull);
      expect(legacy.value, isNull);
    });

    test('a failed migration still returns the legacy passphrase', () async {
      final legacy = _TestPassphraseStore()..value = 'legacy passphrase';
      final primary = _TestPassphraseStore()..failWrites = true;
      final store = MigratingBackupPassphraseStore(
        primary: primary,
        legacy: legacy,
      );

      expect(await store.read(), 'legacy passphrase');
      expect(legacy.value, 'legacy passphrase');
    });

    test('a damaged primary is not replaced by the legacy value', () async {
      final legacy = _TestPassphraseStore()..value = 'old passphrase';
      final primary = _TestPassphraseStore()..failReads = true;
      final store = MigratingBackupPassphraseStore(
        primary: primary,
        legacy: legacy,
      );

      await expectLater(store.read(), throwsA(isA<StateError>()));
      expect(legacy.value, 'old passphrase');
    });
  });

  group('Windows DPAPI key store', () {
    test('protects, reads back and preserves a damaged store', () async {
      if (!Platform.isWindows) return;
      final dir = await Directory.systemTemp.createTemp('locus-dpapi-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(
        '${dir.path}${Platform.pathSeparator}database_keys.dat',
      );
      final store = WindowsDpapiDatabaseKeyStore(file: file);
      final record = DatabaseKeyRecord(
        keyId: 'key-0001',
        generation: 1,
        databaseId: 'db-test',
        cipherProfileId: 'locus-sqlcipher4-raw-v1',
        bytes: KeyDerivation.randomBytes(32),
        createdAt: _fixedDate,
        active: true,
      );

      await store.write(record);
      expect(await file.exists(), isTrue);
      expect((await store.read('key-0001'))!.hex, record.hex);

      // A second save replaces the existing DPAPI blob. This is the step that
      // used to fail on Windows when rename() refused an existing destination.
      await store.markActive('key-0001');
      expect((await store.read('key-0001'))!.active, isTrue);

      final raw = await file.readAsBytes();
      expect(
        utf8.decode(raw, allowMalformed: true),
        isNot(contains('key-0001')),
      );

      await file.writeAsBytes(<int>[0, 1, 2, 3]);
      await expectLater(
        store.listVersions(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.keyStoreCorrupt,
          ),
        ),
      );
      // Evidence is preserved: a failed decrypt must never delete the file.
      expect(await file.exists(), isTrue);
    });
  });
}

final _fixedDate = DateTime.utc(2026, 11, 3);

class _TestPassphraseStore implements BackupPassphraseStore {
  String? value;
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<String?> read() async {
    if (failReads) throw StateError('vault unavailable');
    return value;
  }

  @override
  Future<void> write(String newValue) async {
    if (failWrites) throw StateError('vault unavailable');
    value = newValue;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
