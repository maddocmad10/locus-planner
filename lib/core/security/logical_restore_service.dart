import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../services/attachments/attachment_key_store.dart';
import '../services/crypto/encrypted_envelope.dart';
import '../services/crypto/key_derivation.dart';
import '../services/data_export_service.dart';
import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'cipher_profile.dart';
import 'database_bootstrap.dart';
import 'database_identity.dart';
import 'database_key_service.dart';
import 'database_key_store.dart';
import 'database_lifecycle_lock.dart';
import 'database_metadata.dart';
import 'database_parity_verifier.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'database_security_options.dart';
import 'restore_journal.dart';
import 'sqlite3mc.dart';

/// Thrown when a logical backup cannot be staged as a new installation.
class LogicalRestoreException implements Exception {
  const LogicalRestoreException(this.message);

  final String message;

  @override
  String toString() => 'LogicalRestoreException: $message';
}

class LogicalRestoreResult {
  const LogicalRestoreResult({
    required this.journal,
    required this.report,
    required this.backupSha256,
    required this.sourceDatabaseId,
  });

  final RestoreJournal journal;
  final RestoreReport report;
  final String backupSha256;
  final String? sourceDatabaseId;
}

/// Builds a fresh encrypted installation from a logical backup.
///
/// The staged database gets a new database ID, key ID, DEK, device ID and sync
/// epoch. The current database, key and files are untouched until the staged
/// restore is applied at the next startup. Local attachment blobs are left in
/// place: the imported metadata can reuse any blob this device already has.
class LogicalRestoreService {
  const LogicalRestoreService();

  Future<int> _nextRestoreGeneration(
    DatabasePaths paths,
    DatabaseMetadata? metadata,
    DatabaseKeyStore keyStore,
  ) async {
    if (metadata == null) return 1;
    final key = await keyStore.read(metadata.activeKeyId);
    if (key == null) return 1;
    final profile = CipherProfiles.byId(metadata.cipherProfileId);
    if (profile == null) return 1;
    sqlite3.Database? db;
    try {
      db = SqliteRuntime.open(paths.databaseFile.path);
      SqliteCipherRuntime.applyKey(db, profile, key.bytes);
      final rows = db.select(
        'SELECT value FROM app_settings WHERE key = ?',
        <Object?>[AppDatabase.restoreGenerationSettingKey],
      );
      final previous = rows.isEmpty
          ? null
          : int.tryParse(rows.first['value'] as String? ?? '');
      return (previous ?? 0) + 1;
    } on Object {
      return 1;
    } finally {
      db?.dispose();
    }
  }

