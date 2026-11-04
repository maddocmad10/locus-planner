import 'dart:typed_data';

import '../services/crypto/key_derivation.dart';
import '../utils/app_clock.dart';
import 'database_key_store.dart';
import 'database_security_errors.dart';

/// A DEK together with the complete identity it belongs to.
///
/// Callers must validate every field against the external metadata before the
/// key is used. A DEK on its own is not a statement about which database it may
/// open.
class DatabaseKey {
  const DatabaseKey({
    required this.databaseId,
    required this.keyId,
    required this.generation,
    required this.cipherProfileId,
    required this.bytes,
    required this.createdAt,
    this.active = true,
  });

  final String databaseId;
  final String keyId;
  final int generation;
  final String cipherProfileId;
  final Uint8List bytes;
  final DateTime createdAt;
  final bool active;

  String get hex =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  factory DatabaseKey.fromRecord(DatabaseKeyRecord record) => DatabaseKey(
    databaseId: record.databaseId,
    keyId: record.keyId,
    generation: record.generation,
    cipherProfileId: record.cipherProfileId,
    bytes: record.bytes,
    createdAt: record.createdAt,
    active: record.active,
  );

  DatabaseKeyRecord toRecord({
    required String databaseId,
    required String cipherProfileId,
    required DateTime createdAt,
    bool active = true,
  }) => DatabaseKeyRecord(
    databaseId: databaseId,
    keyId: keyId,
    generation: generation,
    cipherProfileId: cipherProfileId,
    bytes: bytes,
    createdAt: createdAt,
    active: active,
  );

  /// Rejects a key record that belongs to another database, generation or
  /// cipher profile.
  void requireMatches({
    required String databaseId,
    required String keyId,
    required int generation,
    required String cipherProfileId,
  }) {
    if (bytes.length != 32) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The database key has the wrong length.',
      );
    }
    if (this.databaseId != databaseId ||
        this.keyId != keyId ||
        this.generation != generation ||
        this.cipherProfileId != cipherProfileId) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'The key record does not match the database identity metadata.',
      );
    }
  }
}

/// Creates and resolves versioned DEKs.
///
/// A key is never regenerated for an existing file. Callers must first prove
/// that no database identity exists.
class DatabaseKeyService {
  DatabaseKeyService(this.store);

  final DatabaseKeyStore store;

  static String keyIdForGeneration(int generation) =>
      'key-${generation.toString().padLeft(4, '0')}';

  Future<DatabaseKey> createFresh({
    required String databaseId,
    required String cipherProfileId,
    DateTime? createdAt,
    bool activate = true,
  }) async {
    final existing = await store.listVersions();
    final usedGens = existing.map((record) => record.generation).toSet();
    var generation = existing.isEmpty
        ? 1
        : existing
                  .map((record) => record.generation)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    while (usedGens.contains(generation)) {
      generation++;
    }
    final keyId = keyIdForGeneration(generation);
    final created = createdAt ?? AppClock.now().toUtc();
    final key = DatabaseKey(
      databaseId: databaseId,
      keyId: keyId,
      generation: generation,
      cipherProfileId: cipherProfileId,
      bytes: KeyDerivation.randomBytes(32),
      createdAt: created,
    );
    await store.write(
      key.toRecord(
        databaseId: databaseId,
        cipherProfileId: cipherProfileId,
        createdAt: created,
      ),
    );
    if (activate) await store.markActive(keyId);
    return key;
  }

  Future<DatabaseKey?> load(String keyId) async {
    final record = await store.read(keyId);
    if (record == null) return null;
    return DatabaseKey.fromRecord(record);
  }

  /// Loads [keyId] and validates it against the database identity metadata.
  Future<DatabaseKey> requireValid({
    required String keyId,
    required String databaseId,
    required int generation,
    required String cipherProfileId,
  }) async {
    final key = await load(keyId);
    if (key == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyMissing,
        'The database key is unavailable. Restore it from a recovery bundle.',
      );
    }
    key.requireMatches(
      databaseId: databaseId,
      keyId: keyId,
      generation: generation,
      cipherProfileId: cipherProfileId,
    );
    return key;
  }

  /// More than one active slot is ambiguous and must not be resolved by
  /// guessing: the user has to choose a recovery path.
  Future<void> requireSingleActiveKey() async {
    final active = (await store.listVersions())
        .where((record) => record.active)
        .toList();
    if (active.length > 1) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'The key store contains ${active.length} active keys; exactly one is '
        'required.',
      );
    }
  }

  Future<void> retire(String keyId) => store.delete(keyId);

  Future<void> activate(String keyId) => store.markActive(keyId);
}
