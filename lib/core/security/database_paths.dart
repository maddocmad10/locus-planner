import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_file_inspector.dart';
import 'database_security_options.dart';
import 'sqlite3mc.dart';

/// Every sensitive path used by the database lifecycle.
class DatabasePaths {
  const DatabasePaths({
    required this.dataDirectory,
    required this.databaseFile,
    this.legacyDocumentsFile,
  });

  static const databaseFileName = 'locus_planner.db';

  final Directory dataDirectory;
  final File databaseFile;

  /// The old Documents copy, when one still exists. It stays a plaintext
  /// artifact until the user chooses to remove or archive it.
  final File? legacyDocumentsFile;

  File get metadataFile => File('${databaseFile.path}.meta.json');

  File get migrationJournalFile => File('${databaseFile.path}.migration.json');

  /// Crash-safe progress of a raw or logical restore (Phase C).
  File get restoreJournalFile => File('${databaseFile.path}.restore.json');

  /// Crash-safe progress of a DEK rotation.
  File get rotationJournalFile => File('${databaseFile.path}.rotation.json');

  /// Cross-process advisory lock for database lifecycle operations.
  File get lifecycleLockFile => File('${databaseFile.path}.lifecycle.lock');

  Directory get quarantineDirectory =>
      Directory(p.join(dataDirectory.path, 'quarantine'));

  Directory get backupsDirectory =>
      Directory(p.join(dataDirectory.path, 'backups'));

  /// SQLite main file, WAL, SHM and rollback journal.
  List<File> get databaseAndSidecars => <File>[
    databaseFile,
    ...DatabaseFileInspector.sidecars(databaseFile),
  ];
}

/// Resolves the non-roaming data directory and performs the one-time move from
/// the legacy roaming/Documents locations.
abstract final class DatabasePathsResolver {
  static Future<DatabasePaths> resolve({
    DatabaseSecurityOptions? options,
    Directory? legacySupportDirectory,
    Directory? legacyDocumentsDirectory,
  }) async {
    final configured = (options ?? DatabaseSecurity.current).dataDirectory;
    final dataDirectory = configured ?? await secureDataDirectory();
    await dataDirectory.create(recursive: true);

    final databaseFile = File(
      p.join(dataDirectory.path, DatabasePaths.databaseFileName),
    );
    final legacySupport =
        legacySupportDirectory ?? await _legacySupportDirectory();
    final legacySupportFile = File(
      p.join(legacySupport.path, DatabasePaths.databaseFileName),
    );
    final documentsDirectory =
        legacyDocumentsDirectory ?? await _documentsDirectory();
    final legacyDocumentsFile = File(
      p.join(documentsDirectory.path, DatabasePaths.databaseFileName),
    );

    var resolvedFile = databaseFile;
    if (!await databaseFile.exists()) {
      if (await legacySupportFile.exists()) {
        if (await _hasMigrationJournal(legacySupportFile)) {
          // Recovery must run in place: the journal stores absolute paths.
          resolvedFile = legacySupportFile;
        } else {
          try {
            await _moveLegacyDatabase(legacySupportFile, databaseFile);
          } catch (_) {
            // Keep using the old location rather than creating an empty
            // database.
            resolvedFile = legacySupportFile;
          }
        }
      } else if (await legacyDocumentsFile.exists()) {
        if (await _hasMigrationJournal(legacyDocumentsFile)) {
          resolvedFile = legacyDocumentsFile;
        } else {
          try {
            await _moveLegacyDatabase(legacyDocumentsFile, databaseFile);
          } catch (_) {
            resolvedFile = legacyDocumentsFile;
          }
        }
      }
    }

    return DatabasePaths(
      // Keep every security sidecar next to the database that is actually in
      // use. When a legacy in-place fallback is selected, metadata and the
      // migration journal must be found there, not in the new directory.
      dataDirectory: resolvedFile.parent,
      databaseFile: resolvedFile,
      legacyDocumentsFile: await legacyDocumentsFile.exists()
          ? legacyDocumentsFile
          : null,
    );
  }

  /// Windows uses `%LOCALAPPDATA%` so the database and its key do not roam.
  /// Android's application-support directory is already app-private.
  static Future<Directory> secureDataDirectory() async {
    if (Platform.isWindows) {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return Directory(p.join(localAppData, 'LocusPlanner'));
      }
    }
    return getApplicationSupportDirectory();
  }

  static Future<Directory> _legacySupportDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory.current;
    }
  }

  static Future<Directory> _documentsDirectory() async {
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.current;
    }
  }

  /// Whether [database] has a migration journal that must be resolved in place.
  static Future<bool> _hasMigrationJournal(File database) =>
      File('${database.path}.migration.json').exists();

  /// Copies the legacy database consistently, including committed WAL data.
  ///
  /// The original is left in place: it is still a plaintext artifact and must
  /// be cleaned up with explicit user consent. Security metadata travels with
  /// the database so an encrypted file never loses its identity hint.
  static Future<void> _moveLegacyDatabase(File source, File target) async {
    final stamp = AppClock.now().microsecondsSinceEpoch;
    final temp = File('${target.path}.move-$stamp.tmp');
    final companions = <({File temp, File target})>[];
    var databaseCommitted = false;
    try {
      for (final suffix in const <String>['.meta.json', '.migration.json']) {
        final companion = File('${source.path}$suffix');
        if (!await companion.exists()) continue;
        final companionTemp = File('${target.path}$suffix.move-$stamp.tmp');
        await companionTemp.parent.create(recursive: true);
        await companion.copy(companionTemp.path);
        companions.add((
          temp: companionTemp,
          target: File('${target.path}$suffix'),
        ));
      }

      final kind = await DatabaseFileInspector.classify(source);
      if (kind == DatabaseFileKind.plaintext) {
        final db = SqliteRuntime.open(source.path);
        try {
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
          final escaped = temp.path.replaceAll("'", "''");
          db.execute("VACUUM INTO '$escaped'");
        } finally {
          db.dispose();
        }
      } else if (kind == DatabaseFileKind.missing) {
        return;
      } else {
        // Encrypted or unknown: copy bytes plus sidecars; do not interpret.
        await DatabaseFileInspector.copyWithSidecars(source, temp);
      }
      await AtomicFile.replace(temp, target);
      databaseCommitted = true;
      for (final companion in companions) {
        await AtomicFile.replace(companion.temp, companion.target);
      }
    } catch (_) {
      // A failed move must not lose the legacy file. Remove anything already
      // promoted so the next start uses the intact legacy location instead of
      // a database without its metadata.
      await AtomicFile.deleteIfExists(temp);
      for (final companion in companions) {
        await AtomicFile.deleteIfExists(companion.temp);
      }
      if (databaseCommitted) {
        await AtomicFile.deleteIfExists(target);
        for (final companion in companions) {
          await AtomicFile.deleteIfExists(companion.target);
        }
      }
      rethrow;
    }
  }
}
