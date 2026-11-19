import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../services/attachments/attachment_key_store.dart';
import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'cipher_profile.dart';
import 'database_file_inspector.dart';
import 'database_identity.dart';
import 'database_key_store.dart';
import 'database_lifecycle_lock.dart';
import 'database_metadata.dart';
import 'database_parity_verifier.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'recovery_envelope.dart';
import 'recovery_package_manifest.dart';
import 'recovery_package_service.dart';
import 'restore_journal.dart';
import 'sqlite3mc.dart';

/// Stages and applies raw `.locusrecovery` packages.
///
/// Staging never touches the live database. The recovered DEK and attachment
/// key wait in OS-protected staged slots until [applyStagedLocked] runs under
/// the exclusive lifecycle lock at the next startup.
class RecoveryRestoreService {
  const RecoveryRestoreService();

  static const _stagedRollbackPrefix = 'rollback-';

  Future<RestoreJournal> stage({
    required DatabasePaths paths,
    required File package,
    required String passphrase,
    required DatabaseKeyStore keyStore,
    required AttachmentKeyStore attachmentKeyStore,
  }) async {
    final lock = DatabaseLifecycleLock(paths.lifecycleLockFile);
    return lock.withLock(DatabaseLockMode.exclusive, () async {
      final journalStore = RestoreJournalStore(paths.restoreJournalFile);
      if (await journalStore.exists) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'A database restore is already staged. Restart Locus to finish it, '
          'or remove the staged restore before starting another.',
        );
      }
      final stamp = AppClock.now().microsecondsSinceEpoch;
      final staging = Directory(
        p.join(paths.dataDirectory.path, 'recovery', 'staged-$stamp'),
      );
      await staging.create(recursive: true);
      final service = const RecoveryPackageService();
      RecoveryPackageManifest? manifest;
      OpenedRecoveryBundle? opened;
      try {
        manifest = await service.extractAndVerify(
          archive: package,
          passphrase: passphrase,
          destination: staging,
        );
        final storedEnvelope = File(p.join(staging.path, 'recovery.json'));
        final bundle = RecoveryBundle.decode(
          await storedEnvelope.readAsString(),
        );
        opened = await RecoveryEnvelopeService.open(bundle, passphrase);
        _requireIdentity(manifest, opened);

        if (manifest.attachmentsIncluded && opened.attachmentKey == null) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            'The recovery package contains attachments but no attachment key.',
          );
        }

        final previous = await DatabaseMetadataStore(paths.metadataFile).read();
        final now = AppClock.now().toUtc();
        final stagedKey = DatabaseKeyRecord(
          keyId: manifest.keyId,
          generation: manifest.keyGeneration,
          databaseId: manifest.databaseId,
          cipherProfileId: manifest.cipherProfileId,
          bytes: opened.dek,
          createdAt: now,
          active: false,
        );
        await keyStore.writeStaged(stagedKey);
        if (opened.attachmentKey != null) {
          await attachmentKeyStore.writeStaged(opened.attachmentKey!);
        } else {
          await attachmentKeyStore.clearStaged();
        }

