import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';

import '../utils/app_clock.dart';

/// Durable file operations used by metadata, journals, backups and key
/// material.
///
/// The write path is deliberately conservative:
///
/// 1. write a unique sibling temporary file;
/// 2. flush and close it;
/// 3. read it back and verify length + checksum;
/// 4. replace the destination atomically.
///
/// On Windows a plain `rename()` refuses to overwrite an existing destination,
/// so the old implementation deleted the destination first. That made a crash
/// between deletion and rename destroy the only copy. This class now uses
/// `MoveFileExW(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)` instead.
abstract final class AtomicFile {
  static Future<void> writeAtomically(File destination, List<int> bytes) =>
      writeBytes(destination, bytes);

  static Future<void> writeString(File target, String contents) async {
    await writeBytes(target, utf8.encode(contents));
  }

  static Future<void> writeBytes(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp-${AppClock.now().microsecondsSinceEpoch}',
    );
    try {
      final handle = await temp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeFrom(bytes);
        await handle.flush();
      } finally {
        await handle.close();
      }

      final readBack = await temp.readAsBytes();
      if (!_sameBytes(readBack, bytes)) {
        throw FileSystemException(
          'Temporary file verification failed',
          temp.path,
        );
      }
      await replaceAtomically(temp, target);
    } finally {
      await deleteIfExists(temp);
    }
  }

  /// Replaces [destination] with [source] without ever deleting the
  /// destination first.
  static Future<void> replaceAtomically(File source, File destination) async {
    await destination.parent.create(recursive: true);
    if (Platform.isWindows) {
      _replaceOnWindows(source.path, destination.path);
      return;
    }
    await source.rename(destination.path);
  }

  /// Backwards-compatible name used by existing callers.
  static Future<void> replace(File source, File target) =>
      replaceAtomically(source, target);

  /// Copies [source] to a verified temporary sibling and promotes it.
  ///
  /// The destination is untouched until the copy has been read back and its
  /// SHA-256 matches the source.
  static Future<void> copyAndVerify(File source, File destination) async {
    await destination.parent.create(recursive: true);
    final temp = File(
      '${destination.path}.copy-${AppClock.now().microsecondsSinceEpoch}',
    );
    try {
      await source.copy(temp.path);
      await flushFile(temp);
      final sourceDigest = await crypto.sha256.bind(source.openRead()).first;
      final copyDigest = await crypto.sha256.bind(temp.openRead()).first;
      if (sourceDigest != copyDigest) {
        throw FileSystemException(
          'Copied file does not match its source',
          destination.path,
        );
      }
      await replaceAtomically(temp, destination);
    } finally {
      await deleteIfExists(temp);
    }
  }

  static Future<void> flushFile(File file) async {
    final handle = await file.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  /// Verifies the SHA-256 of [file] against [expectedChecksum].
  ///
  /// Accepted forms are `sha256:<hex>` and a bare hex digest.
  static Future<void> verifyFile(File file, String expectedChecksum) async {
    if (!await file.exists()) {
      throw FileSystemException('File to verify is missing', file.path);
    }
    final actual = await checksum(file);
    final normalized = expectedChecksum.startsWith('sha256:')
        ? expectedChecksum.substring('sha256:'.length)
        : expectedChecksum;
    if (actual != normalized) {
      throw FileSystemException(
        'Checksum mismatch',
        file.path,
        OSError('expected $normalized, got $actual'),
      );
    }
  }

  static Future<String> checksum(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Deletes a file if it exists, ignoring a concurrently removed file.
  static Future<void> deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Another process may have removed it first.
    }
  }

  static bool _sameBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static void _replaceOnWindows(String source, String destination) {
    final sourcePointer = source.toNativeUtf16();
    final destinationPointer = destination.toNativeUtf16();
    try {
      final succeeded = _moveFileExW(
        sourcePointer.cast<ffi.Uint16>(),
        destinationPointer.cast<ffi.Uint16>(),
        _moveFileReplaceExisting | _moveFileWriteThrough,
      );
      if (succeeded == 0) {
        final code = _getLastError();
        throw FileSystemException(
          'Atomic replacement failed',
          destination,
          OSError('MoveFileExW error $code', code),
        );
      }
    } finally {
      malloc.free(sourcePointer);
      malloc.free(destinationPointer);
    }
  }

  static const _moveFileReplaceExisting = 0x1;
  static const _moveFileWriteThrough = 0x8;

  static final _moveFileExW = ffi.DynamicLibrary.open('kernel32.dll')
      .lookupFunction<
        ffi.Int32 Function(
          ffi.Pointer<ffi.Uint16>,
          ffi.Pointer<ffi.Uint16>,
          ffi.Uint32,
        ),
        int Function(ffi.Pointer<ffi.Uint16>, ffi.Pointer<ffi.Uint16>, int)
      >('MoveFileExW');

  static final _getLastError = ffi.DynamicLibrary.open(
    'kernel32.dll',
  ).lookupFunction<ffi.Uint32 Function(), int Function()>('GetLastError');
}
