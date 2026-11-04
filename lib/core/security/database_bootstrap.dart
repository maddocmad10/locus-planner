import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import '../db/database_maintenance.dart';
import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'cipher_profile.dart';
import 'database_artifact_inventory.dart';
import 'database_classifier.dart';
import 'database_file_inspector.dart';
import 'database_identity.dart';
import 'database_key_service.dart';
import 'database_lifecycle_lock.dart';
import 'database_metadata.dart';
import 'database_parity_verifier.dart';
import 'database_paths.dart';
import 'database_rotation_service.dart';
import 'database_security_errors.dart';
import 'database_security_options.dart';
import 'migration_journal.dart';
import 'rotation_journal.dart';
import 'sqlite3mc.dart';

/// Snapshot of what the connection factory decided for the current process.
///
/// `beforeOpen` uses it to verify the internal identity anchor without
/// re-reading (and potentially re-trusting) the external metadata file.
class DatabaseRuntimeContext {
  const DatabaseRuntimeContext({
    required this.paths,
    required this.encryptionEnabled,
    this.metadata,
    this.profile,
    this.activeKeyId,
  });

  static DatabaseRuntimeContext? current;

  final DatabasePaths paths;
  final bool encryptionEnabled;
  final DatabaseMetadata? metadata;
  final CipherProfile? profile;
  final String? activeKeyId;
}

/// The single entry point for every production database connection.
///
/// Classification happens before Drift is allowed to touch the file:
///
/// * missing file + no metadata/journal/keys -> create a new identity
/// * recognized plaintext + encryption off -> standard SQLite open
/// * recognized plaintext + encryption on -> controlled conversion
/// * encrypted file + metadata + key -> verify the internal anchor, then open
/// * anything inconsistent -> fail closed with a recovery error
abstract final class DatabaseBootstrap {
  static Future<QueryExecutor> open() async {
    final options = DatabaseSecurity.current;
    if (options.encryptLiveDatabase) {
      // The cipher must be loaded and proven before any consumer can open the
      // database. A failure here is a startup error, not a plaintext fallback.
      Sqlite3mcLoader.ensureConfigured();
      await Sqlite3mcLoader.requireVerified(profile: options.profile);
    }
    final paths = await DatabasePathsResolver.resolve(options: options);
    final lock = DatabaseLifecycleLock(paths.lifecycleLockFile);
    return lock.withLock(
      DatabaseLockMode.exclusive,
      () => _openLocked(options: options, paths: paths),
    );
  }

