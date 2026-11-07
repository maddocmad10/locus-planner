import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_clock.dart';
import 'attachment_crypto.dart';

/// Content-addressed, encrypted blob storage on this device.
///
/// Layout under [root] (the application support directory):
///
/// ```text
/// attachments/ab/<file-id>       sealed blob
/// attachments/thumbs/<file-id>.t sealed 256 px thumbnail
/// attachments/tmp/               partial imports and temporary open copies
/// ```
///
/// `<file-id>` is an HMAC of the plaintext SHA-256, so the file system never
/// exposes content hashes. The same hash always maps to the same file, which
/// gives deduplication without a database lookup.
class AttachmentStore {
  AttachmentStore({required this.root, required this.crypto});

  /// Application support directory that holds the `attachments/` subtree.
  final Directory root;
  final AttachmentCrypto crypto;
  final Random _random = Random.secure();

  Directory get _attachmentsRoot => Directory(p.join(root.path, 'attachments'));

  Directory get blobsDirectory =>
      Directory(p.join(_attachmentsRoot.path, 'ab'));

  Directory get thumbsDirectory =>
      Directory(p.join(_attachmentsRoot.path, 'thumbs'));

  Directory get tmpDirectory => Directory(p.join(_attachmentsRoot.path, 'tmp'));

  Directory get _openDirectory => Directory(p.join(tmpDirectory.path, 'open'));

  Directory get _importDirectory =>
      Directory(p.join(tmpDirectory.path, 'import'));

  /// Creates every directory without deleting anything. Used by the LAN sync
  /// server, which may start before the attachment UI initializes.
  Future<void> ensureLayout() async {
    await blobsDirectory.create(recursive: true);
    await thumbsDirectory.create(recursive: true);
    await tmpDirectory.create(recursive: true);
    await _openDirectory.create(recursive: true);
    await _importDirectory.create(recursive: true);
  }

  /// Creates the layout and removes partial work from a previous run. Open
  /// copies are removed too: they are plaintext by definition.
  Future<void> prepare() async {
    await tmpDirectory.create(recursive: true);
    await _deleteDirectory(_importDirectory);
    await _deleteDirectory(_openDirectory);
    // Archive builders write a short-lived plaintext container directly under
    // tmp/. Remove one left behind by a crash.
    await for (final entity in tmpDirectory.list(followLinks: false)) {
      if (entity is File && p.basename(entity.path).startsWith('arc-')) {
        try {
          await entity.delete();
        } catch (_) {
          // A locked file is retried on the next startup.
        }
      }
    }
    await ensureLayout();
  }

  /// A fresh partial-import file under `attachments/tmp/import`. The caller
  /// must delete it after use, whether the import succeeds or fails.
  Future<File> newImportFile() async {
    await _importDirectory.create(recursive: true);
    final name =
        '${AppClock.now().microsecondsSinceEpoch}-'
        '${_random.nextInt(1 << 32)}.part';
    return File(p.join(_importDirectory.path, name));
  }

  /// Stable partial-download file for [sha256Hex]. A resumed Range download
  /// appends here; `prepare()` deletes the directory at the next startup.
  Future<File> partialDownloadFile(String sha256Hex) async {
    await _importDirectory.create(recursive: true);
    return File(
      p.join(_importDirectory.path, 'dl-${crypto.fileId(sha256Hex)}.part'),
    );
  }

  File blobFile(String sha256Hex) =>
      File(p.join(blobsDirectory.path, crypto.fileId(sha256Hex)));

  File thumbFile(String sha256Hex) =>
      File(p.join(thumbsDirectory.path, '${crypto.fileId(sha256Hex)}.t'));

  Future<bool> hasBlob(String sha256Hex) => blobFile(sha256Hex).exists();

  Future<int?> blobLength(String sha256Hex) async {
    final file = blobFile(sha256Hex);
    return await file.exists() ? file.length() : null;
  }

