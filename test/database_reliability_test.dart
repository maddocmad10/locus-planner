import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/database_maintenance.dart';
import 'package:locus_planner/core/security/atomic_file.dart';
import 'package:locus_planner/core/security/database_bootstrap.dart';
import 'package:locus_planner/core/security/database_artifact_inventory.dart';
import 'package:locus_planner/core/security/database_classifier.dart';
import 'package:locus_planner/core/security/database_file_inspector.dart';
import 'package:locus_planner/core/security/database_identity.dart';
import 'package:locus_planner/core/security/database_key_service.dart';
import 'package:locus_planner/core/security/database_key_store.dart';
import 'package:locus_planner/core/security/database_lifecycle_lock.dart';
import 'package:locus_planner/core/security/database_metadata.dart';
import 'package:locus_planner/core/security/database_parity_verifier.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/database_security_errors.dart';
import 'package:locus_planner/core/security/database_security_options.dart';
import 'package:locus_planner/core/security/migration_journal.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _profileId = 'locus-sqlcipher4-raw-v1';

DatabasePaths _paths(Directory directory) => DatabasePaths(
  dataDirectory: directory,
  databaseFile: File(p.join(directory.path, DatabasePaths.databaseFileName)),
);

DatabaseMetadata _metadata({
  String databaseId = 'db-test',
  String keyId = 'key-0001',
  int generation = 1,
  bool encrypted = true,
}) => DatabaseMetadata(
  databaseId: databaseId,
  activeKeyId: keyId,
  keyGeneration: generation,
  cipherProfileId: _profileId,
  encryptionEnabled: encrypted,
  databaseFile: DatabasePaths.databaseFileName,
  createdAt: DateTime.utc(2026, 11, 4),
);

/// Creates a real SQLite file with the tables the classifier recognizes.
void _createPlaintext(
  File file, {
  int userVersion = currentDatabaseSchemaVersion,
  List<String> tables = const <String>['events', 'app_settings'],
}) {
  final db = sqlite3.sqlite3.open(file.path);
  try {
    for (final table in tables) {
      db.execute('CREATE TABLE $table (id TEXT PRIMARY KEY)');
    }
    db.execute('PRAGMA user_version = $userVersion');
  } finally {
    db.dispose();
  }
}

Future<DatabaseClassification> _classify(
  DatabasePaths paths, {
  DatabaseKeyStore? keyStore,
}) => DatabaseClassifier.classify(
  paths: paths,
  metadataStore: DatabaseMetadataStore(paths.metadataFile),
  journalStore: MigrationJournalStore(paths.migrationJournalFile),
  keyStore: keyStore,
);

DatabaseKeyRecord _record(
  String keyId,
  int generation, {
  String databaseId = 'db-test',
  bool active = false,
}) => DatabaseKeyRecord(
  keyId: keyId,
  generation: generation,
  databaseId: databaseId,
  cipherProfileId: _profileId,
  bytes: Uint8List.fromList(List<int>.generate(32, (index) => index)),
  createdAt: DateTime.utc(2026, 11, 4),
  active: active,
);

MigrationJournal _journal({
  MigrationStage stage = MigrationStage.conversionStarted,
  String? lastErrorCode,
  String? tempChecksum,
}) => MigrationJournal(
  migrationId: 'migration-test',
  databaseId: 'db-test',
  stage: stage,
  sourcePath: 'locus_planner.db',
  sourceSidecars: const <String>['locus_planner.db-wal'],
  sourceSchemaVersion: 15,
  targetSchemaVersion: currentDatabaseSchemaVersion,
  backupPath: 'backup.plaintext.bak',
  tempPath: 'locus_planner.db.encrypting',
  quarantinePath: 'quarantine/db-test',
  newKeyId: 'key-0001',
  newKeyGeneration: 1,
  cipherProfileId: _profileId,
  sourceChecksum: 'sha256:source',
  tempChecksum: tempChecksum,
  lastErrorCode: lastErrorCode,
  startedAt: DateTime.utc(2026, 11, 4),
  updatedAt: DateTime.utc(2026, 11, 4),
  pid: 1234,
);

