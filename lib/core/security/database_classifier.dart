import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'cipher_profile.dart';
import 'database_artifact_inventory.dart';
import 'database_file_inspector.dart';
import 'database_key_store.dart';
import 'database_metadata.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'migration_journal.dart';
import 'sqlite3mc.dart';

/// The explicit startup states required by the reliability specification.
///
/// Classification is a single decision based on every durable signal, not a
/// collection of independent `exists()` checks.
enum DatabaseStartupState {
  freshInstall,
  recognizedPlaintext,
  encryptedDatabase,
  interruptedMigration,
  interruptedRestore,
  interruptedRotation,
  emptyDatabase,
  unknownDatabase,
  corruptedDatabase,
  recoveryRequired,
}

/// Result of startup classification.
class DatabaseClassification {
  const DatabaseClassification({
    required this.state,
    required this.fileKind,
    this.metadata,
    this.journal,
    this.databaseId,
    this.keyId,
    this.cipherProfileId,
    this.reason,
    this.errorCode,
  });

  final DatabaseStartupState state;
  final DatabaseFileKind fileKind;
  final DatabaseMetadata? metadata;
  final MigrationJournal? journal;
  final String? databaseId;
  final String? keyId;
  final String? cipherProfileId;
  final String? reason;
  final DatabaseSecurityErrorCode? errorCode;

  bool get canCreateFresh => state == DatabaseStartupState.freshInstall;
  bool get canOpenPlaintext =>
      state == DatabaseStartupState.recognizedPlaintext;
  bool get canOpenEncrypted => state == DatabaseStartupState.encryptedDatabase;
  bool get needsMigrationRecovery =>
      state == DatabaseStartupState.interruptedMigration;
  bool get mustFailClosed =>
      !canCreateFresh &&
      !canOpenPlaintext &&
      !canOpenEncrypted &&
      !needsMigrationRecovery;

  DatabaseSecurityException toException() => DatabaseSecurityException(
    errorCode ?? DatabaseSecurityErrorCode.recoveryRequired,
    reason ?? 'The database is not in a state this build can open safely.',
  );
}

/// Classifies the database before any connection is opened.
abstract final class DatabaseClassifier {
  /// Tables that identify a Locus planner schema. An unrelated SQLite file
  /// must not be adopted just because its header is valid.
  static const knownApplicationTables = <String>{
    'events',
    'projects',
    'progress_logs',
    'tasks',
    'diary_entries',
    'habits',
    'habit_logs',
    'focus_sessions',
    'app_settings',
    'todo_items',
    'todo_completions',
    'daily_plans',
    'daily_plan_items',
    'sync_outbox',
  };