  Future<LogicalRestoreResult> stage({
    required DatabasePaths paths,
    required File backup,
    required String? passphrase,
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
        p.join(paths.dataDirectory.path, 'recovery', 'logical-$stamp'),
      );
      await staging.create(recursive: true);
      DatabaseKeyRecord? stagedKey;
      final previousContext = DatabaseRuntimeContext.current;
      try {
        final json = await _readBackup(backup, passphrase);
        _validateBackupJson(json);
        final provenance = _provenance(json);

        final currentMetadata = await DatabaseMetadataStore(
          paths.metadataFile,
        ).read();
        final profile =
            CipherProfiles.byId(
              currentMetadata?.cipherProfileId ??
                  DatabaseSecurity.profile.profileId,
            ) ??
            DatabaseSecurity.profile;

        var maxGeneration = 0;
        for (final record in await keyStore.listVersions()) {
          if (record.generation > maxGeneration) {
            maxGeneration = record.generation;
          }
        }
        final generation = maxGeneration + 1;
        final keyId = DatabaseKeyService.keyIdForGeneration(generation);
        final databaseId = 'db-${const Uuid().v4()}';
        final dek = KeyDerivation.randomBytes(32);
        final now = AppClock.now().toUtc();
        final nextRestoreGeneration = await _nextRestoreGeneration(
          paths,
          currentMetadata,
          keyStore,
        );
        final identity = DatabaseIdentity(
          databaseId: databaseId,
          keyId: keyId,
          keyGeneration: generation,
          cipherProfileId: profile.profileId,
          createdAt: now,
        );

        final stagedDatabase = File(p.join(staging.path, 'locus_planner.db'));
        final anchor = SqliteRuntime.open(stagedDatabase.path);
        try {
          SqliteCipherRuntime.applyKey(anchor, profile, dek);
          DatabaseIdentityStore.write(anchor, identity);
        } finally {
          anchor.dispose();
        }

        // Opening the staged database must not be compared with the live
        // database's runtime identity.
        DatabaseRuntimeContext.current = null;
        final executor = NativeDatabase.createInBackground(
          stagedDatabase,
          isolateSetup: Sqlite3mcLoader.ensureConfigured,
          setup: (db) {
            for (final statement in profile.keyStatements(dek)) {
              db.execute(statement);
            }
            db.select(profile.verificationQuery);
          },
        );
        final stagedDb = AppDatabase.forTesting(
          executor,
          schemaVersion: currentDatabaseSchemaVersion,
        );
        late RestoreReport report;
        try {
          await stagedDb.customSelect('SELECT 1 AS ok').get();
          await stagedDb.setSetting(
            AppDatabase.syncSuppressOutboxSettingKey,
            '1',
          );
          report = await DataExportService(
            stagedDb,
            backupDirectory: paths.backupsDirectory,
          ).restoreFromJson(json);

          await stagedDb.customStatement('DELETE FROM sync_outbox');
          await stagedDb.setSetting(
            AppDatabase.syncSuppressOutboxSettingKey,
            '0',
          );
          await stagedDb.setSetting(
            AppDatabase.syncDeviceIdSettingKey,
            const Uuid().v4(),
          );
          await stagedDb.setSetting(
            AppDatabase.syncEpochSettingKey,
            const Uuid().v4(),
          );
          await stagedDb.setSetting(
            AppDatabase.syncServerPairedClientsSettingKey,
            '[]',
          );
          await stagedDb.setSetting(
            AppDatabase.syncServerEnabledSettingKey,
            '0',
          );
          await stagedDb.setSetting(
            AppDatabase.syncRebaseRequiredSettingKey,
            '1',
          );
          await stagedDb.setSetting(
            AppDatabase.restoreGenerationSettingKey,
            '$nextRestoreGeneration',
          );
          await stagedDb.setSetting(
            AppDatabase.restoreTimestampSettingKey,
            now.toIso8601String(),
          );
          await stagedDb.setSetting(
            AppDatabase.restoreSourceBackupSha256SettingKey,
            provenance.payloadSha256 ?? await AtomicFile.checksum(backup),
          );
          if (provenance.databaseId != null) {
            await stagedDb.setSetting(
              AppDatabase.restoreSourceDatabaseIdSettingKey,
              provenance.databaseId!,
            );
          }
          if (provenance.exportedAt != null) {
            await stagedDb.setSetting(
              AppDatabase.restoreSourceExportedAtSettingKey,
              provenance.exportedAt!,
            );
          }
          await stagedDb.verifyIntegrity();
        } finally {
          await stagedDb.close();
        }

        _verifyStagedDatabase(stagedDatabase, profile, dek, identity);

        await attachmentKeyStore.loadOrCreate();
        stagedKey = DatabaseKeyRecord(
          keyId: keyId,
          generation: generation,
          databaseId: databaseId,
          cipherProfileId: profile.profileId,
          bytes: dek,
          createdAt: now,
          active: false,
        );
        await keyStore.writeStaged(stagedKey);

        final journal = RestoreJournal(
          packageSha256: await AtomicFile.checksum(backup),
          stagedDirectory: staging.path,
          quarantineDirectory: p.join(
            paths.quarantineDirectory.path,
            'logical-restore-$stamp',
          ),
          databaseId: databaseId,
          keyId: keyId,
          keyGeneration: generation,
          cipherProfileId: profile.profileId,
          databaseSha256: await AtomicFile.checksum(stagedDatabase),
          databaseBytes: await stagedDatabase.length(),
          schemaVersion: currentDatabaseSchemaVersion,
          attachmentsIncluded: false,
          attachmentCount: 0,
          replaceAttachmentStore: false,
          previousDatabaseId: currentMetadata?.databaseId ?? '',
          previousKeyId: currentMetadata?.activeKeyId ?? '',
          previousKeyGeneration: currentMetadata?.keyGeneration ?? 0,
          previousCipherProfileId: currentMetadata?.cipherProfileId ?? '',
          previousDatabaseFile:
              currentMetadata?.databaseFile ??
              p.basename(paths.databaseFile.path),
          startedAt: now,
          updatedAt: now,
        );
        await journalStore.write(journal);
        return LogicalRestoreResult(
          journal: journal,
          report: report,
          backupSha256: journal.packageSha256,
          sourceDatabaseId: provenance.databaseId,
        );
      } catch (error) {
        await keyStore.deleteStaged(stagedKey?.keyId ?? '');
        await _deleteDirectory(staging);
        if (error is DatabaseSecurityException) rethrow;
        if (error is LogicalRestoreException) {
          throw DatabaseSecurityException(
            DatabaseSecurityErrorCode.recoveryRequired,
            error.message,
            cause: error,
          );
        }
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'The logical backup could not be staged.',
          cause: error,
        );
      } finally {
        DatabaseRuntimeContext.current = previousContext;
      }
    });
  }

  Future<String> _readBackup(File backup, String? passphrase) async {
    if (!await backup.exists()) {
      throw const LogicalRestoreException('The backup file is missing.');
    }
    if (await backup.length() > DataExportService.maxImportFileBytes) {
      throw const LogicalRestoreException(
        'The backup is too large to import on this device.',
      );
    }
    final text = await backup.readAsString();
    if (!EncryptedEnvelope.looksEncrypted(text)) return text;
    if (passphrase == null || passphrase.isEmpty) {
      throw const LogicalRestoreException(
        'That backup is encrypted. Enter its passphrase.',
      );
    }
    try {
      final opened = await EncryptedEnvelope.open(text, passphrase);
      if (opened.payloadType != EncryptedEnvelope.payloadFullBackup) {
        throw const LogicalRestoreException(
          'That encrypted file is not a full Locus backup.',
        );
      }
      return opened.plaintext;
    } on BackupDecryptionException catch (error) {
      throw LogicalRestoreException(error.message);
    }
  }

  void _validateBackupJson(String json) {
    try {
      BackupImportPlan.parse(json);
    } on FormatException catch (error) {
      throw LogicalRestoreException(error.message);
    }
  }

  _BackupProvenance _provenance(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      throw const LogicalRestoreException('The backup is not a JSON object.');
    }
    final exportedAt = decoded['exported_at'];
    return _BackupProvenance(
      payloadSha256: decoded['payload_sha256'] is String
          ? decoded['payload_sha256'] as String
          : null,
      databaseId: decoded['source_database_id'] is String
          ? decoded['source_database_id'] as String
          : null,
      exportedAt: exportedAt is String ? exportedAt : null,
    );
  }

  void _verifyStagedDatabase(
    File file,
    CipherProfile profile,
    Uint8List dek,
    DatabaseIdentity identity,
  ) {
    final db = SqliteRuntime.open(file.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, dek);
      DatabaseParityVerifier.requireIntegrity(db);
      final stored = DatabaseIdentityStore.read(db);
      if (stored == null ||
          stored.databaseId != identity.databaseId ||
          stored.keyId != identity.keyId ||
          stored.keyGeneration != identity.keyGeneration ||
          stored.cipherProfileId != identity.cipherProfileId) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The staged logical database identity is wrong.',
        );
      }
      final rows = db.select('PRAGMA user_version');
      final version = rows.isEmpty ? 0 : rows.first['user_version'] as int;
      if (version != currentDatabaseSchemaVersion) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.identityMismatch,
          'The staged logical database has the wrong schema version.',
        );
      }
    } finally {
      db.dispose();
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

class _BackupProvenance {
  const _BackupProvenance({
    required this.payloadSha256,
    required this.databaseId,
    required this.exportedAt,
  });

  final String? payloadSha256;
  final String? databaseId;
  final String? exportedAt;
}
