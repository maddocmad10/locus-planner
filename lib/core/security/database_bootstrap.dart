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
import 'database_file_inspector.dart';
import 'database_identity.dart';
import 'database_key_service.dart';
import 'database_metadata.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'database_security_options.dart';
import 'migration_journal.dart';

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
/// The startup decision model is implemented here, before Drift is allowed to
/// touch the file:
///
/// * missing file + no metadata  -> create a new identity
/// * plaintext file + no metadata -> controlled conversion
/// * encrypted file + metadata + key -> open with the recorded profile
/// * anything inconsistent -> fail closed with a recovery error
abstract final class DatabaseBootstrap {
  static Future<QueryExecutor> open() async {
    final options = DatabaseSecurity.current;
    final paths = await DatabasePathsResolver.resolve(options: options);
    final metadataStore = DatabaseMetadataStore(paths.metadataFile);
    final journalStore = MigrationJournalStore(paths.migrationJournalFile);

    final pending = await journalStore.read();
    if (pending != null && !pending.isComplete) {
      await _recoverInterruptedMigration(
        paths: paths,
        journalStore: journalStore,
        metadataStore: metadataStore,
      );
      return open();
    }
    if (pending != null) await journalStore.clear();

    final kind = await DatabaseFileInspector.classify(paths.databaseFile);
    final metadata = await metadataStore.read();

    if (!options.encryptLiveDatabase) {
      return _openPlaintext(paths, metadata, kind);
    }

    final keyStore = options.keyStore;
    if (keyStore == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'Live encryption is enabled without a key store.',
      );
    }
    final keyService = DatabaseKeyService(keyStore);

