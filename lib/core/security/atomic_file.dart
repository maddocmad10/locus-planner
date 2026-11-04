import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';

/// Small helper for the "write a temp file, flush it, then replace the target"
/// pattern used by metadata, journals, backups and key material.
///
/// SQLite data files themselves are moved with [replace] only after they have
/// been closed and verified.
abstract final class AtomicFile {
  static Future<void> writeString(File target, String contents) async {
    final bytes = await _encode(contents);
    await writeBytes(target, bytes);
  }

  static Future<void> writeBytes(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp-${AppClock.now().microsecondsSinceEpoch}',
    );
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
    await replace(temp, target);
  }

  /// Replaces [target] with [source].
  ///
  /// Dart's [File.rename] is atomic on POSIX. On Windows it fails when the
  /// destination exists, so the destination is removed first. That is the
  /// documented fallback the encryption schema allows when an OS-level
  /// replace primitive is unavailable; callers protect the operation with the
  /// migration journal.
  static Future<void> replace(File source, File target) async {
    await target.parent.create(recursive: true);
    try {
      await source.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await target.delete();
      }
      await source.rename(target.path);
    }
  }

  static Future<List<int>> _encode(String contents) async =>
      utf8.encode(contents);

  /// Deletes a file if it exists, ignoring a concurrently removed file.
  static Future<void> deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Another process may have removed it first.
    }
  }
}
