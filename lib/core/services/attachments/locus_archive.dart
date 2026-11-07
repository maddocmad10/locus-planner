import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:pointycastle/api.dart'
    show AEADParameters, InvalidCipherTextException, KeyParameter;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../db/app_database.dart';
import '../../utils/app_clock.dart';
import '../crypto/key_derivation.dart';
import '../data_export_service.dart';
import 'attachment_service.dart';
import 'attachment_types.dart';

/// Thrown when an archive cannot be built, opened or verified.
class LocusArchiveException implements Exception {
  const LocusArchiveException(this.message);

  final String message;

  @override
  String toString() => 'LocusArchiveException: $message';
}

class ArchiveBuildResult {
  const ArchiveBuildResult({
    required this.file,
    required this.blobCount,
    required this.missingHashes,
  });

  final File file;
  final int blobCount;
  final List<String> missingHashes;
}

class ArchiveRestoreReport {
  const ArchiveRestoreReport({
    required this.restoredRows,
    required this.skippedRows,
    required this.blobsWritten,
    required this.missingHashes,
  });

  final int restoredRows;
  final int skippedRows;
  final int blobsWritten;
  final List<String> missingHashes;
}

/// A `.locusarchive` is a logical JSON backup plus the attachment bytes it
/// references, wrapped in a passphrase-encrypted, chunked container.
///
/// Plaintext layout:
///
/// ```text
/// "LOCUSARC1\n"                  magic
/// uint64 manifestLength
/// manifest JSON (UTF-8)          backup + blob list
/// uint32 blobCount
/// per blob: 64-byte sha256 + uint64 length + bytes
/// ```
///
/// The encrypted wrapper is `LOCUSARC1E\n`, the format version, the PBKDF2
/// iteration count, the salt, a random 8-byte nonce base and the plaintext
/// length, followed by 64 KiB AES-256-GCM chunks. The associated data covers
/// the whole header, the chunk counter and the final-chunk flag, so a flipped
/// byte, a truncated file or a reordered chunk fails closed.
class LocusArchiveService {
  const LocusArchiveService({this.workDirectory});

  /// Where the short-lived plaintext container is written. Production passes
  /// the app-private attachment temp directory, which is cleaned at startup;
  /// tests may omit it.
  final Directory? workDirectory;

  Directory get _work => workDirectory ?? Directory.systemTemp;

  static const format = 'locus.archive';
  static const version = 1;
  static const iterations = 210000;
  static const chunkSize = 64 * 1024;
  static const maxPlainBytes = 4 * 1024 * 1024 * 1024;
  static const plainMagic = <int>[
    0x4C,
    0x4F,
    0x43,
    0x55,
    0x53,
    0x41,
    0x52,
    0x43,
    0x31,
    0x0A,
  ];
  static const encryptedMagic = <int>[
    0x4C,
    0x4F,
    0x43,
    0x55,
    0x53,
    0x41,
    0x52,
    0x43,
    0x31,
    0x45,
    0x0A,
  ];
  static const _headerLength = 11 + 4 + 4 + 16 + 8 + 8;
  static const _tagLength = 16;

  static final _random = Random.secure();

  Future<ArchiveBuildResult> create({
    required AppDatabase db,
    required AttachmentService attachments,
    required String passphrase,
    required File target,
  }) async {
    if (passphrase.isEmpty) {
      throw const LocusArchiveException('Enter a passphrase for the archive.');
    }
    final backupJson = await DataExportService(db).buildBackupJson();
    final backup = jsonDecode(backupJson);
    if (backup is! Map<String, dynamic>) {
      throw const LocusArchiveException('The logical backup is not valid.');
    }

    final rows = await db.select(db.attachments).get();
    // Keep only metadata here: blobs are read one at a time below so a large
    // archive does not hold every file in memory at once.
    final blobs = <({String sha256, int sizeBytes})>[];
    final missing = <String>[];
    for (final row in rows) {
      if (!await attachments.store.hasBlob(row.sha256)) {
        if (!missing.contains(row.sha256)) missing.add(row.sha256);
        continue;
      }
      blobs.add((sha256: row.sha256, sizeBytes: row.sizeBytes));
    }

    final manifest = <String, dynamic>{
      'format': format,
      'version': version,
      'created_at': AppClock.now().toUtc().toIso8601String(),
      'database_schema_version': AppDatabase.currentSchemaVersion,
      'backup': backup,
      'blobs': [
        for (final entry in blobs)
          {'sha256': entry.sha256, 'size_bytes': entry.sizeBytes},
      ],
      'missing_hashes': missing,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));

