import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thrown when the device-local attachment key is missing or malformed.
///
/// Attachment code fails closed: without a usable key it refuses to write or
/// read blobs rather than silently storing plaintext files.
class AttachmentKeyException implements Exception {
  const AttachmentKeyException(this.message);

  final String message;

  @override
  String toString() => 'AttachmentKeyException: $message';
}

/// Source of the device-local key used to encrypt attachment blobs.
///
/// This key is deliberately independent of the database encryption key. Blob
/// encryption must work while `LOCUS_DB_ENCRYPTION` is still off, and the two
/// concerns have different lifetimes: a database rotation does not need to
/// rewrite every attachment.
abstract interface class AttachmentKeyStore {
  Future<Uint8List> loadOrCreate();

  Future<void> delete();
}

/// Stores one 32-byte key in the platform secure store (DPAPI on Windows,
/// Keystore on Android).
class SecureAttachmentKeyStore implements AttachmentKeyStore {
  SecureAttachmentKeyStore({FlutterSecureStorage? storage, Random? random})
    : _storage = storage ?? const FlutterSecureStorage(),
      _random = random ?? Random.secure();

  /// Versioned slot. A future key rotation writes a new slot and re-encrypts
  /// blobs; the old slot must never be reused for different key material.
  static const storageKey = 'locus.attachments.key.v1';

  static const keyLength = 32;

  final FlutterSecureStorage _storage;
  final Random _random;

  @override
  Future<Uint8List> loadOrCreate() async {
    final existing = await _storage.read(key: storageKey);
    if (existing != null) {
      final Uint8List bytes;
      try {
        bytes = base64Decode(existing);
      } on FormatException {
        throw const AttachmentKeyException(
          'The stored attachment key is not valid base64.',
        );
      }
      if (bytes.length != keyLength) {
        throw const AttachmentKeyException(
          'The stored attachment key has the wrong length.',
        );
      }
      return bytes;
    }

    final bytes = Uint8List(keyLength);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = _random.nextInt(256);
    }
    await _storage.write(key: storageKey, value: base64Encode(bytes));
    return bytes;
  }

  @override
  Future<void> delete() => _storage.delete(key: storageKey);
}