        final journal = RestoreJournal(
          packageSha256: await AtomicFile.checksum(package),
          stagedDirectory: staging.path,
          quarantineDirectory: p.join(
            paths.quarantineDirectory.path,
            'raw-restore-$stamp',
          ),
          databaseId: manifest.databaseId,
          keyId: manifest.keyId,
          keyGeneration: manifest.keyGeneration,
          cipherProfileId: manifest.cipherProfileId,
          databaseSha256: manifest.databaseSha256,
          databaseBytes: manifest.databaseBytes,
          schemaVersion: manifest.schemaVersion,
          attachmentsIncluded: manifest.attachmentsIncluded,
          attachmentCount: manifest.attachmentFileCount,
          replaceAttachmentStore: manifest.attachmentsIncluded,
          previousDatabaseId: previous?.databaseId ?? '',
          previousKeyId: previous?.activeKeyId ?? '',
          previousKeyGeneration: previous?.keyGeneration ?? 0,
          previousCipherProfileId: previous?.cipherProfileId ?? '',
          previousDatabaseFile:
              previous?.databaseFile ?? p.basename(paths.databaseFile.path),
          startedAt: now,
          updatedAt: now,
        );
        await journalStore.write(journal);
        return journal;
      } catch (error) {
        await keyStore.deleteStaged(manifest?.keyId ?? '');
        await attachmentKeyStore.clearStaged();
        await _deleteDirectory(staging);
        if (error is DatabaseSecurityException) rethrow;
        if (error is RecoveryPackageException) {
          throw DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            error.message,
            cause: error,
          );
        }
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'The recovery package could not be staged.',
          cause: error,
        );
      }
    });
  }

  /// Applies a staged restore. The caller must already hold the exclusive
  /// lifecycle lock (DatabaseBootstrap calls this before classification).
  ///
  /// Returns true when a staged restore was present and applied.
  Future<bool> applyStagedLocked({
    required DatabasePaths paths,
    required DatabaseKeyStore keyStore,
    required AttachmentKeyStore attachmentKeyStore,
  }) async {
    final journalStore = RestoreJournalStore(paths.restoreJournalFile);
    final journal = await journalStore.read();
    if (journal == null) return false;
    if (journal.isComplete) {
      await _deleteDirectory(Directory(journal.stagedDirectory));
      await journalStore.clear();
      return false;
    }

    Sqlite3mcLoader.ensureConfigured();
    final staging = Directory(journal.stagedDirectory);
    final stagedDatabase = File(p.join(staging.path, 'locus_planner.db'));
    final stagedKey = await keyStore.readStaged(journal.keyId);
    if (stagedKey == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'The staged recovery key is missing. Stage the package again.',
      );
    }
    if (!await stagedDatabase.exists()) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'The staged recovery database is missing. Stage the package again.',
      );
    }
    if (await stagedDatabase.length() != journal.databaseBytes ||
        await AtomicFile.checksum(stagedDatabase) != journal.databaseSha256) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'The staged recovery database failed its checksum.',
      );
    }

    final profile = CipherProfiles.byId(journal.cipherProfileId);
    if (profile == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unsupportedEncryption,
        'This build does not support the package cipher profile.',
      );
    }
    final identity = _readVerifiedIdentity(
      stagedDatabase,
      profile,
      stagedKey.bytes,
      journal,
    );

    final quarantine = Directory(journal.quarantineDirectory);
    await quarantine.create(recursive: true);
    final previousDatabase = File(
      p.join(quarantine.path, p.basename(paths.databaseFile.path)),
    );
    final previousMetadata = File(
      p.join(quarantine.path, p.basename(paths.metadataFile.path)),
    );
    Uint8List? previousAttachmentKey;
    var attachmentKeyCaptured = false;

    try {
      final alreadyInstalled = _liveDatabaseMatches(
        paths,
        profile,
        stagedKey.bytes,
        journal,
      );
      if (!alreadyInstalled) {
        // Keep the previous database, sidecars and identity hint together.
        if (await paths.databaseFile.exists()) {
          for (final file in paths.databaseAndSidecars) {
            if (!await file.exists()) continue;
            final target = File(p.join(quarantine.path, p.basename(file.path)));
            if (await target.exists()) await AtomicFile.deleteIfExists(target);
            await file.rename(target.path);
          }
        }
        if (await paths.metadataFile.exists() &&
            !await previousMetadata.exists()) {
          await paths.metadataFile.rename(previousMetadata.path);
        }
        for (final journalFile in <File>[
          paths.migrationJournalFile,
          paths.rotationJournalFile,
        ]) {
          if (!await journalFile.exists()) continue;
          final target = File(
            p.join(quarantine.path, p.basename(journalFile.path)),
          );
          if (await target.exists()) await AtomicFile.deleteIfExists(target);
          await journalFile.rename(target.path);
        }

        final temp = File(
          '${paths.databaseFile.path}.restore-'
          '${AppClock.now().microsecondsSinceEpoch}',
        );
        try {
          await AtomicFile.copyAndVerify(stagedDatabase, temp);
          await AtomicFile.replaceAtomically(temp, paths.databaseFile);
        } finally {
          await AtomicFile.deleteIfExists(temp);
        }
        for (final sidecar in DatabaseFileInspector.sidecars(
          paths.databaseFile,
        )) {
          await AtomicFile.deleteIfExists(sidecar);
        }
      }

      // Preserve a colliding key slot before the recovered identity takes it.
      final existingKey = await keyStore.read(journal.keyId);
      if (existingKey != null && existingKey.databaseId != journal.databaseId) {
        await keyStore.writeStaged(
          DatabaseKeyRecord(
            keyId: '$_stagedRollbackPrefix${journal.previousKeyId}',
            generation: existingKey.generation,
            databaseId: existingKey.databaseId,
            cipherProfileId: existingKey.cipherProfileId,
            bytes: existingKey.bytes,
            createdAt: existingKey.createdAt,
            active: false,
          ),
        );
      }

      await keyStore.write(stagedKey.copyWith(active: true));
      await keyStore.markActive(journal.keyId);
      await keyStore.deleteStaged(journal.keyId);

      final attachments = Directory(
        p.join(paths.dataDirectory.path, 'attachments'),
      );
      final quarantinedAttachments = Directory(
        p.join(quarantine.path, 'attachments'),
      );
      if (journal.replaceAttachmentStore &&
          await attachments.exists() &&
          !await quarantinedAttachments.exists()) {
        await attachments.rename(quarantinedAttachments.path);
      }

      await DatabaseMetadataStore(paths.metadataFile).write(
        DatabaseMetadata(
          databaseId: journal.databaseId,
          activeKeyId: journal.keyId,
          keyGeneration: journal.keyGeneration,
          cipherProfileId: journal.cipherProfileId,
          encryptionEnabled: true,
          databaseFile: p.basename(paths.databaseFile.path),
          createdAt: identity.createdAt,
          lastOpenedAt: AppClock.now().toUtc(),
        ),
      );

      if (journal.attachmentsIncluded) {
        final attachmentKey = await attachmentKeyStore.readStaged();
        if (attachmentKey == null) {
          throw const DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            'The staged attachment key is missing. Stage the package again.',
          );
        }
        previousAttachmentKey = await attachmentKeyStore.read();
        attachmentKeyCaptured = true;
        await _installAttachments(staging: staging, destination: attachments);
        await attachmentKeyStore.write(attachmentKey);
        await attachmentKeyStore.clearStaged();
      } else {
        await attachmentKeyStore.clearStaged();
      }

      _verifyInstalled(paths.databaseFile, profile, stagedKey.bytes, journal);
      await journalStore.write(journal.advance(RestoreStage.applied));
      await journalStore.clear();
      await _deleteDirectory(staging);
      return true;
    } catch (error) {
      await _rollback(
        paths: paths,
        journal: journal,
        keyStore: keyStore,
        attachmentKeyStore: attachmentKeyStore,
        quarantine: quarantine,
        previousDatabase: previousDatabase,
        previousMetadata: previousMetadata,
        previousAttachmentKey: previousAttachmentKey,
        attachmentKeyCaptured: attachmentKeyCaptured,
      );
      await journalStore.write(journal.fail('RESTORE_APPLY_FAILED'));
      if (error is DatabaseSecurityException) rethrow;
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'The staged database restore failed. The previous database was kept '
        'in quarantine.',
        cause: error,
      );
    }
  }

  Future<void> _installAttachments({
    required Directory staging,
    required Directory destination,
  }) async {
    final source = Directory(p.join(staging.path, 'attachments'));
    if (!await source.exists()) return;
    await for (final entity in source.list(recursive: true)) {
      if (entity is! File) continue;
      final relative = p.relative(entity.path, from: source.path);
      if (relative.contains('..') || p.isAbsolute(relative)) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'The staged attachment path is unsafe.',
        );
      }
      final target = File(p.join(destination.path, relative));
      await AtomicFile.copyAndVerify(entity, target);
    }
  }

  Future<void> _rollback({
    required DatabasePaths paths,
    required RestoreJournal journal,
    required DatabaseKeyStore keyStore,
    required AttachmentKeyStore attachmentKeyStore,
    required Directory quarantine,
    required File previousDatabase,
    required File previousMetadata,
    Uint8List? previousAttachmentKey,
    bool attachmentKeyCaptured = false,
  }) async {
    try {
      final installedDb = paths.databaseFile;
      if (await installedDb.exists()) {
        for (final file in paths.databaseAndSidecars) {
          await AtomicFile.deleteIfExists(file);
        }
      }
      if (await previousDatabase.exists()) {
        final temp = File(
          '${paths.databaseFile.path}.rollback-'
          '${AppClock.now().microsecondsSinceEpoch}',
        );
        try {
          await AtomicFile.copyAndVerify(previousDatabase, temp);
          await AtomicFile.replaceAtomically(temp, paths.databaseFile);
        } finally {
          await AtomicFile.deleteIfExists(temp);
        }
      }
      if (await previousMetadata.exists()) {
        await AtomicFile.copyAndVerify(previousMetadata, paths.metadataFile);
      } else {
        await AtomicFile.deleteIfExists(paths.metadataFile);
      }
      for (final journalFile in <File>[
        paths.migrationJournalFile,
        paths.rotationJournalFile,
      ]) {
        final quarantined = File(
          p.join(quarantine.path, p.basename(journalFile.path)),
        );
        if (await quarantined.exists()) {
          await AtomicFile.copyAndVerify(quarantined, journalFile);
        }
      }

      final attachments = Directory(
        p.join(paths.dataDirectory.path, 'attachments'),
      );
      final quarantinedAttachments = Directory(
        p.join(quarantine.path, 'attachments'),
      );
      if (await quarantinedAttachments.exists()) {
        await _deleteDirectory(attachments);
        await quarantinedAttachments.rename(attachments.path);
      }

      if (journal.previousKeyId.isNotEmpty) {
        final rolledBack = await keyStore.readStaged(
          '$_stagedRollbackPrefix${journal.previousKeyId}',
        );
        if (rolledBack != null) {
          await keyStore.write(
            DatabaseKeyRecord(
              keyId: journal.previousKeyId,
              generation: rolledBack.generation,
              databaseId: rolledBack.databaseId,
              cipherProfileId: rolledBack.cipherProfileId,
              bytes: rolledBack.bytes,
              createdAt: rolledBack.createdAt,
              active: true,
            ),
          );
          await keyStore.markActive(journal.previousKeyId);
          await keyStore.deleteStaged(
            '$_stagedRollbackPrefix${journal.previousKeyId}',
          );
        } else {
          await keyStore.markActive(journal.previousKeyId);
        }
      }
      await keyStore.deleteStaged(journal.keyId);
      if (attachmentKeyCaptured) {
        if (previousAttachmentKey != null) {
          await attachmentKeyStore.write(previousAttachmentKey);
        } else {
          await attachmentKeyStore.delete();
        }
      }
      await attachmentKeyStore.clearStaged();
      await _deleteDirectory(Directory(journal.stagedDirectory));
    } catch (_) {
      // Keep the journal and staging so the next start can retry or the user
      // can inspect the quarantined files.
    }
  }

  bool _liveDatabaseMatches(
    DatabasePaths paths,
    CipherProfile profile,
    Uint8List dek,
    RestoreJournal journal,
  ) {
    if (!paths.databaseFile.existsSync()) return false;
    try {
      final identity = _readIdentity(paths.databaseFile.path, profile, dek);
      return identity != null &&
          identity.databaseId == journal.databaseId &&
          identity.keyId == journal.keyId &&
          identity.keyGeneration == journal.keyGeneration;
    } on Object {
      return false;
    }
  }

  DatabaseIdentity _readVerifiedIdentity(
    File file,
    CipherProfile profile,
    Uint8List dek,
    RestoreJournal journal,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, dek);
      DatabaseParityVerifier.requireIntegrity(db);
      final identity = DatabaseIdentityStore.read(db);
      if (identity == null) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The staged database has no identity anchor.',
        );
      }
      if (identity.databaseId != journal.databaseId ||
          identity.keyId != journal.keyId ||
          identity.keyGeneration != journal.keyGeneration ||
          identity.cipherProfileId != journal.cipherProfileId) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The staged database identity does not match the restore journal.',
        );
      }
      return identity;
    } finally {
      db.dispose();
    }
  }

  DatabaseIdentity? _readIdentity(
    String path,
    CipherProfile profile,
    Uint8List dek,
  ) {
    final db = SqliteRuntime.open(path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, dek);
      return DatabaseIdentityStore.read(db);
    } on Object {
      return null;
    } finally {
      db.dispose();
    }
  }

  void _verifyInstalled(
    File file,
    CipherProfile profile,
    Uint8List dek,
    RestoreJournal journal,
  ) {
    final identity = _readVerifiedIdentity(file, profile, dek, journal);
    if (identity.databaseId != journal.databaseId) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The installed database identity is wrong.',
      );
    }
  }

  static void _requireIdentity(
    RecoveryPackageManifest manifest,
    OpenedRecoveryBundle opened,
  ) {
    if (manifest.databaseId != opened.databaseId ||
        manifest.keyId != opened.keyId ||
        manifest.keyGeneration != opened.keyGeneration ||
        manifest.cipherProfileId != opened.cipherProfileId) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The recovery envelope identity does not match the manifest.',
      );
    }
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort.
    }
  }
}
