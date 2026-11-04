import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// How a database file presents itself before any key is applied.
enum DatabaseFileKind {
  /// The file does not exist.
  missing,

  /// The file exists but contains zero bytes (interrupted creation).
  empty,

  /// A stock SQLite file: starts with `SQLite format 3\0`.
  plaintext,

  /// Not a plaintext SQLite header.  This is the expected state for an
  /// encrypted database, but it can also be an unrelated or corrupt file; the
  /// startup state machine must never infer "encrypted" from this alone.
  encryptedOrUnknown,

  /// Too short to contain a SQLite header.
  corrupt,
}

abstract final class DatabaseFileInspector {
  static const sqliteHeader = 'SQLite format 3\u0000';

  static Future<DatabaseFileKind> classify(File file) async {
    if (!await file.exists()) return DatabaseFileKind.missing;
    final length = await file.length();
    if (length == 0) return DatabaseFileKind.empty;
    if (length < sqliteHeader.length) return DatabaseFileKind.corrupt;

    final handle = await file.open();
    try {
      final header = await handle.read(sqliteHeader.length);
      if (header.length < sqliteHeader.length) {
        return DatabaseFileKind.corrupt;
      }
      final text = String.fromCharCodes(header);
      return text == sqliteHeader
          ? DatabaseFileKind.plaintext
          : DatabaseFileKind.encryptedOrUnknown;
    } finally {
      await handle.close();
    }
  }

  static File walFile(File database) => File('${database.path}-wal');
  static File shmFile(File database) => File('${database.path}-shm');
  static File journalFile(File database) => File('${database.path}-journal');

  static List<File> sidecars(File database) => <File>[
    walFile(database),
    shmFile(database),
    journalFile(database),
  ];

  /// SHA-256 of a file, used by the migration journal and backup manifest.
  static Future<String> sha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return 'sha256:$digest';
  }

  /// Moves the main file and every sidecar into [directory].
  ///
  /// Stale sidecars must never be attached to a replacement database, so they
  /// travel with the original into quarantine.
  static Future<void> quarantine(File database, Directory directory) async {
    await directory.create(recursive: true);
    for (final source in <File>[database, ...sidecars(database)]) {
      if (!await source.exists()) continue;
      final target = File(
        '${directory.path}${Platform.pathSeparator}'
        '${source.uri.pathSegments.last}',
      );
      await source.rename(target.path);
    }
  }

  /// Copies the main file and sidecars after the source connection has been
  /// closed and checkpointed.
  static Future<void> copyWithSidecars(File source, File target) async {
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    for (final sidecar in sidecars(source)) {
      if (!await sidecar.exists()) continue;
      final suffix = sidecar.path.substring(source.path.length);
      final sidecarTarget = File('${target.path}$suffix');
      await sidecar.copy(sidecarTarget.path);
    }
  }
}