void main() {
  group('A-START startup classification', () {
    late Directory directory;
    late DatabasePaths paths;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-start-');
      paths = _paths(directory);
    });

    tearDown(() => directory.delete(recursive: true));

    test('a missing file with no metadata, journal or keys is fresh', () async {
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.freshInstall);
      expect(result.canCreateFresh, isTrue);
      expect(result.mustFailClosed, isFalse);
    });

    test('a recognized plaintext database is opened as plaintext', () async {
      _createPlaintext(paths.databaseFile);
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recognizedPlaintext);
      expect(result.canOpenPlaintext, isTrue);
    });

    test('a newer plaintext schema is rejected', () async {
      _createPlaintext(
        paths.databaseFile,
        userVersion: currentDatabaseSchemaVersion + 1,
      );
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.unsupportedEncryption);
    });

    test('an unrelated SQLite file is not adopted', () async {
      _createPlaintext(paths.databaseFile, tables: const <String>['invoices']);
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.unknownDatabase);
      expect(result.mustFailClosed, isTrue);
    });

    test('an empty file is reported instead of recreated', () async {
      await paths.databaseFile.writeAsBytes(const <int>[]);
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.emptyDatabase);
      expect(result.errorCode, DatabaseSecurityErrorCode.zeroLengthDatabase);
    });

    test('a truncated file is corrupt', () async {
      await paths.databaseFile.writeAsBytes(const <int>[1, 2, 3]);
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.corruptedDatabase);
      expect(result.errorCode, DatabaseSecurityErrorCode.databaseDamaged);
    });

    test('an unknown header is never treated as plaintext', () async {
      await paths.databaseFile.writeAsBytes(List<int>.filled(4096, 0x5a));
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.fileKind, DatabaseFileKind.encryptedOrUnknown);
      expect(result.errorCode, DatabaseSecurityErrorCode.recoveryRequired);
    });

    test('plaintext bytes under an encrypted identity fail closed', () async {
      _createPlaintext(paths.databaseFile);
      await DatabaseMetadataStore(paths.metadataFile).write(_metadata());
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(
        result.errorCode,
        DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
      );
    });

    test('missing file plus metadata is a recovery situation', () async {
      await DatabaseMetadataStore(paths.metadataFile).write(_metadata());
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.databaseMissing);
    });

    test('keys without a database are not a fresh install', () async {
      final store = InMemoryDatabaseKeyStore();
      await store.write(_record('key-0001', 1, active: true));
      final result = await _classify(paths, keyStore: store);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.recoveryRequired);
    });

    test('an encrypted file with a matching key is openable', () async {
      final store = InMemoryDatabaseKeyStore();
      final key = await DatabaseKeyService(
        store,
      ).createFresh(databaseId: 'db-test', cipherProfileId: _profileId);
      await paths.databaseFile.writeAsBytes(List<int>.filled(4096, 0x33));
      await DatabaseMetadataStore(
        paths.metadataFile,
      ).write(_metadata(keyId: key.keyId));

      final result = await _classify(paths, keyStore: store);
      expect(result.state, DatabaseStartupState.encryptedDatabase);
      expect(result.databaseId, 'db-test');
      expect(result.keyId, key.keyId);
    });

    test('an encrypted file without its active key needs recovery', () async {
      final store = InMemoryDatabaseKeyStore();
      await paths.databaseFile.writeAsBytes(List<int>.filled(4096, 0x33));
      await DatabaseMetadataStore(paths.metadataFile).write(_metadata());
      final result = await _classify(paths, keyStore: store);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.keyMissing);
    });

    test('two active keys are ambiguous, not resolved by guessing', () async {
      final store = InMemoryDatabaseKeyStore();
      await store.write(_record('key-0001', 1, active: true));
      await store.write(_record('key-0002', 2, active: true));
      await paths.databaseFile.writeAsBytes(List<int>.filled(4096, 0x33));
      await DatabaseMetadataStore(paths.metadataFile).write(_metadata());
      final result = await _classify(paths, keyStore: store);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.recoveryRequired);
    });

    test(
      'an interrupted migration is recognized before file inspection',
      () async {
        await MigrationJournalStore(
          paths.migrationJournalFile,
        ).write(_journal());
        final result = await _classify(paths);
        expect(result.state, DatabaseStartupState.interruptedMigration);
        expect(result.needsMigrationRecovery, isTrue);
        expect(result.journal?.databaseId, 'db-test');
      },
    );

    test('a corrupt journal is a recovery error', () async {
      await paths.migrationJournalFile.writeAsString('{');
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.migrationInterrupted);
    });

    test('restore and rotation journals stop normal startup', () async {
      await paths.restoreJournalFile.writeAsString('{}');
      final restore = await _classify(paths);
      expect(restore.state, DatabaseStartupState.interruptedRestore);

      await paths.restoreJournalFile.delete();
      await paths.rotationJournalFile.writeAsString('{}');
      final rotation = await _classify(paths);
      expect(rotation.state, DatabaseStartupState.interruptedRotation);
    });

    test(
      'bootstrap never rewrites an unknown encrypted-looking file',
      () async {
        final bytes = List<int>.generate(4096, (index) => (index * 7) % 256);
        bytes[0] = 0x00;
        await paths.databaseFile.writeAsBytes(bytes);

        DatabaseSecurity.configure(
          DatabaseSecurityOptions.encrypted(
            dataDirectory: directory,
            keyStore: InMemoryDatabaseKeyStore(),
          ),
        );
        addTearDown(DatabaseSecurity.reset);

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
        expect(await paths.databaseFile.readAsBytes(), bytes);
        expect(await paths.metadataFile.exists(), isFalse);
      },
    );

    test('a malformed metadata file is a recovery error', () async {
      await paths.metadataFile.writeAsString('{"formatVersion": 99}');
      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.metadataCorrupt);
    });

    test('a format-2 identity table without updated_at stays readable', () {
      final db = sqlite3.sqlite3.openInMemory();
      addTearDown(db.dispose);
      db.execute('''
        CREATE TABLE ${DatabaseIdentity.tableName} (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          database_id TEXT NOT NULL,
          key_id TEXT NOT NULL,
          key_generation INTEGER NOT NULL,
          cipher_profile_id TEXT NOT NULL,
          format_version INTEGER NOT NULL,
          created_at TEXT NOT NULL
        )
      ''');
      db.execute(
        'INSERT INTO ${DatabaseIdentity.tableName} '
        '(id, database_id, key_id, key_generation, cipher_profile_id, '
        'format_version, created_at) '
        "VALUES (1, 'db-test', 'key-0001', 1, ?, 2, '2026-11-04T00:00:00Z')",
        <Object?>[_profileId],
      );

      final identity = DatabaseIdentityStore.read(db);
      expect(identity, isNotNull);
      expect(identity!.formatVersion, 2);
      expect(identity.updatedAt, isNull);

      DatabaseIdentityStore.write(
        db,
        identity.copyWith(updatedAt: DateTime.utc(2026, 11, 4, 1)),
      );
      expect(
        DatabaseIdentityStore.read(db)!.updatedAt,
        DateTime.utc(2026, 11, 4, 1),
      );
    });
  });

  group('A-ART artifact inventory', () {
    late Directory directory;
    late DatabasePaths paths;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-artifacts-');
      paths = _paths(directory);
    });

    tearDown(() => directory.delete(recursive: true));

    Future<File> write(String name) async {
      final file = File(p.join(directory.path, name));
      await file.parent.create(recursive: true);
      await file.writeAsString(name);
      return file;
    }

    test(
      'discovers candidates, temporaries, quarantine and sidecars',
      () async {
        final candidate = await write('locus_planner.db.encrypting-123');
        final metadataTemp = await write('locus_planner.db.meta.json.tmp-1');
        final moveTemp = await write('locus_planner.db.move-1.tmp');
        final wal = await write('locus_planner.db-wal');
        final quarantine = Directory(
          p.join(directory.path, 'quarantine', 'q1'),
        );
        await quarantine.create(recursive: true);

        final inventory = await DatabaseArtifactInventory.scan(paths);
        expect(
          inventory.conversionCandidates.map((file) => p.basename(file.path)),
          <String>[p.basename(candidate.path)],
        );
        expect(
          inventory.atomicTemporaries.map((file) => p.basename(file.path)),
          containsAll(<String>[
            p.basename(metadataTemp.path),
            p.basename(moveTemp.path),
          ]),
        );
        expect(inventory.quarantineDirectories.map((dir) => dir.path), <String>[
          quarantine.path,
        ]);
        expect(
          inventory.sidecars.map((file) => p.basename(file.path)),
          <String>[p.basename(wal.path)],
        );
        expect(inventory.hasJournal, isFalse);
        expect(inventory.hasUnjournaledConversionCandidate, isTrue);
      },
    );

    test('cleanup preserves candidates and quarantine evidence', () async {
      final candidate = await write('locus_planner.db.encrypting-123');
      final temporary = await write('locus_planner.db.meta.json.tmp-1');
      final quarantine = Directory(p.join(directory.path, 'quarantine', 'q1'));
      await quarantine.create(recursive: true);

      final inventory = await DatabaseArtifactInventory.scan(paths);
      expect(await inventory.cleanupAtomicTemporaries(), 1);
      expect(await temporary.exists(), isFalse);
      expect(await candidate.exists(), isTrue);
      expect(await quarantine.exists(), isTrue);
    });

    test('cleanup is skipped while a journal exists', () async {
      final temporary = await write('locus_planner.db.meta.json.tmp-1');
      await write('locus_planner.db.migration.json');

      final inventory = await DatabaseArtifactInventory.scan(paths);
      expect(inventory.hasJournal, isTrue);
      expect(await inventory.cleanupAtomicTemporaries(), 0);
      expect(await temporary.exists(), isTrue);
    });

    test('an unjournaled candidate fails classification', () async {
      _createPlaintext(paths.databaseFile);
      await write('locus_planner.db.encrypting-123');

      final result = await _classify(paths);
      expect(result.state, DatabaseStartupState.recoveryRequired);
      expect(result.errorCode, DatabaseSecurityErrorCode.migrationInterrupted);
    });
  });

  group('A-KEY key record identity validation', () {
    test(
      'rejects a key from another database, generation or profile',
      () async {
        final service = DatabaseKeyService(InMemoryDatabaseKeyStore());
        final key = await service.createFresh(
          databaseId: 'db-test',
          cipherProfileId: _profileId,
        );

        Future<void> expectMismatch(Future<DatabaseKey> future) => expectLater(
          future,
          throwsA(
            isA<DatabaseSecurityException>().having(
              (error) => error.code,
              'code',
              DatabaseSecurityErrorCode.identityMismatch,
            ),
          ),
        );

        await expectMismatch(
          service.requireValid(
            keyId: key.keyId,
            databaseId: 'db-other',
            generation: key.generation,
            cipherProfileId: _profileId,
          ),
        );
        await expectMismatch(
          service.requireValid(
            keyId: key.keyId,
            databaseId: 'db-test',
            generation: key.generation + 1,
            cipherProfileId: _profileId,
          ),
        );
        await expectMismatch(
          service.requireValid(
            keyId: key.keyId,
            databaseId: 'db-test',
            generation: key.generation,
            cipherProfileId: 'another-profile',
          ),
        );
      },
    );

    test('a missing key slot is reported as such', () async {
      final service = DatabaseKeyService(InMemoryDatabaseKeyStore());
      await expectLater(
        service.requireValid(
          keyId: 'key-9999',
          databaseId: 'db-test',
          generation: 9,
          cipherProfileId: _profileId,
        ),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.keyMissing,
          ),
        ),
      );
    });

    test('keys shorter or longer than 32 bytes are corrupt', () {
      for (final length in <int>[16, 33]) {
        final key = DatabaseKey(
          databaseId: 'db-test',
          keyId: 'key-0001',
          generation: 1,
          cipherProfileId: _profileId,
          bytes: Uint8List(length),
          createdAt: DateTime.utc(2026, 11, 4),
        );
        expect(
          () => key.requireMatches(
            databaseId: 'db-test',
            keyId: 'key-0001',
            generation: 1,
            cipherProfileId: _profileId,
          ),
          throwsA(
            isA<DatabaseSecurityException>().having(
              (error) => error.code,
              'code',
              DatabaseSecurityErrorCode.keyStoreCorrupt,
            ),
          ),
          reason: 'length $length must be rejected',
        );
      }
    });

    test('external metadata must match every identity field', () {
      final identity = DatabaseIdentity(
        databaseId: 'db-test',
        keyId: 'key-0001',
        keyGeneration: 1,
        cipherProfileId: _profileId,
        createdAt: DateTime.utc(2026, 11, 4),
      );
      final mismatches = <DatabaseMetadata>[
        _metadata(databaseId: 'db-other'),
        _metadata(keyId: 'key-0002'),
        _metadata(generation: 2),
      ];
      for (final metadata in mismatches) {
        expect(
          () => identity.requireMatches(metadata),
          throwsA(
            isA<DatabaseSecurityException>().having(
              (error) => error.code,
              'code',
              DatabaseSecurityErrorCode.identityMismatch,
            ),
          ),
        );
      }
    });

    test('more than one active key is rejected', () async {
      final store = InMemoryDatabaseKeyStore();
      await store.write(_record('key-0001', 1, active: true));
      await store.write(_record('key-0002', 2, active: true));
      await expectLater(
        DatabaseKeyService(store).requireSingleActiveKey(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.recoveryRequired,
          ),
        ),
      );
    });

    test('the Windows store keeps the previous committed generation', () async {
      if (!Platform.isWindows) return;
      final directory = await Directory.systemTemp.createTemp('locus-keys-');
      addTearDown(() => directory.delete(recursive: true));
      final store = WindowsDpapiDatabaseKeyStore(
        file: File(p.join(directory.path, 'database_keys.dat')),
      );

      await store.write(_record('key-0001', 1, active: true));
      await store.write(_record('key-0002', 2, active: true));

      expect(
        (await store.listVersions()).map((record) => record.keyId),
        <String>['key-0001', 'key-0002'],
      );
      expect(
        (await store.listPreviousVersions()).map((record) => record.keyId),
        <String>['key-0001'],
      );
    });
  });

  group('A-FILE atomic replacement', () {
    late Directory directory;
    late File destination;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-file-');
      destination = File(p.join(directory.path, 'target.bin'));
    });

    tearDown(() => directory.delete(recursive: true));

    test(
      'overwrites an existing file and leaves no temporary sibling',
      () async {
        await AtomicFile.writeString(destination, 'first');
        await AtomicFile.writeString(destination, 'second');

        expect(await destination.readAsString(), 'second');
        expect(
          directory.listSync().where(
            (entity) =>
                entity.path.contains('.tmp-') || entity.path.contains('.copy-'),
          ),
          isEmpty,
        );
      },
    );

    test('a failed replace leaves the destination untouched', () async {
      await destination.writeAsString('original');
      final missing = File(p.join(directory.path, 'missing.bin'));

      await expectLater(
        AtomicFile.replaceAtomically(missing, destination),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.readAsString(), 'original');
    });

    test('copyAndVerify promotes a verified copy', () async {
      final source = File(p.join(directory.path, 'source.bin'));
      final bytes = List<int>.generate(512, (index) => index % 256);
      await source.writeAsBytes(bytes);

      await AtomicFile.copyAndVerify(source, destination);
      expect(await destination.readAsBytes(), bytes);
      expect(
        await AtomicFile.checksum(destination),
        await AtomicFile.checksum(source),
      );
    });

    test('verifyFile rejects a checksum mismatch', () async {
      await destination.writeAsString('content');
      final checksum = await AtomicFile.checksum(destination);

      await AtomicFile.verifyFile(destination, checksum);
      await expectLater(
        AtomicFile.verifyFile(destination, 'sha256:${'0' * 64}'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('A-MIG migration journal', () {
    late Directory directory;
    late MigrationJournalStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-mig-');
      store = MigrationJournalStore(
        File(p.join(directory.path, 'db.migration.json')),
      );
    });

    tearDown(() => directory.delete(recursive: true));

    test('records every stage and survives a restart', () async {
      final journal = _journal(tempChecksum: 'sha256:candidate');
      await store.write(journal);

      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.migrationId, 'migration-test');
      expect(read.stage, MigrationStage.conversionStarted);
      expect(read.sourceChecksum, 'sha256:source');
      expect(read.tempChecksum, 'sha256:candidate');
      expect(read.sourceSidecars.single, endsWith('-wal'));
      expect(read.pid, 1234);
      expect(read.needsRecovery, isTrue);
    });

    test('never advances backwards', () {
      final journal = _journal(stage: MigrationStage.destinationVerified);
      expect(
        () => journal.advance(MigrationStage.conversionStarted),
        throwsStateError,
      );
      expect(
        journal.advance(MigrationStage.completed).stage,
        MigrationStage.completed,
      );
    });

    test('decodes legacy stage names', () async {
      await store.write(_journal(stage: MigrationStage.completed));
      final encoded = await store.file.readAsString();
      final legacy = encoded.replaceFirst(
        '"stage": "completed"',
        '"stage": "migrationComplete"',
      );
      expect(MigrationJournal.decode(legacy).stage, MigrationStage.completed);
    });

    test('a failed stage stays recoverable', () {
      final failed = _journal().fail('CONVERSION_FAILED');
      expect(failed.stage, MigrationStage.recoveryRequired);
      expect(failed.lastErrorCode, 'CONVERSION_FAILED');
      expect(failed.needsRecovery, isTrue);
    });

    test('a corrupt or unsupported journal is a recovery error', () async {
      await store.file.writeAsString('{');
      await expectLater(
        store.read(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.migrationInterrupted,
          ),
        ),
      );

      await store.write(_journal());
      final encoded = await store.file.readAsString();
      await store.file.writeAsString(
        encoded.replaceFirst('"formatVersion": 1', '"formatVersion": 99'),
      );
      await expectLater(
        store.read(),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.migrationInterrupted,
          ),
        ),
      );
    });
  });

  group('A-PARITY source-to-destination comparison', () {
    late Directory directory;
    late File sourceFile;
    late File targetFile;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-parity-');
      sourceFile = File(p.join(directory.path, 'source.db'));
      targetFile = File(p.join(directory.path, 'target.db'));
      _createPlaintext(sourceFile);
      _createPlaintext(targetFile);
    });

    tearDown(() => directory.delete(recursive: true));

    Future<DatabaseParityReport> compare() async {
      final source = sqlite3.sqlite3.open(sourceFile.path);
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        return DatabaseParityVerifier.compare(source: source, target: target);
      } finally {
        source.dispose();
        target.dispose();
      }
    }

    test('identical databases match', () async {
      final report = await compare();
      expect(report.matches, isTrue, reason: report.mismatches.join('; '));
      expect(report.tableCount, 2);
      expect(report.sourceSchemaVersion, currentDatabaseSchemaVersion);
    });

    test('a changed row is detected', () async {
      for (final file in <File>[sourceFile, targetFile]) {
        final db = sqlite3.sqlite3.open(file.path);
        try {
          db.execute("INSERT INTO events (id) VALUES ('event-1')");
        } finally {
          db.dispose();
        }
      }
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        target.execute("UPDATE events SET id = 'event-2' WHERE id = 'event-1'");
      } finally {
        target.dispose();
      }

      final report = await compare();
      expect(report.matches, isFalse);
      expect(report.mismatches.any((line) => line.contains('events')), isTrue);
    });

    test('a missing table is detected', () async {
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        target.execute('DROP TABLE app_settings');
      } finally {
        target.dispose();
      }
      final report = await compare();
      expect(report.matches, isFalse);
      expect(
        report.mismatches.any(
          (line) =>
              line.contains('schema object count') ||
              line.contains('table list differs'),
        ),
        isTrue,
      );
    });

    test('a schema version difference is detected', () async {
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        target.execute('PRAGMA user_version = 15');
      } finally {
        target.dispose();
      }
      final report = await compare();
      expect(report.matches, isFalse);
      expect(
        report.mismatches.any((line) => line.contains('user_version')),
        isTrue,
      );
    });

    test('the internal identity table is excluded from parity', () async {
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        target.execute(
          'CREATE TABLE db_security_identity (id INTEGER PRIMARY KEY)',
        );
      } finally {
        target.dispose();
      }
      final report = await compare();
      expect(report.matches, isTrue, reason: report.mismatches.join('; '));
    });

    test('requireParity throws a damaged-database error', () async {
      final target = sqlite3.sqlite3.open(targetFile.path);
      try {
        target.execute('DROP TABLE events');
      } finally {
        target.dispose();
      }
      final source = sqlite3.sqlite3.open(sourceFile.path);
      final other = sqlite3.sqlite3.open(targetFile.path);
      try {
        expect(
          () => DatabaseParityVerifier.requireParity(
            source: source,
            target: other,
          ),
          throwsA(
            isA<DatabaseSecurityException>().having(
              (error) => error.code,
              'code',
              DatabaseSecurityErrorCode.databaseDamaged,
            ),
          ),
        );
      } finally {
        source.dispose();
        other.dispose();
      }
    });
  });

  group('A-LIFE lifecycle lock', () {
    late Directory directory;
    late File lockFile;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('locus-lock-');
      lockFile = File(p.join(directory.path, 'db.lifecycle.lock'));
    });

    tearDown(() => directory.delete(recursive: true));

    // Windows locks are handle-scoped, so two handles in one process
    // conflict. Linux/Android advisory locks are process-scoped and cannot
    // model contention inside a single test process.
    final canContend = Platform.isWindows;

    test('contention times out with a stable error code', () async {
      if (!canContend) return;
      final held = await DatabaseLifecycleLock(
        lockFile,
      ).acquire(DatabaseLockMode.exclusive);
      addTearDown(held.release);

      await expectLater(
        DatabaseLifecycleLock(
          lockFile,
          timeout: const Duration(milliseconds: 150),
          retryDelay: const Duration(milliseconds: 10),
        ).acquire(DatabaseLockMode.exclusive),
        throwsA(
          isA<DatabaseSecurityException>().having(
            (error) => error.code,
            'code',
            DatabaseSecurityErrorCode.lifecycleBusy,
          ),
        ),
      );
    });

    test('the lock is released after a failure', () async {
      final lock = DatabaseLifecycleLock(lockFile);
      await expectLater(
        lock.withLock(
          DatabaseLockMode.exclusive,
          () async => throw StateError('operation failed'),
        ),
        throwsStateError,
      );

      final handle = await lock.acquire(DatabaseLockMode.exclusive);
      await handle.release();
    });

    test('shared holders do not exclude each other', () async {
      final first = await DatabaseLifecycleLock(
        lockFile,
      ).acquire(DatabaseLockMode.shared);
      final second = await DatabaseLifecycleLock(
        lockFile,
        timeout: const Duration(milliseconds: 150),
        retryDelay: const Duration(milliseconds: 10),
      ).acquire(DatabaseLockMode.shared);
      await second.release();
      await first.release();
    });

    test('withLock returns the action result', () async {
      final result = await DatabaseLifecycleLock(
        lockFile,
      ).withLock(DatabaseLockMode.exclusive, () async => 42);
      expect(result, 42);
    });
  });
}
