import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'cipher_profile.dart';
import 'database_identity.dart';
import 'database_key_service.dart';
import 'database_metadata.dart';
import 'database_parity_verifier.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'rotation_journal.dart';
import 'sqlite3mc.dart';

/// Creates a verified replacement database encrypted with a new DEK.
///
/// The caller must hold the exclusive lifecycle lock and must not have any open
/// handle on the live database. The old encrypted database and the old key
/// record are retained until the replacement has been verified and the new
/// metadata is committed.
abstract final class DatabaseRotationService {
  static Future<DatabaseMetadata> rotate({
    required DatabasePaths paths,
    required DatabaseMetadata metadata,
    required DatabaseKey oldKey,
    required DatabaseKeyService keyService,
    required DatabaseMetadataStore metadataStore,
    required RotationJournalStore journalStore,
    required CipherProfile profile,
  }) async {
    final stamp = AppClock.now().microsecondsSinceEpoch;
    final candidate = File('${paths.databaseFile.path}.rotating-$stamp');
    final backupDirectory = Directory(
      p.join(paths.backupsDirectory.path, 'rotation'),
    );
    final backup = File(
      p.join(
        backupDirectory.path,
        '${p.basename(paths.databaseFile.path)}'
        '.pre-rotation-$stamp.encrypted.bak',
      ),
    );

    // A rotation is meaningless if the live database cannot be opened with the
    // key that is about to be rotated away.
    _checkpoint(paths.databaseFile, profile, oldKey);
    final sourceChecksum = await AtomicFile.checksum(paths.databaseFile);
    final oldIdentity = _readIdentity(paths.databaseFile, profile, oldKey);
    if (oldIdentity == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The live database has no readable identity anchor.',
      );
    }
    oldIdentity.requireMatches(metadata);

    final newKey = await keyService.createFresh(
      databaseId: metadata.databaseId,
      cipherProfileId: profile.profileId,
      createdAt: AppClock.now().toUtc(),
      activate: false,
    );

    final newMetadata = DatabaseMetadata(
      databaseId: metadata.databaseId,
      activeKeyId: newKey.keyId,
      keyGeneration: newKey.generation,
      cipherProfileId: profile.profileId,
      encryptionEnabled: true,
      databaseFile: p.basename(paths.databaseFile.path),
      createdAt: metadata.createdAt,
      lastOpenedAt: AppClock.now().toUtc(),
    );

    var journal = RotationJournal(
      rotationId: const Uuid().v4(),
      databaseId: metadata.databaseId,
      stage: RotationStage.planned,
      sourcePath: paths.databaseFile.path,
      backupPath: backup.path,
      candidatePath: candidate.path,
      oldKeyId: oldKey.keyId,
      oldGeneration: oldKey.generation,
      newKeyId: newKey.keyId,
      newGeneration: newKey.generation,
      cipherProfileId: profile.profileId,
      sourceChecksum: sourceChecksum,
      startedAt: AppClock.now().toUtc(),
      updatedAt: AppClock.now().toUtc(),
      pid: pid,
    );

