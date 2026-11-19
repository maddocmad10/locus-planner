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
///
/// The staged slot exists only while a raw recovery package is waiting for the
/// next restart. It is kept in the same OS-protected store and never written to
/// the database or a plain file.
abstract interface class AttachmentKeyStore {
  Future<Uint8List> loadOrCreate();

  /// Returns the current key without creating one.
  Future<Uint8List?> read();

  /// Replaces the active key. Callers must be replacing the matching blobs.
  Future<void> write(Uint8List key);

  Future<void> writeStaged(Uint8List key);
  Future<Uint8List?> readStaged();
  Future<void> clearStaged();

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
  static const stagedStorageKey = 'locus.attachments.key.staged.v1';

  static const keyLength = 32;

  final FlutterSecureStorage _storage;
  final Random _random;

  @override
  Future<Uint8List> loadOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;

    final bytes = _randomKey();
    await write(bytes);
    return bytes;
  }

  @override
  Future<Uint8List?> read() => _readSlot(storageKey);

  @override
  Future<void> write(Uint8List key) async {
    _requireKey(key);
    await _storage.write(key: storageKey, value: base64Encode(key));
  }

  @override
  Future<void> writeStaged(Uint8List key) async {
    _requireKey(key);
    await _storage.write(key: stagedStorageKey, value: base64Encode(key));
  }

  @override
  Future<Uint8List?> readStaged() => _readSlot(stagedStorageKey);

  @override
  Future<void> clearStaged() => _storage.delete(key: stagedStorageKey);

  @override
  Future<void> delete() => _storage.delete(key: storageKey);

  Future<Uint8List?> _readSlot(String slot) async {
    final existing = await _storage.read(key: slot);
    if (existing == null) return null;
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

  Uint8List _randomKey() {
    final bytes = Uint8List(keyLength);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = _random.nextInt(256);
    }
    return bytes;
  }

  static void _requireKey(Uint8List key) {
    if (key.length != keyLength) {
      throw const AttachmentKeyException('An attachment key must be 32 bytes.');
    }
  }
}

/// Test double that follows the same staged-key rules as the secure store.
class InMemoryAttachmentKeyStore implements AttachmentKeyStore {
  Uint8List? value;
  Uint8List? staged;

  @override
  Future<Uint8List> loadOrCreate() async {
    value ??= Uint8List.fromList(List<int>.generate(32, (index) => index));
    return value!;
  }

  @override
  Future<Uint8List?> read() async => value;

  @override
  Future<void> write(Uint8List key) async => value = Uint8List.fromList(key);

  @override
  Future<void> writeStaged(Uint8List key) async =>
      staged = Uint8List.fromList(key);

  @override
  Future<Uint8List?> readStaged() async => staged;

  @override
  Future<void> clearStaged() async => staged = null;

  @override
  Future<void> delete() async => value = null;
}