    if (metadata == null) {
      switch (kind) {
        case DatabaseFileKind.missing:
        case DatabaseFileKind.empty:
          return _createEncrypted(
            paths: paths,
            metadataStore: metadataStore,
            keyService: keyService,
            profile: options.profile,
          );
        case DatabaseFileKind.plaintext:
          return _migratePlaintext(
            paths: paths,
            metadataStore: metadataStore,
            journalStore: journalStore,
            keyService: keyService,
            profile: options.profile,
          );
        case DatabaseFileKind.encryptedOrUnknown:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            'The database is encrypted but its metadata is missing.',
          );
        case DatabaseFileKind.corrupt:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.databaseDamaged,
            'The database file is too short to be valid.',
          );
      }
    }

    if (!metadata.encryptionEnabled) {
      if (kind == DatabaseFileKind.plaintext) {
        return _openPlaintext(paths, metadata, kind);
      }
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'Metadata describes a plaintext database but the file is not plaintext.',
      );
    }

    final recordedProfile = CipherProfiles.byId(metadata.cipherProfileId);
    if (recordedProfile == null) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.unsupportedEncryption,
        'This build does not support cipher profile '
        '"${metadata.cipherProfileId}".',
      );
    }

    switch (kind) {
      case DatabaseFileKind.missing:
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.databaseMissing,
          'The database file is missing. It was not recreated automatically.',
        );
      case DatabaseFileKind.empty:
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.zeroLengthDatabase,
          'The database file is empty; creation may have been interrupted.',
        );
      case DatabaseFileKind.plaintext:
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
          'A plaintext database was found where an encrypted one is expected.',
        );
      case DatabaseFileKind.corrupt:
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.databaseDamaged,
          'The database file is damaged.',
        );
      case DatabaseFileKind.encryptedOrUnknown:
        final key = await keyService.load(metadata.activeKeyId);
        if (key == null) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.keyMissing,
            'The database key is unavailable. Restore it from a recovery bundle.',
          );
        }
        await backupDatabaseBeforeUpgrade(
          paths.databaseFile,
          profile: recordedProfile,
          dek: key.bytes,
        );
        DatabaseRuntimeContext.current = DatabaseRuntimeContext(
          paths: paths,
          encryptionEnabled: true,
          metadata: metadata,
          profile: recordedProfile,
          activeKeyId: key.keyId,
        );
        await metadataStore.touch();
        return _openEncrypted(paths.databaseFile, recordedProfile, key);
    }
  }

  static Future<QueryExecutor> _openPlaintext(
    DatabasePaths paths,
    DatabaseMetadata? metadata,
    DatabaseFileKind kind,
  ) async {
    // Metadata is an untrusted hint, but a hint that says "encrypted" must
    // never be ignored just because this process was started without the E0
    // flag. Otherwise a deleted/renamed file could be replaced by an empty
    // plaintext database under an encrypted identity.
    if (metadata?.encryptionEnabled == true) {
      switch (kind) {
        case DatabaseFileKind.missing:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.databaseMissing,
            'The encrypted database file is missing. It was not recreated.',
          );
        case DatabaseFileKind.empty:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.zeroLengthDatabase,
            'The encrypted database file is empty.',
          );
        case DatabaseFileKind.plaintext:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
            'A plaintext database was found where an encrypted one is expected.',
          );
        case DatabaseFileKind.corrupt:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.databaseDamaged,
            'The database file is damaged.',
          );
        case DatabaseFileKind.encryptedOrUnknown:
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.unsupportedEncryption,
            'This build was not started with database encryption enabled.',
          );
      }
    }
    if (kind == DatabaseFileKind.encryptedOrUnknown) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unsupportedEncryption,
        'This build was not started with database encryption enabled.',
      );
    }
    if (kind == DatabaseFileKind.corrupt) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.databaseDamaged,
        'The database file is damaged.',
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
    await metadataStore.write(metadata);
    DatabaseRuntimeContext.current = DatabaseRuntimeContext(
      paths: paths,
      encryptionEnabled: true,
      metadata: metadata,
      profile: profile,
      activeKeyId: key.keyId,
    );
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

    final travel = DatabaseFileInspector.sidecars(
      paths.databaseFile,
    ).where((file) => file.existsSync()).map((file) => file.path).toList();
    var journal = MigrationJournal(
      databaseId: databaseId,
      stage: MigrationStage.notStarted,
      sourcePath: paths.databaseFile.path,
      sourceSidecars: travel,
      newKeyId: DatabaseKeyService.keyIdForGeneration(1),
      newKeyGeneration: 1,
      cipherProfileId: profile.profileId,
      startedAt: AppClock.now().toUtc(),
      updatedAt: AppClock.now().toUtc(),
      pid: pid,
    );
    await journalStore.write(journal);

    journal = journal.advance(MigrationStage.precheckOk);
    await journalStore.write(journal);

    // A labelled plaintext safety copy is a necessary evil for the very first
    // migration. It is recorded in the journal and never treated as the only
    // recovery path.
    await backupDir.create(recursive: true);
    await _snapshotPlaintext(paths.databaseFile, safetyCopy);
    journal = journal.copyWith(backupPath: safetyCopy.path);
    journal = journal.advance(MigrationStage.snapshotCreated);
    await journalStore.write(journal);

    final key = await keyService.createFresh(
      databaseId: databaseId,
      cipherProfileId: profile.profileId,
      createdAt: AppClock.now().toUtc(),
    );
    journal = MigrationJournal(
      databaseId: journal.databaseId,
      stage: MigrationStage.keyCreated,
      sourcePath: journal.sourcePath,
      sourceSidecars: journal.sourceSidecars,
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

    try {
      await _snapshotPlaintext(safetyCopy, temp);
      journal = journal.copyWith(tempPath: temp.path);
      journal = journal.advance(MigrationStage.tempCreated);
      await journalStore.write(journal);

      final writer = sqlite3.sqlite3.open(temp.path);
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
      journal = journal.advance(MigrationStage.encryptionApplied);
      await journalStore.write(journal);

      await _verifyEncrypted(temp.path, profile, key, databaseId);
      journal = journal.advance(MigrationStage.encryptedDatabaseVerified);
      await journalStore.write(journal);

      // Quarantine the original and its sidecars, then replace atomically.
      await DatabaseFileInspector.quarantine(paths.databaseFile, quarantine);
      journal = journal.copyWith(quarantinePath: quarantine.path);
      await AtomicFile.replace(temp, paths.databaseFile);
      journal = journal.advance(MigrationStage.databaseReplaced);
      await journalStore.write(journal);
    } catch (error) {
      // The original is still in quarantine or in place; never delete it.
      if (error is DatabaseSecurityException) rethrow;
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The database conversion did not complete; the original is preserved.',
        cause: error,
      );
    }

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
    journal = journal.advance(MigrationStage.migrationComplete);
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
    final db = sqlite3.sqlite3.open(source.path);
    try {
      db.execute('PRAGMA temp_store = MEMORY');
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

  static Future<void> _verifyEncrypted(
    String path,
    CipherProfile profile,
    DatabaseKey key,
    String databaseId,
  ) async {
    final db = sqlite3.sqlite3.open(path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      final integrity = db.select('PRAGMA integrity_check');
      if (integrity.length != 1 || integrity.first.values.first != 'ok') {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.databaseDamaged,
          'The encrypted replacement failed integrity_check.',
        );
      }
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

  static Future<void> _recoverInterruptedMigration({
    required DatabasePaths paths,
    required MigrationJournalStore journalStore,
    required DatabaseMetadataStore metadataStore,
  }) async {
    final journal = await journalStore.read();
    if (journal == null) return;
    if (journal.isComplete) {
      await journalStore.clear();
      return;
    }

    final kind = await DatabaseFileInspector.classify(paths.databaseFile);
    final profile = CipherProfiles.byId(journal.cipherProfileId);
    final databaseId = journal.databaseId;

    if (profile != null && kind == DatabaseFileKind.encryptedOrUnknown) {
      final keyStore = DatabaseSecurity.keyStore;
      if (keyStore == null) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'Encryption is enabled without a key store.',
        );
      }
      final keyService = DatabaseKeyService(keyStore);
      final key = await keyService.load(journal.newKeyId);
      if (key != null) {
        final identity = await _readIdentity(
          paths.databaseFile.path,
          profile,
          key,
        );
        if (identity != null && identity.databaseId == databaseId) {
          await metadataStore.write(
            DatabaseMetadata(
              databaseId: databaseId,
              activeKeyId: key.keyId,
              keyGeneration: key.generation,
              cipherProfileId: profile.profileId,
              encryptionEnabled: true,
              databaseFile: p.basename(paths.databaseFile.path),
              createdAt: identity.createdAt,
              lastOpenedAt: AppClock.now().toUtc(),
            ),
          );
          await journalStore.write(
            journal.advance(MigrationStage.migrationComplete),
          );
          await journalStore.clear();
          return;
        }
      }
    }

    if (journal.quarantinePath != null) {
      final quarantine = Directory(journal.quarantinePath!);
      final original = File(
        p.join(quarantine.path, p.basename(journal.sourcePath)),
      );
      if (await original.exists()) {
        for (final file in paths.databaseAndSidecars) {
          await AtomicFile.deleteIfExists(file);
        }
        await DatabaseFileInspector.copyWithSidecars(
          original,
          paths.databaseFile,
        );
        await AtomicFile.deleteIfExists(paths.metadataFile);
        await journalStore.clear();
        return;
      }
    }

    if (kind == DatabaseFileKind.plaintext) {
      // Nothing replaced the original.
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

  static Future<DatabaseIdentity?> _readIdentity(
    String path,
    CipherProfile profile,
    DatabaseKey key,
  ) async {
    final db = sqlite3.sqlite3.open(path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
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