  /// Rotates the DEK of the live encrypted database.
  ///
  /// The caller must ensure the database is closed. Rotation runs under the
  /// exclusive lifecycle lock and keeps the pre-rotation database and old key
  /// record until the replacement has been verified.
  static Future<DatabaseMetadata> rotateKey() async {
    if (DatabaseRuntimeContext.current != null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.lifecycleBusy,
        'The application database is open. Close it before rotating the key.',
      );
    }
    final options = DatabaseSecurity.current;
    final keyStore = options.keyStore;
    if (!options.encryptLiveDatabase || keyStore == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'Key rotation requires live encryption and a key store.',
      );
    }
    Sqlite3mcLoader.ensureConfigured();
    await Sqlite3mcLoader.requireVerified(profile: options.profile);

    final paths = await DatabasePathsResolver.resolve(options: options);
    final lock = DatabaseLifecycleLock(paths.lifecycleLockFile);
    return lock.withLock(DatabaseLockMode.exclusive, () async {
      final metadataStore = DatabaseMetadataStore(paths.metadataFile);
      final migrationStore = MigrationJournalStore(paths.migrationJournalFile);
      final rotationStore = RotationJournalStore(paths.rotationJournalFile);
      final keyService = DatabaseKeyService(keyStore);

      final classification = await DatabaseClassifier.classify(
        paths: paths,
        metadataStore: metadataStore,
        journalStore: migrationStore,
        keyStore: keyStore,
        maximumPlaintextSchemaVersion: currentDatabaseSchemaVersion,
      );
      if (classification.state != DatabaseStartupState.encryptedDatabase) {
        throw classification.toException();
      }
      final metadata = classification.metadata!;
      final profile = CipherProfiles.byId(metadata.cipherProfileId);
      if (profile == null) {
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.unsupportedEncryption,
          'This build does not support cipher profile '
          '"${metadata.cipherProfileId}".',
        );
      }
      await keyService.requireSingleActiveKey();
      final oldKey = await keyService.requireValid(
        keyId: metadata.activeKeyId,
        databaseId: metadata.databaseId,
        generation: metadata.keyGeneration,
        cipherProfileId: metadata.cipherProfileId,
      );

      return DatabaseRotationService.rotate(
        paths: paths,
        metadata: metadata,
        oldKey: oldKey,
        keyService: keyService,
        metadataStore: metadataStore,
        journalStore: rotationStore,
        profile: profile,
      );
    });
  }

  static Future<QueryExecutor> _openLocked({
    required DatabaseSecurityOptions options,
    required DatabasePaths paths,
  }) async {
    final metadataStore = DatabaseMetadataStore(paths.metadataFile);
    final journalStore = MigrationJournalStore(paths.migrationJournalFile);
    final keyStore = options.keyStore;
    if (options.encryptLiveDatabase && keyStore == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'Live encryption is enabled without a key store.',
      );
    }
    final keyService = keyStore == null ? null : DatabaseKeyService(keyStore);

    final classification = await DatabaseClassifier.classify(
      paths: paths,
      metadataStore: metadataStore,
      journalStore: journalStore,
      keyStore: keyStore,
      maximumPlaintextSchemaVersion: currentDatabaseSchemaVersion,
    );

    if (classification.canCreateFresh ||
        classification.canOpenPlaintext ||
        classification.canOpenEncrypted) {
      // Only abandoned atomic-write siblings are removed. Conversion candidates
      // and quarantine evidence stay for recovery.
      await (await DatabaseArtifactInventory.scan(
        paths,
      )).cleanupAtomicTemporaries();
    }

    switch (classification.state) {
      case DatabaseStartupState.interruptedMigration:
        await _recoverInterruptedMigration(
          paths: paths,
          journalStore: journalStore,
          metadataStore: metadataStore,
          keyService: keyService,
        );
        return _openLocked(options: options, paths: paths);

      case DatabaseStartupState.interruptedRotation:
        await _recoverInterruptedRotation(
          paths: paths,
          rotationStore: RotationJournalStore(paths.rotationJournalFile),
          metadataStore: metadataStore,
          keyService: keyService,
        );
        return _openLocked(options: options, paths: paths);

      case DatabaseStartupState.freshInstall:
        if (!options.encryptLiveDatabase) {
          return _openPlaintext(paths, classification.metadata);
        }
        return _createEncrypted(
          paths: paths,
          metadataStore: metadataStore,
          keyService: keyService!,
          profile: options.profile,
        );

      case DatabaseStartupState.recognizedPlaintext:
        if (!options.encryptLiveDatabase) {
          return _openPlaintext(paths, classification.metadata);
        }
        if (!options.allowAutomaticConversion) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            'A plaintext database was recognized, but automatic encryption '
            'migration is disabled in this build. The file was not modified.',
          );
        }
        return _migratePlaintext(
          paths: paths,
          metadataStore: metadataStore,
          journalStore: journalStore,
          keyService: keyService!,
          profile: options.profile,
        );

      case DatabaseStartupState.encryptedDatabase:
        if (!options.encryptLiveDatabase) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.unsupportedEncryption,
            'This build was not started with database encryption enabled.',
          );
        }
        return _openExistingEncrypted(
          paths: paths,
          metadataStore: metadataStore,
          keyService: keyService!,
          metadata: classification.metadata!,
        );

      case DatabaseStartupState.emptyDatabase:
      case DatabaseStartupState.unknownDatabase:
      case DatabaseStartupState.corruptedDatabase:
      case DatabaseStartupState.recoveryRequired:
      case DatabaseStartupState.interruptedRestore:
        throw classification.toException();
    }
  }

  static Future<QueryExecutor> _openPlaintext(
    DatabasePaths paths,
    DatabaseMetadata? metadata,
  ) async {
    if (metadata?.encryptionEnabled == true) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
        'A plaintext database was found where an encrypted one is expected.',
      );
    }
    await backupDatabaseBeforeUpgrade(paths.databaseFile);
    DatabaseRuntimeContext.current = DatabaseRuntimeContext(
      paths: paths,
      encryptionEnabled: false,
      metadata: metadata,
    );
    return NativeDatabase.createInBackground(paths.databaseFile);
  }

  static Future<QueryExecutor> _createEncrypted({
    required DatabasePaths paths,
    required DatabaseMetadataStore metadataStore,
    required DatabaseKeyService keyService,
    required CipherProfile profile,
  }) async {
    final databaseId = 'db-${const Uuid().v4()}';
    final key = await keyService.createFresh(
      databaseId: databaseId,
      cipherProfileId: profile.profileId,
      createdAt: AppClock.now().toUtc(),
    );
    final metadata = DatabaseMetadata(
      databaseId: databaseId,
      activeKeyId: key.keyId,
      keyGeneration: key.generation,
      cipherProfileId: profile.profileId,
      encryptionEnabled: true,
      databaseFile: p.basename(paths.databaseFile.path),
      createdAt: AppClock.now().toUtc(),
      lastOpenedAt: AppClock.now().toUtc(),
    );

    // Provision the internal anchor before the external hint exists. An
    // existing database must never gain an anchor this way.
    _writeIdentityAnchor(paths.databaseFile, profile, key, databaseId);
    await metadataStore.write(metadata);
    _verifyIdentityAnchor(paths.databaseFile, profile, key, metadata);

    DatabaseRuntimeContext.current = DatabaseRuntimeContext(
      paths: paths,
      encryptionEnabled: true,
      metadata: metadata,
      profile: profile,
      activeKeyId: key.keyId,
    );
    return _openEncrypted(paths.databaseFile, profile, key);
  }

  static Future<QueryExecutor> _openExistingEncrypted({
    required DatabasePaths paths,
    required DatabaseMetadataStore metadataStore,
    required DatabaseKeyService keyService,
    required DatabaseMetadata metadata,
  }) async {
    final profile = CipherProfiles.byId(metadata.cipherProfileId);
    if (profile == null) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.unsupportedEncryption,
        'This build does not support cipher profile '
        '"${metadata.cipherProfileId}".',
      );
    }
    await keyService.requireSingleActiveKey();
    final key = await keyService.requireValid(
      keyId: metadata.activeKeyId,
      databaseId: metadata.databaseId,
      generation: metadata.keyGeneration,
      cipherProfileId: metadata.cipherProfileId,
    );

    // Verify the internal identity before Drift runs any migration.
    _verifyIdentityAnchor(paths.databaseFile, profile, key, metadata);
    await backupDatabaseBeforeUpgrade(
      paths.databaseFile,
      profile: profile,
      dek: key.bytes,
    );

    DatabaseRuntimeContext.current = DatabaseRuntimeContext(
      paths: paths,
      encryptionEnabled: true,
      metadata: metadata,
      profile: profile,
      activeKeyId: key.keyId,
    );
    await metadataStore.touch();
    return _openEncrypted(paths.databaseFile, profile, key);
  }

  static Future<QueryExecutor> _migratePlaintext({
    required DatabasePaths paths,
    required DatabaseMetadataStore metadataStore,
    required MigrationJournalStore journalStore,
    required DatabaseKeyService keyService,
    required CipherProfile profile,
  }) async {
    final databaseId = 'db-${const Uuid().v4()}';
    final migrationId = const Uuid().v4();
    final stamp = AppClock.now().microsecondsSinceEpoch;
    final temp = File('${paths.databaseFile.path}.encrypting-$stamp');
    final backupDir = Directory(
      p.join(paths.backupsDirectory.path, 'pre-encryption'),
    );
    final safetyCopy = File(
      p.join(
        backupDir.path,
        '${p.basename(paths.databaseFile.path)}'
        '.pre-encryption-$stamp.plaintext.bak',
      ),
    );
    final quarantine = Directory(
      p.join(paths.quarantineDirectory.path, '$databaseId-$stamp'),
    );

    final sourceSchemaVersion = _readUserVersion(paths.databaseFile);
    var journal = MigrationJournal(
      migrationId: migrationId,
      databaseId: databaseId,
      stage: MigrationStage.planned,
      sourcePath: paths.databaseFile.path,
      sourceSidecars: DatabaseFileInspector.sidecars(
        paths.databaseFile,
      ).where((file) => file.existsSync()).map((file) => file.path).toList(),
      sourceSchemaVersion: sourceSchemaVersion,
      targetSchemaVersion: currentDatabaseSchemaVersion,
      backupPath: safetyCopy.path,
      tempPath: temp.path,
      quarantinePath: quarantine.path,
      newKeyId: DatabaseKeyService.keyIdForGeneration(1),
      newKeyGeneration: 1,
      cipherProfileId: profile.profileId,
      startedAt: AppClock.now().toUtc(),
      updatedAt: AppClock.now().toUtc(),
      pid: pid,
    );

    DatabaseKey? key;
    try {
      await journalStore.write(journal);

      // 1. Checkpoint the source so committed WAL data is part of the snapshot.
      _checkpoint(paths.databaseFile);
      journal = journal.advance(MigrationStage.precheckOk);
      journal = journal.copyWith(
        sourceChecksum: await AtomicFile.checksum(paths.databaseFile),
      );
      await journalStore.write(journal);

      // 2. Create and verify the safety backup before touching the original.
      await backupDir.create(recursive: true);
      await _snapshotPlaintext(paths.databaseFile, safetyCopy);
      journal = journal.advance(MigrationStage.backupCreated);
      await journalStore.write(journal);

      final plaintextSource = SqliteRuntime.open(paths.databaseFile.path);
      final plaintextBackup = SqliteRuntime.open(safetyCopy.path);
      try {
        DatabaseParityVerifier.requireIntegrity(plaintextBackup);
        DatabaseParityVerifier.requireParity(
          source: plaintextSource,
          target: plaintextBackup,
        );
      } finally {
        plaintextSource.dispose();
        plaintextBackup.dispose();
      }
      journal = journal.advance(MigrationStage.backupVerified);
      await journalStore.write(journal);

      // 3. Persist the target key before the destructive steps.
      key = await keyService.createFresh(
        databaseId: databaseId,
        cipherProfileId: profile.profileId,
        createdAt: AppClock.now().toUtc(),
      );
      journal = MigrationJournal(
        migrationId: journal.migrationId,
        databaseId: journal.databaseId,
        stage: MigrationStage.keyCreated,
        sourcePath: journal.sourcePath,
        sourceSidecars: journal.sourceSidecars,
        sourceSchemaVersion: journal.sourceSchemaVersion,
        targetSchemaVersion: journal.targetSchemaVersion,
        backupPath: journal.backupPath,
        tempPath: journal.tempPath,
        quarantinePath: journal.quarantinePath,
        oldKeyId: journal.oldKeyId,
        newKeyId: key.keyId,
        newKeyGeneration: key.generation,
        cipherProfileId: journal.cipherProfileId,
        sourceChecksum: journal.sourceChecksum,
        tempChecksum: journal.tempChecksum,
        startedAt: journal.startedAt,
        updatedAt: AppClock.now().toUtc(),
        pid: journal.pid,
      );
      await journalStore.write(journal);

      // 4. The intended quarantine path is durable before anything moves.
      journal = journal.advance(MigrationStage.quarantinePlanned);
      await journalStore.write(journal);

      await DatabaseFileInspector.quarantine(paths.databaseFile, quarantine);
      final quarantined = File(
        p.join(quarantine.path, p.basename(paths.databaseFile.path)),
      );
      if (!await quarantined.exists()) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.migrationInterrupted,
          'The original database could not be verified in quarantine.',
        );
      }
      journal = journal.advance(MigrationStage.originalQuarantined);
      await journalStore.write(journal);

      // 5. Convert from the verified safety copy into a temporary candidate.
      await _snapshotPlaintext(safetyCopy, temp);
      journal = journal.advance(MigrationStage.conversionStarted);
      await journalStore.write(journal);

      final writer = SqliteRuntime.open(temp.path);
      try {
        if (!SqliteCipherRuntime.isAvailable(writer)) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
            'SQLite3MultipleCiphers is not compiled into this build.',
          );
        }
        SqliteCipherRuntime.applyRekey(writer, profile, key.bytes);
      } finally {
        writer.dispose();
      }
      await _removeSidecars(temp);
      journal = journal.advance(MigrationStage.conversionCompleted);
      await journalStore.write(journal);

      // 6. Verify the encrypted candidate, its identity and full parity.
      _writeIdentityAnchor(temp, profile, key, databaseId);
      _verifyIdentityAnchor(
        temp,
        profile,
        key,
        DatabaseMetadata(
          databaseId: databaseId,
          activeKeyId: key.keyId,
          keyGeneration: key.generation,
          cipherProfileId: profile.profileId,
          encryptionEnabled: true,
          databaseFile: p.basename(temp.path),
          createdAt: AppClock.now().toUtc(),
        ),
      );
      await _verifyParity(
        plaintextPath: quarantined.path,
        encryptedPath: temp.path,
        profile: profile,
        key: key,
      );
      journal = journal.copyWith(tempChecksum: await AtomicFile.checksum(temp));
      journal = journal.advance(MigrationStage.destinationVerified);
      await journalStore.write(journal);

      journal = journal.advance(MigrationStage.replacementStarted);
      await journalStore.write(journal);
      await AtomicFile.replaceAtomically(temp, paths.databaseFile);
      journal = journal.advance(MigrationStage.replacementCompleted);
      await journalStore.write(journal);

      // 7. Commit the external hint only after the verified replacement.
      final metadata = DatabaseMetadata(
        databaseId: databaseId,
        activeKeyId: key.keyId,
        keyGeneration: key.generation,
        cipherProfileId: profile.profileId,
        encryptionEnabled: true,
        databaseFile: p.basename(paths.databaseFile.path),
        createdAt: AppClock.now().toUtc(),
        lastOpenedAt: AppClock.now().toUtc(),
      );
      await metadataStore.write(metadata);
      journal = journal.advance(MigrationStage.metadataCommitted);
      await journalStore.write(journal);

      _verifyIdentityAnchor(paths.databaseFile, profile, key, metadata);
      journal = journal.advance(MigrationStage.identityVerified);
      await journalStore.write(journal);
      journal = journal.advance(MigrationStage.completed);
      await journalStore.write(journal);
      await journalStore.clear();

      DatabaseRuntimeContext.current = DatabaseRuntimeContext(
        paths: paths,
        encryptionEnabled: true,
        metadata: metadata,
        profile: profile,
        activeKeyId: key.keyId,
      );
      return _openEncrypted(paths.databaseFile, profile, key);
    } catch (error) {
      // Preserve the journal, the plaintext original in quarantine and the
      // candidate. The next start decides deterministically whether to resume
      // or roll back.
      try {
        journal = journal.fail(
          error is DatabaseSecurityException
              ? error.codeName
              : 'MIGRATION_CONVERSION_FAILED',
        );
        await journalStore.write(journal);
      } catch (_) {
        // Keep the original exception.
      }
      if (error is DatabaseSecurityException) rethrow;
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The database conversion did not complete; the original is preserved.',
        cause: error,
      );
    }
  }

  static QueryExecutor _openEncrypted(
    File file,
    CipherProfile profile,
    DatabaseKey key,
  ) {
    final statements = profile.keyStatements(key.bytes);
    final verification = profile.verificationQuery;
    return NativeDatabase.createInBackground(
      file,
      // The cipher override is per isolate; install it before Drift opens the
      // connection in its background isolate.
      isolateSetup: Sqlite3mcLoader.ensureConfigured,
      setup: (db) {
        if (!SqliteCipherRuntime.isAvailable(db)) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
            'SQLite3MultipleCiphers is not available in the loaded build.',
          );
        }
        for (final statement in statements) {
          db.execute(statement);
        }
        // A wrong key must fail here, not on the first application query.
        db.select(verification);
      },
    );
  }

  static Future<void> _snapshotPlaintext(File source, File target) async {
    await target.parent.create(recursive: true);
    final db = SqliteRuntime.open(source.path);
    try {
      db.execute('PRAGMA temp_store = MEMORY');
      _checkpointDatabase(db);
      final escaped = target.path.replaceAll("'", "''");
      db.execute("VACUUM INTO '$escaped'");
    } finally {
      db.dispose();
    }
  }

  static Future<void> _removeSidecars(File database) async {
    for (final sidecar in DatabaseFileInspector.sidecars(database)) {
      await AtomicFile.deleteIfExists(sidecar);
    }
  }

  static int _readUserVersion(File file) {
    final db = SqliteRuntime.open(file.path, mode: sqlite3.OpenMode.readOnly);
    try {
      final rows = db.select('PRAGMA user_version');
      return rows.isEmpty ? 0 : rows.first['user_version'] as int;
    } finally {
      db.dispose();
    }
  }

  static void _checkpoint(File file) {
    final db = SqliteRuntime.open(file.path);
    try {
      _checkpointDatabase(db);
    } finally {
      db.dispose();
    }
  }

  static void _checkpointDatabase(sqlite3.Database db) {
    final rows = db.select('PRAGMA wal_checkpoint(TRUNCATE)');
    if (rows.isNotEmpty) {
      final busy = rows.first.values.first;
      if (busy is int && busy != 0) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'The database is still busy; WAL checkpoint could not complete.',
        );
      }
    }
  }

  static void _writeIdentityAnchor(
    File file,
    CipherProfile profile,
    DatabaseKey key,
    String databaseId,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      _applyKey(db, profile, key);
      DatabaseIdentityStore.write(
        db,
        DatabaseIdentity(
          databaseId: databaseId,
          keyId: key.keyId,
          keyGeneration: key.generation,
          cipherProfileId: profile.profileId,
          createdAt: AppClock.now().toUtc(),
        ),
      );
    } finally {
      db.dispose();
    }
  }

  static void _verifyIdentityAnchor(
    File file,
    CipherProfile profile,
    DatabaseKey key,
    DatabaseMetadata metadata,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      _applyKey(db, profile, key);
      DatabaseParityVerifier.requireIntegrity(db);
      final derived = DatabaseIdentityStore.read(db);
      if (derived == null) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The encrypted database has no security identity anchor.',
        );
      }
      derived.requireMatches(metadata);
    } finally {
      db.dispose();
    }
  }

  static void _applyKey(
    sqlite3.Database db,
    CipherProfile profile,
    DatabaseKey key,
  ) {
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
    } on DatabaseSecurityException {
      rethrow;
    } on StateError catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'SQLite3MultipleCiphers is not available in the loaded build.',
        cause: error,
      );
    } catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.wrongKey,
        'The database key or cipher profile was rejected.',
        cause: error,
      );
    }
  }

  static Future<void> _verifyParity({
    required String plaintextPath,
    required String encryptedPath,
    required CipherProfile profile,
    required DatabaseKey key,
  }) async {
    final plaintext = SqliteRuntime.open(plaintextPath);
    final encrypted = SqliteRuntime.open(encryptedPath);
    try {
      _applyKey(encrypted, profile, key);
      DatabaseParityVerifier.requireParity(
        source: plaintext,
        target: encrypted,
      );
    } finally {
      plaintext.dispose();
      encrypted.dispose();
    }
  }

  static Future<void> _recoverInterruptedMigration({
    required DatabasePaths paths,
    required MigrationJournalStore journalStore,
    required DatabaseMetadataStore metadataStore,
    required DatabaseKeyService? keyService,
  }) async {
    final journal = await journalStore.read();
    if (journal == null) return;
    if (journal.isComplete || journal.stage == MigrationStage.rolledBack) {
      await journalStore.clear();
      return;
    }

    final kind = await DatabaseFileInspector.classify(paths.databaseFile);
    final profile = CipherProfiles.byId(journal.cipherProfileId);
    final databaseId = journal.databaseId;

    // The replacement may already have produced a valid database. Its internal
    // identity is the only signal considered trustworthy. Probing is limited to
    // an existing non-plaintext file so recovery can never create an empty
    // database by opening a path that does not exist.
    if (keyService != null &&
        profile != null &&
        kind == DatabaseFileKind.encryptedOrUnknown) {
      final key = await keyService.load(journal.newKeyId);
      if (key != null) {
        final identity = _readIdentity(paths.databaseFile.path, profile, key);
        if (identity != null && identity.databaseId == databaseId) {
          await metadataStore.write(
            DatabaseMetadata(
              databaseId: identity.databaseId,
              activeKeyId: identity.keyId,
              keyGeneration: identity.keyGeneration,
              cipherProfileId: identity.cipherProfileId,
              encryptionEnabled: true,
              databaseFile: p.basename(paths.databaseFile.path),
              createdAt: identity.createdAt,
              lastOpenedAt: AppClock.now().toUtc(),
            ),
          );
          await journalStore.write(journal.advance(MigrationStage.completed));
          await journalStore.clear();
          return;
        }
      }
    }

    // Nothing replaced the original yet, or the replacement failed before it
    // was durable. Restore the quarantined original when it exists.
    if (journal.quarantinePath != null) {
      final quarantine = Directory(journal.quarantinePath!);
      final original = File(
        p.join(quarantine.path, p.basename(journal.sourcePath)),
      );
      if (await original.exists()) {
        for (final file in paths.databaseAndSidecars) {
          if (await file.exists()) await AtomicFile.deleteIfExists(file);
        }
        // The quarantined original was checkpointed before it moved, so the
        // main file is the complete rollback point. Sidecars are deliberately
        // not reused: a stale WAL must never attach to a restored database.
        await AtomicFile.copyAndVerify(original, paths.databaseFile);
        await _removeSidecars(paths.databaseFile);
        await AtomicFile.deleteIfExists(paths.metadataFile);
        if (journal.tempPath != null) {
          await AtomicFile.deleteIfExists(File(journal.tempPath!));
        }
        await journalStore.write(journal.advance(MigrationStage.rolledBack));
        await journalStore.clear();
        return;
      }
    }

    if (kind == DatabaseFileKind.plaintext ||
        kind == DatabaseFileKind.missing) {
      // The original is still in place (the quarantine move never happened, or
      // it moved and has already been restored).
      if (journal.tempPath != null) {
        await AtomicFile.deleteIfExists(File(journal.tempPath!));
      }
      await journalStore.clear();
      return;
    }

    throw const DatabaseSecurityException(
      DatabaseSecurityErrorCode.migrationInterrupted,
      'A database conversion was interrupted and cannot be resolved '
      'automatically. The original files have been preserved.',
    );
  }

  static Future<void> _recoverInterruptedRotation({
    required DatabasePaths paths,
    required RotationJournalStore rotationStore,
    required DatabaseMetadataStore metadataStore,
    required DatabaseKeyService? keyService,
  }) async {
    final journal = await rotationStore.read();
    if (journal == null) return;
    if (journal.isComplete || journal.stage == RotationStage.rolledBack) {
      await rotationStore.clear();
      return;
    }

    final profile = CipherProfiles.byId(journal.cipherProfileId);
    if (profile == null || keyService == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'An interrupted key rotation cannot be resolved by this build.',
      );
    }
    final newKey = await keyService.load(journal.newKeyId);
    final oldKey = await keyService.load(journal.oldKeyId);

    // The replacement may already be live. Its internal identity is the only
    // trustworthy statement of which key it uses.
    if (newKey != null) {
      final identity = _readIdentity(paths.databaseFile.path, profile, newKey);
      if (identity != null &&
          identity.databaseId == journal.databaseId &&
          identity.keyId == journal.newKeyId &&
          identity.keyGeneration == journal.newGeneration) {
        await metadataStore.write(
          DatabaseMetadata(
            databaseId: identity.databaseId,
            activeKeyId: identity.keyId,
            keyGeneration: identity.keyGeneration,
            cipherProfileId: identity.cipherProfileId,
            encryptionEnabled: true,
            databaseFile: p.basename(paths.databaseFile.path),
            createdAt: identity.createdAt,
            lastOpenedAt: AppClock.now().toUtc(),
          ),
        );
        await keyService.activate(newKey.keyId);
        await rotationStore.write(journal.advance(RotationStage.completed));
        await rotationStore.clear();
        return;
      }
    }

    if (oldKey != null) {
      // The live database still belongs to the old key: abandon the candidate.
      final identity = _readIdentity(paths.databaseFile.path, profile, oldKey);
      if (identity != null &&
          identity.databaseId == journal.databaseId &&
          identity.keyId == journal.oldKeyId) {
        await _deleteRotationCandidate(journal);
        await keyService.activate(oldKey.keyId);
        await rotationStore.write(journal.advance(RotationStage.rolledBack));
        await rotationStore.clear();
        return;
      }

      // The live file is missing or damaged after a partial replacement.
      // Restore the verified pre-rotation copy rather than guessing.
      if (journal.backupPath != null) {
        final backup = File(journal.backupPath!);
        if (await backup.exists()) {
          final backupIdentity = _readIdentity(backup.path, profile, oldKey);
          if (backupIdentity != null &&
              backupIdentity.databaseId == journal.databaseId) {
            final temp = File(
              '${paths.databaseFile.path}.rotation-restore-'
              '${AppClock.now().microsecondsSinceEpoch}',
            );
            try {
              await AtomicFile.copyAndVerify(backup, temp);
              await AtomicFile.replaceAtomically(temp, paths.databaseFile);
            } finally {
              await AtomicFile.deleteIfExists(temp);
            }
            await _removeSidecars(paths.databaseFile);
            await metadataStore.write(
              DatabaseMetadata(
                databaseId: backupIdentity.databaseId,
                activeKeyId: journal.oldKeyId,
                keyGeneration: journal.oldGeneration,
                cipherProfileId: journal.cipherProfileId,
                encryptionEnabled: true,
                databaseFile: p.basename(paths.databaseFile.path),
                createdAt: backupIdentity.createdAt,
                lastOpenedAt: AppClock.now().toUtc(),
              ),
            );
            await _deleteRotationCandidate(journal);
            await keyService.activate(oldKey.keyId);
            await rotationStore.write(
              journal.advance(RotationStage.rolledBack),
            );
            await rotationStore.clear();
            return;
          }
        }
      }
    }

    throw const DatabaseSecurityException(
      DatabaseSecurityErrorCode.migrationInterrupted,
      'An interrupted key rotation cannot be resolved automatically. The '
      'pre-rotation database and old key have been preserved.',
    );
  }

  static Future<void> _deleteRotationCandidate(RotationJournal journal) async {
    final candidatePath = journal.candidatePath;
    if (candidatePath == null) return;
    await AtomicFile.deleteIfExists(File(candidatePath));
  }

  static DatabaseIdentity? _readIdentity(
    String path,
    CipherProfile profile,
    DatabaseKey key,
  ) {
    final db = SqliteRuntime.open(path, mode: sqlite3.OpenMode.readOnly);
    try {
      _applyKey(db, profile, key);
      return DatabaseIdentityStore.read(db);
    } on Object {
      return null;
    } finally {
      db.dispose();
    }
  }
}

/// Small helper used by tests and diagnostics.
Uint8List hexToBytes(String hex) {
  if (hex.length.isOdd) throw const FormatException('Odd-length hex string.');
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}
