import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../security/atomic_file.dart';
import '../security/cipher_profile.dart';
import '../security/database_file_inspector.dart';
import '../security/database_security_errors.dart';
import '../security/sqlite3mc.dart';
import '../utils/app_clock.dart';

/// Kept here so the maintenance layer does not need to import the Drift
/// database class (which would create an export cycle).
const currentDatabaseSchemaVersion = 17;

/// Preserve a consistent SQLite snapshot before Drift upgrades an older file.
///
/// The snapshot is **encryption-aware**.  A plaintext source still produces a
/// labelled plaintext `.bak`; an encrypted source is copied only after being
/// opened with its key and checkpointed, so this helper can never create a
/// plaintext copy of an encrypted database.
Future<void> backupDatabaseBeforeUpgrade(
  File file, {
  int targetVersion = currentDatabaseSchemaVersion,
  Directory? backupDirectory,
  CipherProfile? profile,
  List<int>? dek,
}) async {
  final kind = await DatabaseFileInspector.classify(file);
  if (kind == DatabaseFileKind.missing ||
      kind == DatabaseFileKind.empty ||
      kind == DatabaseFileKind.corrupt) {
    if (kind == DatabaseFileKind.corrupt) {
      throw StateError('Existing database file is too short to be SQLite.');
    }
    return;
  }

  if (kind == DatabaseFileKind.encryptedOrUnknown) {
    if (profile == null || dek == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'An encrypted database cannot be backed up without its key.',
      );
    }
    await _backupEncryptedDatabase(
      file,
      targetVersion: targetVersion,
      backupDirectory: backupDirectory,
      profile: profile,
      dek: dek,
    );
    return;
  }

  await _backupPlaintextDatabase(
    file,
    targetVersion: targetVersion,
    backupDirectory: backupDirectory,
  );
}

Future<void> _backupPlaintextDatabase(
  File file, {
  required int targetVersion,
  Directory? backupDirectory,
}) async {
  final source = SqliteRuntime.open(file.path);
  try {
    source.execute('PRAGMA temp_store = MEMORY');
    final versionRows = source.select('PRAGMA user_version');
    final version = versionRows.first['user_version'] as int;
    if (version >= targetVersion) return;

    // New SQLite files have user_version=0 and no user tables. A non-empty
    // unversioned database is different: preserve it before Drift attempts a
    // migration, even if it came from an older or interrupted app version.
    if (version == 0) {
      final tables = source.select(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      if (tables.isEmpty) return;
    }

    final integrity = source.select('PRAGMA integrity_check');
    if (integrity.length != 1 || integrity.first.values.first != 'ok') {
      throw StateError('Existing database failed integrity_check: $integrity');
    }

    final backupPath = _backupPath(
      file,
      targetVersion: targetVersion,
      backupDirectory: backupDirectory,
    );
    if (backupDirectory != null) {
      await backupDirectory.create(recursive: true);
    }
    final escapedPath = backupPath.replaceAll("'", "''");
    source.execute("VACUUM INTO '$escapedPath'");
    if (!await File(backupPath).exists()) {
      throw StateError('Pre-migration backup was not created: $backupPath');
    }
  } finally {
    source.dispose();
  }
}

Future<void> _backupEncryptedDatabase(
  File file, {
  required int targetVersion,
  Directory? backupDirectory,
  required CipherProfile profile,
  required List<int> dek,
}) async {
  final bytes = dek is Uint8List ? dek : Uint8List.fromList(dek);
  if (bytes.length != 32) {
    throw const DatabaseSecurityException(
      DatabaseSecurityErrorCode.wrongKey,
      'The database key has the wrong length.',
    );
  }
  final source = SqliteRuntime.open(file.path);
  try {
    try {
      SqliteCipherRuntime.applyKey(source, profile, bytes);
    } on StateError catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'SQLite3MultipleCiphers is not available in the loaded build.',
        cause: error,
      );
    }
    source.execute('PRAGMA temp_store = MEMORY');
    final versionRows = source.select('PRAGMA user_version');
    final version = versionRows.first['user_version'] as int;
    if (version >= targetVersion) return;
    source.execute('PRAGMA wal_checkpoint(TRUNCATE)');
  } finally {
    source.dispose();
  }

  // The source is closed and checkpointed: copy the main file and sidecars.
  final backupPath = _backupPath(
    file,
    targetVersion: targetVersion,
    backupDirectory: backupDirectory,
  );
  final target = File(backupPath);
  await target.parent.create(recursive: true);
  // The copy must be byte-verified before it is called a safety backup. It is
  // still ciphertext; no plaintext export happens here.
  await AtomicFile.copyAndVerify(file, target);
  for (final sidecar in DatabaseFileInspector.sidecars(file)) {
    if (!await sidecar.exists()) continue;
    final suffix = sidecar.path.substring(file.path.length);
    await AtomicFile.copyAndVerify(sidecar, File('${target.path}$suffix'));
  }
}

String _backupPath(
  File file, {
  required int targetVersion,
  Directory? backupDirectory,
}) {
  final stamp = AppClock.now().toIso8601String().replaceAll(':', '-');
  final basePath = backupDirectory == null
      ? file.path
      : p.join(backupDirectory.path, p.basename(file.path));
  return '$basePath.pre-migration-v$targetVersion-$stamp.bak';
}
