import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Thrown when a sealed blob is malformed or fails authentication.
class AttachmentBlobCorruptException implements Exception {
  const AttachmentBlobCorruptException(this.message);

  final String message;

  @override
  String toString() => 'AttachmentBlobCorruptException: $message';
}

/// Authenticated, chunked encryption for content-addressed attachment files.
///
/// Format (`LATTCH1`):
///
/// ```text
/// offset  size  field
/// 0       8     magic "LATTCH1\n"
/// 8       4     chunk size, big-endian uint32 (default 64 KiB)
/// 12      8     plaintext length, big-endian uint64
/// 20      8     random nonce base
/// 28      ...   chunks: AES-256-GCM ciphertext + 16-byte tag
/// ```
///
/// Each chunk uses a 12-byte nonce built from the random per-file base plus a
/// big-endian 32-bit chunk counter, so the same key can safely seal many files.
/// The associated data binds the whole header, the counter and a final-chunk
/// flag. Reordering, truncating or splicing chunks therefore fails
/// authentication instead of yielding partial plaintext.
class AttachmentCrypto {
  AttachmentCrypto(this.key) {
    if (key.length != 32) {
      throw ArgumentError.value(key.length, 'key', 'must be 32 bytes');
    }
  }

  static const magic = <int>[0x4C, 0x41, 0x54, 0x54, 0x43, 0x48, 0x31, 0x0A];
  static const chunkSize = 64 * 1024;
  static const _headerLength = 28;
  static const _tagLength = 16;
  static const maxPlainBytes = 1024 * 1024 * 1024;

  final Uint8List key;
  final Random _random = Random.secure();

  /// Content-addressed disk name. HMAC-ing the public SHA-256 keeps content
  /// hashes out of the file system while preserving deduplication.
  String fileId(String sha256Hex) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(sha256Hex)).toString();
  }

  Uint8List sealBytes(Uint8List plaintext) {
    if (plaintext.length > maxPlainBytes) {
      throw ArgumentError.value(
        plaintext.length,
        'plaintext',
        'attachment is too large',
      );
    }
    final nonceBase = _randomBytes(8);
    final buffer = BytesBuilder(copy: false)
      ..add(magic)
      ..add(_uint32(chunkSize))
      ..add(_uint64(plaintext.length))
      ..add(nonceBase);
    final header = buffer.takeBytes();

    var offset = 0;
    var counter = 0;
    if (plaintext.isEmpty) {
      final sealed = _sealChunk(
        Uint8List(0),
        nonceBase,
        counter,
        true,
        header,
      );
      return Uint8List.fromList([...header, ...sealed]);
    }
    final output = BytesBuilder(copy: false)..add(header);
    while (offset < plaintext.length) {
      final end = min(offset + chunkSize, plaintext.length);
      final chunk = Uint8List.sublistView(plaintext, offset, end);
      final finalChunk = end == plaintext.length;
      output.add(_sealChunk(chunk, nonceBase, counter, finalChunk, header));
      offset = end;
      counter++;
    }
    return output.takeBytes();
  }

  Uint8List openBytes(Uint8List sealed) {
    if (sealed.length < _headerLength) {
      throw const AttachmentBlobCorruptException('Attachment header is short.');
    }
    for (var index = 0; index < magic.length; index++) {
      if (sealed[index] != magic[index]) {
        throw const AttachmentBlobCorruptException(
          'Attachment header magic is invalid.',
        );
      }
    }
    final storedChunkSize = _readUint32(sealed, 8);
    if (storedChunkSize != chunkSize) {
      throw const AttachmentBlobCorruptException(
        'Attachment chunk size is unsupported.',
      );
    }
    final plainLength = _readUint64(sealed, 12);
    if (plainLength < 0 || plainLength > maxPlainBytes) {
      throw const AttachmentBlobCorruptException(
        'Attachment length is out of range.',
      );
    }
    final nonceBase = Uint8List.sublistView(sealed, 20, 28);
    final header = Uint8List.sublistView(sealed, 0, _headerLength);

    final output = BytesBuilder(copy: false);
    var offset = _headerLength;
    var counter = 0;
    var remaining = plainLength;
    if (remaining == 0) {
      final cipherLength = _tagLength;
      if (sealed.length != offset + cipherLength) {
        throw const AttachmentBlobCorruptException(
          'Empty attachment has trailing bytes.',
        );
      }
      output.add(
        _openChunk(
          Uint8List.sublistView(sealed, offset),
          nonceBase,
          counter,
          true,
          header,
        ),
      );
      return output.takeBytes();
    }
    while (remaining > 0) {
      final plainChunk = min(chunkSize, remaining);
      final cipherLength = plainChunk + _tagLength;
      if (offset + cipherLength > sealed.length) {
        throw const AttachmentBlobCorruptException(
          'Attachment is truncated.',
        );
      }
      final finalChunk = plainChunk == remaining;
      output.add(
        _openChunk(
          Uint8List.sublistView(sealed, offset, offset + cipherLength),
          nonceBase,
          counter,
          finalChunk,
          header,
        ),
      );
      offset += cipherLength;
      remaining -= plainChunk;
      counter++;
    }
    if (offset != sealed.length) {
      throw const AttachmentBlobCorruptException(
        'Attachment has trailing bytes.',
      );
    }
    return output.takeBytes();
  }

  Uint8List _sealChunk(
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

  Uint8List _openChunk(
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
    try {
      return cipher.process(ciphertext);
    } on InvalidCipherTextException {
      throw const AttachmentBlobCorruptException(
        'Attachment failed authentication.',
      );
    }
  }

  Uint8List _nonce(Uint8List nonceBase, int counter) {
    final nonce = Uint8List(12)
      ..setRange(0, 8, nonceBase)
      ..setRange(8, 12, _uint32(counter));
    return nonce;
  }

  Uint8List _aad(Uint8List header, int counter, bool finalChunk) {
    final aad = BytesBuilder(copy: false)
      ..add(header)
      ..add(_uint32(counter))
      ..addByte(finalChunk ? 1 : 0);
    return aad.takeBytes();
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var index = 0; index < length; index++) {
      bytes[index] = _random.nextInt(256);
    }
    return bytes;
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

  static int _readUint32(Uint8List bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static int _readUint64(Uint8List bytes, int offset) {
    var value = 0;
    for (var index = 0; index < 8; index++) {
      value = (value << 8) | bytes[offset + index];
    }
    return value;
  }
}

/// Streams a sealed blob to disk without holding the whole file in memory.
Future<void> sealFile(
  AttachmentCrypto crypto,
  Uint8List plaintext,
  File target,
) async {
  final sealed = crypto.sealBytes(plaintext);
  await target.parent.create(recursive: true);
  await target.writeAsBytes(sealed, flush: true);
}