    try {
      await journalStore.write(journal);

      // 1. Preserve the pre-rotation encrypted database before touching it.
      await backupDirectory.create(recursive: true);
      await AtomicFile.copyAndVerify(paths.databaseFile, backup);
      journal = journal.advance(RotationStage.backupCreated);
      await journalStore.write(journal);

      _verifyReadable(backup, profile, oldKey, metadata);
      _verifyParity(
        source: paths.databaseFile,
        sourceProfile: profile,
        sourceKey: oldKey,
        target: backup,
        targetProfile: profile,
        targetKey: oldKey,
      );
      journal = journal.advance(RotationStage.backupVerified);
      await journalStore.write(journal);
      journal = journal.advance(RotationStage.keyCreated);
      await journalStore.write(journal);

      // 2. Build the rekeyed candidate from the verified copy.
      await AtomicFile.copyAndVerify(paths.databaseFile, candidate);
      journal = journal.advance(RotationStage.candidateCreated);
      await journalStore.write(journal);

      _rekeyCandidate(candidate, profile, oldKey, newKey, oldIdentity);
      await AtomicFile.flushFile(candidate);

      // 3. Verify the candidate with the new key before any replacement.
      _verifyReadable(candidate, profile, newKey, newMetadata);
      _verifyParity(
        source: paths.databaseFile,
        sourceProfile: profile,
        sourceKey: oldKey,
        target: candidate,
        targetProfile: profile,
        targetKey: newKey,
      );
      if (_canOpen(candidate, profile, oldKey)) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The rekeyed candidate still opens with the old database key.',
        );
      }
      journal = journal.copyWith(
        candidateChecksum: await AtomicFile.checksum(candidate),
      );
      journal = journal.advance(RotationStage.candidateVerified);
      await journalStore.write(journal);

      // 4. Replace, then commit metadata before activating the key.
      journal = journal.advance(RotationStage.replacementStarted);
      await journalStore.write(journal);
      await AtomicFile.replaceAtomically(candidate, paths.databaseFile);
      journal = journal.advance(RotationStage.replacementCompleted);
      await journalStore.write(journal);

      await metadataStore.write(newMetadata);
      journal = journal.advance(RotationStage.metadataCommitted);
      await journalStore.write(journal);

      _verifyReadable(paths.databaseFile, profile, newKey, newMetadata);
      await keyService.activate(newKey.keyId);
      journal = journal.advance(RotationStage.completed);
      await journalStore.write(journal);
      await journalStore.clear();

      return newMetadata;
    } catch (error) {
      try {
        await journalStore.write(
          journal.fail(
            error is DatabaseSecurityException
                ? error.codeName
                : 'ROTATION_FAILED',
          ),
        );
      } catch (_) {
        // Keep the original error.
      }
      if (error is DatabaseSecurityException) rethrow;
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The database key rotation did not complete; the old database and key '
        'are preserved.',
        cause: error,
      );
    }
  }

  static void _rekeyCandidate(
    File candidate,
    CipherProfile profile,
    DatabaseKey oldKey,
    DatabaseKey newKey,
    DatabaseIdentity current,
  ) {
    final db = SqliteRuntime.open(candidate.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, oldKey.bytes);
      SqliteCipherRuntime.applyRekeyOnly(db, profile, newKey.bytes);
      DatabaseIdentityStore.write(
        db,
        DatabaseIdentity(
          databaseId: current.databaseId,
          keyId: newKey.keyId,
          keyGeneration: newKey.generation,
          cipherProfileId: profile.profileId,
          createdAt: current.createdAt,
          updatedAt: AppClock.now().toUtc(),
        ),
      );
      DatabaseParityVerifier.requireIntegrity(db);
    } finally {
      db.dispose();
    }
  }

  static void _checkpoint(File file, CipherProfile profile, DatabaseKey key) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      final rows = db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      if (rows.isNotEmpty) {
        final busy = rows.first.values.first;
        if (busy is int && busy != 0) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            'The database is still busy; rotation cannot checkpoint the WAL.',
          );
        }
      }
      DatabaseParityVerifier.requireIntegrity(db);
    } finally {
      db.dispose();
    }
  }

  static DatabaseIdentity? _readIdentity(
    File file,
    CipherProfile profile,
    DatabaseKey key,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      return DatabaseIdentityStore.read(db);
    } finally {
      db.dispose();
    }
  }

  static void _verifyReadable(
    File file,
    CipherProfile profile,
    DatabaseKey key,
    DatabaseMetadata metadata,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      DatabaseParityVerifier.requireIntegrity(db);
      final identity = DatabaseIdentityStore.read(db);
      if (identity == null) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The rotated database has no identity anchor.',
        );
      }
      identity.requireMatches(metadata);
    } finally {
      db.dispose();
    }
  }

  static void _verifyParity({
    required File source,
    required CipherProfile sourceProfile,
    required DatabaseKey sourceKey,
    required File target,
    required CipherProfile targetProfile,
    required DatabaseKey targetKey,
  }) {
    final left = SqliteRuntime.open(source.path);
    final right = SqliteRuntime.open(target.path);
    try {
      SqliteCipherRuntime.applyKey(left, sourceProfile, sourceKey.bytes);
      SqliteCipherRuntime.applyKey(right, targetProfile, targetKey.bytes);
      DatabaseParityVerifier.requireParity(source: left, target: right);
    } finally {
      left.dispose();
      right.dispose();
    }
  }

  static bool _canOpen(File file, CipherProfile profile, DatabaseKey key) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      return true;
    } catch (_) {
      return false;
    } finally {
      db.dispose();
    }
  }
}