    final plain = await File(
      '${_work.path}/arc-build-${AppClock.now().microsecondsSinceEpoch}.plain',
    ).create(recursive: true);
    try {
      final output = await plain.open(mode: FileMode.write);
      try {
        await output.writeFrom(plainMagic);
        await output.writeFrom(_uint64(manifestBytes.length));
        await output.writeFrom(manifestBytes);
        await output.writeFrom(_uint32(blobs.length));
        for (final entry in blobs) {
          // One blob at a time: verify its hash, then append its plaintext to
          // the container that is about to be encrypted.
          final bytes = await attachments.store.readBytes(entry.sha256);
          await output.writeFrom(ascii.encode(entry.sha256));
          await output.writeFrom(_uint64(bytes.length));
          await output.writeFrom(bytes);
        }
      } finally {
        await output.close();
      }
      await _sealFile(plain, target, passphrase);
    } finally {
      if (await plain.exists()) await plain.delete();
    }
    return ArchiveBuildResult(
      file: target,
      blobCount: blobs.length,
      missingHashes: missing,
    );
  }

  Future<ArchiveRestoreReport> restore({
    required AppDatabase db,
    required AttachmentService attachments,
    required File archive,
    required String passphrase,
  }) async {
    if (passphrase.isEmpty) {
      throw const LocusArchiveException('Enter the archive passphrase.');
    }
    final plain = await File(
      '${_work.path}/arc-restore-${AppClock.now().microsecondsSinceEpoch}.plain',
    ).create(recursive: true);
    try {
      await _openFile(archive, plain, passphrase);
      final input = await plain.open();
      try {
        final header = await _readExact(input, plainMagic.length);
        if (!_bytesEqual(header, plainMagic)) {
          throw const LocusArchiveException('This is not a Locus archive.');
        }
        final manifestLength = _readUint64(await _readExact(input, 8), 0);
        if (manifestLength < 2 || manifestLength > 64 * 1024 * 1024) {
          throw const LocusArchiveException('The archive manifest is invalid.');
        }
        final manifestBytes = await _readExact(input, manifestLength.toInt());
        final manifest = jsonDecode(utf8.decode(manifestBytes));
        if (manifest is! Map<String, dynamic> ||
            manifest['format'] != format ||
            manifest['version'] != version) {
          throw const LocusArchiveException('Unsupported archive version.');
        }
        final backup = manifest['backup'];
        if (backup is! Map<String, dynamic>) {
          throw const LocusArchiveException('The archive has no backup.');
        }
        final blobCount = _readUint32(await _readExact(input, 4), 0);
        if (blobCount < 0 || blobCount > 100000) {
          throw const LocusArchiveException(
            'The archive blob list is invalid.',
          );
        }
        final seen = <String>{};
        var written = 0;
        for (var index = 0; index < blobCount; index++) {
          final hashBytes = await _readExact(input, 64);
          final hash = ascii.decode(hashBytes);
          if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
            throw const LocusArchiveException('Invalid blob hash in archive.');
          }
          final length = _readUint64(await _readExact(input, 8), 0);
          if (length < 0 || length > AttachmentRules.maxFileBytes) {
            throw const LocusArchiveException('Blob size is out of range.');
          }
          final bytes = await _readExact(input, length.toInt());
          if (sha256.convert(bytes).toString() != hash) {
            throw const LocusArchiveException(
              'An attachment failed its hash check.',
            );
          }
          if (seen.add(hash)) {
            if (!await attachments.store.hasBlob(hash)) {
              final stored = await attachments.store.putBytes(bytes);
              if (stored != hash) {
                throw const LocusArchiveException(
                  'An attachment could not be stored.',
                );
              }
              written++;
            }
            await db
                .into(db.attachmentBlobs)
                .insertOnConflictUpdate(
                  AttachmentBlobsCompanion.insert(
                    sha256: hash,
                    sizeBytes: length.toInt(),
                    state: const Value('present'),
                    hasThumb: const Value(false),
                    lastAccessedAt: Value(AppClock.now()),
                    orphanedAt: const Value(null),
                    failCount: const Value(0),
                  ),
                );
          }
        }
        if (await input.length() != await input.position()) {
          throw const LocusArchiveException(
            'The archive has unexpected trailing data.',
          );
        }
        final report = await DataExportService(
          db,
        ).restoreFromJson(jsonEncode(backup));
        final restoredRows = backup.values.whereType<List<dynamic>>().fold<int>(
          0,
          (sum, rows) => sum + rows.length,
        );
        return ArchiveRestoreReport(
          restoredRows: restoredRows,
          skippedRows: report.skippedRows,
          blobsWritten: written,
          missingHashes: [
            for (final value
                in (manifest['missing_hashes'] as List? ?? const []))
              if (value is String) value,
          ],
        );
      } finally {
        await input.close();
      }
    } finally {
      if (await plain.exists()) await plain.delete();
    }
  }

  Future<void> _sealFile(File plain, File target, String passphrase) async {
    final salt = KeyDerivation.randomBytes(16, _random);
    final nonceBase = KeyDerivation.randomBytes(8, _random);
    final length = await plain.length();
    if (length > maxPlainBytes) {
      throw const LocusArchiveException('The archive is too large.');
    }
    final header = BytesBuilder(copy: false)
      ..add(encryptedMagic)
      ..add(_uint32(version))
      ..add(_uint32(iterations))
      ..add(salt)
      ..add(nonceBase)
      ..add(_uint64(length));
    final headerBytes = header.takeBytes();
    final key = await KeyDerivation.derive(
      unorm.nfc(passphrase),
      salt,
      iterations,
    );

    final input = await plain.open();
    final output = await target.open(mode: FileMode.write);
    try {
      await output.writeFrom(headerBytes);
      var offset = 0;
      var counter = 0;
      if (length == 0) {
        await output.writeFrom(
          _sealChunk(key, Uint8List(0), nonceBase, counter, true, headerBytes),
        );
      }
      while (offset < length) {
        final size = min(chunkSize, length - offset);
        final chunk = await _readExact(input, size);
        final sealed = _sealChunk(
          key,
          chunk,
          nonceBase,
          counter,
          offset + size == length,
          headerBytes,
        );
        await output.writeFrom(sealed);
        offset += size;
        counter++;
      }
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<void> _openFile(File source, File target, String passphrase) async {
    final input = await source.open();
    final output = await target.open(mode: FileMode.write);
    try {
      final header = await _readExact(input, _headerLength);
      if (!_bytesEqual(
        header.sublist(0, encryptedMagic.length),
        encryptedMagic,
      )) {
        throw const LocusArchiveException('This is not a Locus archive.');
      }
      var cursor = encryptedMagic.length;
      final fileVersion = _readUint32(header, cursor);
      cursor += 4;
      if (fileVersion != version) {
        throw const LocusArchiveException('Unsupported archive version.');
      }
      final fileIterations = _readUint32(header, cursor);
      cursor += 4;
      if (!KeyDerivation.iterationsInRange(fileIterations)) {
        throw const LocusArchiveException('Unsupported archive settings.');
      }
      final salt = header.sublist(cursor, cursor + 16);
      cursor += 16;
      final nonceBase = header.sublist(cursor, cursor + 8);
      cursor += 8;
      final length = _readUint64(header, cursor);
      if (length < 0 || length > maxPlainBytes) {
        throw const LocusArchiveException('The archive length is invalid.');
      }
      final key = await KeyDerivation.derive(
        unorm.nfc(passphrase),
        salt,
        fileIterations,
      );
      var offset = 0;
      var counter = 0;
      if (length == 0) {
        final chunk = await _readExact(input, _tagLength);
        await output.writeFrom(
          _openChunk(key, chunk, nonceBase, counter, true, header),
        );
      }
      while (offset < length) {
        final size = min(chunkSize, length - offset);
        final chunk = await _readExact(input, size + _tagLength);
        final plain = _openChunk(
          key,
          chunk,
          nonceBase,
          counter,
          offset + size == length,
          header,
        );
        await output.writeFrom(plain);
        offset += size;
        counter++;
      }
      if (await input.length() != await input.position()) {
        throw const LocusArchiveException(
          'The archive has unexpected trailing data.',
        );
      }
    } on InvalidCipherTextException {
      throw const LocusArchiveException(
        'The passphrase is wrong, or the archive is damaged.',
      );
    } finally {
      await input.close();
      await output.close();
    }
  }

  static Uint8List _sealChunk(
    Uint8List key,
    Uint8List plaintext,
    Uint8List nonceBase,
    int counter,
    bool finalChunk,
    Uint8List header,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          _nonce(nonceBase, counter),
          _aad(header, counter, finalChunk),
        ),
      );
    return cipher.process(plaintext);
  }

  static Uint8List _openChunk(
    Uint8List key,
    Uint8List ciphertext,
    Uint8List nonceBase,
    int counter,
    bool finalChunk,
    Uint8List header,
  ) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          _nonce(nonceBase, counter),
          _aad(header, counter, finalChunk),
        ),
      );
    return cipher.process(ciphertext);
  }

  static Uint8List _nonce(Uint8List base, int counter) => Uint8List(12)
    ..setRange(0, 8, base)
    ..setRange(8, 12, _uint32(counter));

  static Uint8List _aad(Uint8List header, int counter, bool finalChunk) {
    final builder = BytesBuilder(copy: false)
      ..add(header)
      ..add(_uint32(counter))
      ..addByte(finalChunk ? 1 : 0);
    return builder.takeBytes();
  }

  static Future<Uint8List> _readExact(RandomAccessFile file, int length) async {
    final result = Uint8List(length);
    var read = 0;
    while (read < length) {
      final chunk = await file.read(length - read);
      if (chunk.isEmpty) {
        throw const LocusArchiveException('The archive is truncated.');
      }
      result.setRange(read, read + chunk.length, chunk);
      read += chunk.length;
    }
    return result;
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var index = 0; index < a.length; index++) {
      difference |= a[index] ^ b[index];
    }
    return difference == 0;
  }

  static Uint8List _uint32(int value) => Uint8List(4)
    ..[0] = (value >> 24) & 0xFF
    ..[1] = (value >> 16) & 0xFF
    ..[2] = (value >> 8) & 0xFF
    ..[3] = value & 0xFF;

  static Uint8List _uint64(int value) {
    final bytes = Uint8List(8);
    var remaining = value;
    for (var index = 7; index >= 0; index--) {
      bytes[index] = remaining & 0xFF;
      remaining >>= 8;
    }
    return bytes;
  }

  static int _readUint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static int _readUint64(List<int> bytes, int offset) {
    var value = 0;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | bytes[offset + index];
    }
    return value;
  }
}