  static Future<DatabaseClassification> classify({
    required DatabasePaths paths,
    required DatabaseMetadataStore metadataStore,
    required MigrationJournalStore journalStore,
    DatabaseKeyStore? keyStore,
    int maximumPlaintextSchemaVersion = 19,
  }) async {
    if (await paths.restoreJournalFile.exists()) {
      return const DatabaseClassification(
        state: DatabaseStartupState.interruptedRestore,
        fileKind: DatabaseFileKind.missing,
        reason: 'A database restore was interrupted and must be resumed.',
        errorCode: DatabaseSecurityErrorCode.recoveryRequired,
      );
    }
    if (await paths.rotationJournalFile.exists()) {
      return const DatabaseClassification(
        state: DatabaseStartupState.interruptedRotation,
        fileKind: DatabaseFileKind.missing,
        reason: 'A database key rotation was interrupted and must be resumed.',
        errorCode: DatabaseSecurityErrorCode.recoveryRequired,
      );
    }

    MigrationJournal? journal;
    try {
      journal = await journalStore.read();
    } on DatabaseSecurityException catch (error) {
      return DatabaseClassification(
        state: DatabaseStartupState.recoveryRequired,
        fileKind: DatabaseFileKind.missing,
        reason: error.message,
        errorCode: DatabaseSecurityErrorCode.migrationInterrupted,
      );
    }

    final kind = await DatabaseFileInspector.classify(paths.databaseFile);

    final artifacts = await DatabaseArtifactInventory.scan(paths);
    if (artifacts.hasUnjournaledConversionCandidate) {
      return DatabaseClassification(
        state: DatabaseStartupState.recoveryRequired,
        fileKind: kind,
        reason:
            'A database conversion candidate exists without a journal. The '
            'active database was not inferred from the filename.',
        errorCode: DatabaseSecurityErrorCode.migrationInterrupted,
      );
    }

    DatabaseMetadata? metadata;
    try {
      metadata = await metadataStore.read();
    } on DatabaseSecurityException catch (error) {
      return DatabaseClassification(
        state: DatabaseStartupState.recoveryRequired,
        fileKind: kind,
        reason: error.message,
        errorCode: DatabaseSecurityErrorCode.metadataCorrupt,
      );
    }

    if (journal != null && journal.needsRecovery) {
      return DatabaseClassification(
        state: DatabaseStartupState.interruptedMigration,
        fileKind: kind,
        metadata: metadata,
        journal: journal,
        databaseId: journal.databaseId,
        keyId: journal.newKeyId,
        cipherProfileId: journal.cipherProfileId,
        reason: journal.lastErrorCode == null
            ? 'A database conversion was interrupted.'
            : 'A database conversion stopped at ${journal.lastErrorCode}.',
        errorCode: DatabaseSecurityErrorCode.migrationInterrupted,
      );
    }

    switch (kind) {
      case DatabaseFileKind.missing:
        if (metadata != null) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            metadata: metadata,
            databaseId: metadata.databaseId,
            keyId: metadata.activeKeyId,
            cipherProfileId: metadata.cipherProfileId,
            reason:
                'Metadata describes a database that is no longer present. It '
                'was not recreated automatically.',
            errorCode: DatabaseSecurityErrorCode.databaseMissing,
          );
        }
        final keyCount = await _keyCount(keyStore);
        if (keyCount > 0) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            reason:
                'The database file is missing, but $keyCount key record(s) '
                'remain. This is a recovery situation, not a fresh install.',
            errorCode: DatabaseSecurityErrorCode.recoveryRequired,
          );
        }
        return const DatabaseClassification(
          state: DatabaseStartupState.freshInstall,
          fileKind: DatabaseFileKind.missing,
        );

      case DatabaseFileKind.empty:
        return const DatabaseClassification(
          state: DatabaseStartupState.emptyDatabase,
          fileKind: DatabaseFileKind.empty,
          reason:
              'The database file is empty; creation may have been '
              'interrupted. It was not recreated automatically.',
          errorCode: DatabaseSecurityErrorCode.zeroLengthDatabase,
        );

      case DatabaseFileKind.corrupt:
        return const DatabaseClassification(
          state: DatabaseStartupState.corruptedDatabase,
          fileKind: DatabaseFileKind.corrupt,
          reason: 'The database file is too short to be a valid SQLite file.',
          errorCode: DatabaseSecurityErrorCode.databaseDamaged,
        );

      case DatabaseFileKind.plaintext:
        if (metadata != null && metadata.encryptionEnabled) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            metadata: metadata,
            databaseId: metadata.databaseId,
            keyId: metadata.activeKeyId,
            cipherProfileId: metadata.cipherProfileId,
            reason:
                'A plaintext database was found where an encrypted one is '
                'expected.',
            errorCode:
                DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity,
          );
        }
        final probe = await _probePlaintext(paths.databaseFile);
        if (probe == null) {
          return const DatabaseClassification(
            state: DatabaseStartupState.corruptedDatabase,
            fileKind: DatabaseFileKind.plaintext,
            reason: 'The plaintext database could not be inspected.',
            errorCode: DatabaseSecurityErrorCode.databaseDamaged,
          );
        }
        if (probe.userVersion > maximumPlaintextSchemaVersion) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            metadata: metadata,
            reason:
                'The plaintext database uses schema ${probe.userVersion}, '
                'which is newer than this build supports.',
            errorCode: DatabaseSecurityErrorCode.unsupportedEncryption,
          );
        }
        if (probe.applicationTableCount == 0) {
          if (probe.tableCount == 0) {
            return const DatabaseClassification(
              state: DatabaseStartupState.emptyDatabase,
              fileKind: DatabaseFileKind.plaintext,
              reason:
                  'The file is a SQLite database but contains no '
                  'application tables.',
              errorCode: DatabaseSecurityErrorCode.zeroLengthDatabase,
            );
          }
          return const DatabaseClassification(
            state: DatabaseStartupState.unknownDatabase,
            fileKind: DatabaseFileKind.plaintext,
            reason:
                'The SQLite file does not contain a recognized Locus '
                'planner schema.',
            errorCode: DatabaseSecurityErrorCode.recoveryRequired,
          );
        }
        return DatabaseClassification(
          state: DatabaseStartupState.recognizedPlaintext,
          fileKind: kind,
          metadata: metadata,
          databaseId: metadata?.databaseId,
          keyId: metadata?.activeKeyId,
          cipherProfileId: metadata?.cipherProfileId,
        );

      case DatabaseFileKind.encryptedOrUnknown:
        if (metadata == null) {
          return const DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: DatabaseFileKind.encryptedOrUnknown,
            reason:
                'The database has an unknown or encrypted header but no '
                'metadata. It was not treated as plaintext.',
            errorCode: DatabaseSecurityErrorCode.recoveryRequired,
          );
        }
        if (!metadata.encryptionEnabled) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            metadata: metadata,
            reason:
                'Metadata describes a plaintext database but the file has an '
                'unknown or encrypted header.',
            errorCode: DatabaseSecurityErrorCode.unsupportedEncryption,
          );
        }
        final profile = CipherProfiles.byId(metadata.cipherProfileId);
        if (profile == null) {
          return DatabaseClassification(
            state: DatabaseStartupState.recoveryRequired,
            fileKind: kind,
            metadata: metadata,
            databaseId: metadata.databaseId,
            keyId: metadata.activeKeyId,
            cipherProfileId: metadata.cipherProfileId,
            reason:
                'This build does not support cipher profile '
                '"${metadata.cipherProfileId}".',
            errorCode: DatabaseSecurityErrorCode.unsupportedEncryption,
          );
        }
        if (keyStore != null) {
          try {
            final versions = await keyStore.listVersions();
            final active = versions
                .where((record) => record.active)
                .toList(growable: false);
            if (active.length > 1) {
              return DatabaseClassification(
                state: DatabaseStartupState.recoveryRequired,
                fileKind: kind,
                metadata: metadata,
                databaseId: metadata.databaseId,
                keyId: metadata.activeKeyId,
                cipherProfileId: metadata.cipherProfileId,
                reason:
                    'The key store contains ${active.length} active keys; '
                    'exactly one is required.',
                errorCode: DatabaseSecurityErrorCode.recoveryRequired,
              );
            }
            final key = await keyStore.read(metadata.activeKeyId);
            if (key == null) {
              return DatabaseClassification(
                state: DatabaseStartupState.recoveryRequired,
                fileKind: kind,
                metadata: metadata,
                databaseId: metadata.databaseId,
                keyId: metadata.activeKeyId,
                cipherProfileId: metadata.cipherProfileId,
                reason:
                    'The active database key is missing. Restore it from a '
                    'recovery bundle.',
                errorCode: DatabaseSecurityErrorCode.keyMissing,
              );
            }
          } on DatabaseSecurityException catch (error) {
            return DatabaseClassification(
              state: DatabaseStartupState.recoveryRequired,
              fileKind: kind,
              metadata: metadata,
              reason: error.message,
              errorCode: error.code,
            );
          }
        }
        return DatabaseClassification(
          state: DatabaseStartupState.encryptedDatabase,
          fileKind: kind,
          metadata: metadata,
          databaseId: metadata.databaseId,
          keyId: metadata.activeKeyId,
          cipherProfileId: metadata.cipherProfileId,
        );
    }
  }

  static Future<int> _keyCount(DatabaseKeyStore? store) async {
    if (store == null) return 0;
    try {
      return (await store.listVersions()).length;
    } on DatabaseSecurityException {
      // An unreadable key store is itself a recovery condition; report it as
      // "keys may exist" rather than pretending the installation is fresh.
      return 1;
    }
  }

  static Future<_PlaintextProbe?> _probePlaintext(File file) async {
    sqlite3.Database? db;
    try {
      db = SqliteRuntime.open(file.path, mode: sqlite3.OpenMode.readOnly);
      final versionRows = db.select('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : versionRows.first['user_version'] as int;
      final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'",
      );
      var applicationTables = 0;
      for (final row in tables) {
        if (knownApplicationTables.contains(row['name'])) {
          applicationTables++;
        }
      }
      return _PlaintextProbe(
        userVersion: version,
        tableCount: tables.length,
        applicationTableCount: applicationTables,
      );
    } catch (_) {
      return null;
    } finally {
      db?.dispose();
    }
  }
}

class _PlaintextProbe {
  const _PlaintextProbe({
    required this.userVersion,
    required this.tableCount,
    required this.applicationTableCount,
  });

  final int userVersion;
  final int tableCount;
  final int applicationTableCount;
}