  /// Seals [plaintext] and returns its hex SHA-256.
  Future<String> putBytes(Uint8List plaintext) async {
    final sha256Hex = sha256.convert(plaintext).toString();
    final target = blobFile(sha256Hex);
    if (await target.exists()) return sha256Hex;

    await blobsDirectory.create(recursive: true);
    final temp = File(p.join(_importDirectory.path, '${_randomHex(12)}.part'));
    await temp.writeAsBytes(crypto.sealBytes(plaintext), flush: true);
    await target.parent.create(recursive: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      // Another import won the race, or Windows refused to replace an existing
      // file. Either way identical content is already present.
      if (await target.exists()) {
        await _deleteFile(temp);
      } else {
        rethrow;
      }
    }
    return sha256Hex;
  }

  Future<Uint8List> readBytes(String sha256Hex) async {
    final file = blobFile(sha256Hex);
    if (!await file.exists()) {
      throw const AttachmentBlobCorruptException('Attachment file is missing.');
    }
    final sealed = await file.readAsBytes();
    final plaintext = crypto.openBytes(sealed);
    final actual = sha256.convert(plaintext).toString();
    if (actual != sha256Hex) {
      throw const AttachmentBlobCorruptException(
        'Attachment content does not match its hash.',
      );
    }
    return plaintext;
  }

  Future<void> putThumb(String sha256Hex, Uint8List jpeg) async {
    await thumbsDirectory.create(recursive: true);
    final temp = File(p.join(_importDirectory.path, '${_randomHex(12)}.tpart'));
    await temp.writeAsBytes(crypto.sealBytes(jpeg), flush: true);
    final target = thumbFile(sha256Hex);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) {
        await _deleteFile(temp);
      } else {
        rethrow;
      }
    }
  }

  Future<Uint8List?> readThumb(String sha256Hex) async {
    final file = thumbFile(sha256Hex);
    if (!await file.exists()) return null;
    return crypto.openBytes(await file.readAsBytes());
  }

  Future<void> deleteBlob(String sha256Hex) async {
    await _deleteFile(blobFile(sha256Hex));
    await _deleteFile(thumbFile(sha256Hex));
  }

  /// Decrypts a blob into a per-session temporary folder so the OS handler can
  /// open it. The folder is removed at startup and at exit.
  Future<File> materialize(String sha256Hex, String displayName) async {
    final session = Directory(p.join(_openDirectory.path, _randomHex(8)));
    await session.create(recursive: true);
    final safeName = _safeFileComponent(displayName);
    final target = File(p.join(session.path, safeName));
    await target.writeAsBytes(await readBytes(sha256Hex), flush: true);
    return target;
  }

  Future<void> clearOpenCopies() => _deleteDirectory(_openDirectory);

  Future<void> clearImports() => _deleteDirectory(_importDirectory);

  Future<int> totalBlobBytes() async {
    if (!await blobsDirectory.exists()) return 0;
    var total = 0;
    await for (final entity in blobsDirectory.list(followLinks: false)) {
      if (entity is File) total += await entity.length();
    }
    return total;
  }

  /// Lists blob files whose file id has no metadata row. Used by the orphan
  /// sweep to remove files left behind by a crash before the row was written.
  Future<List<String>> untrackedFileIds(Set<String> trackedFileIds) async {
    if (!await blobsDirectory.exists()) return const [];
    final untracked = <String>[];
    await for (final entity in blobsDirectory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!trackedFileIds.contains(name)) untracked.add(entity.path);
    }
    return untracked;
  }

  Future<void> deleteByPath(String path) => _deleteFile(File(path));

  String _randomHex(int bytes) {
    final buffer = StringBuffer();
    for (var index = 0; index < bytes; index++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static String _safeFileComponent(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    if (cleaned.isEmpty) return 'attachment';
    return cleaned.length > 100 ? cleaned.substring(0, 100) : cleaned;
  }

  static Future<void> _deleteFile(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A file locked by an external viewer is removed by the next sweep.
    }
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // Best effort: a locked file must not block startup.
    }
  }
}
