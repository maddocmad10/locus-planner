import 'dart:typed_data';

import '../services/crypto/key_derivation.dart';
import '../utils/app_clock.dart';
import 'database_key_store.dart';

/// A DEK together with the identifiers needed to persist it.
class DatabaseKey {
  const DatabaseKey({
    required this.keyId,
    required this.generation,
    required this.bytes,
  });

  final String keyId;
  final int generation;
  final Uint8List bytes;

  String get hex =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  DatabaseKeyRecord toRecord({
    required String databaseId,
    required String cipherProfileId,
    required DateTime createdAt,
    bool active = true,
  }) => DatabaseKeyRecord(
    keyId: keyId,
    generation: generation,
    databaseId: databaseId,
    cipherProfileId: cipherProfileId,
    bytes: bytes,
    createdAt: createdAt,
    active: active,
  );
}

/// Creates and resolves versioned DEKs.
///
/// A key is never regenerated for an existing file.  Callers must first prove
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
    final key = DatabaseKey(
      keyId: keyId,
      generation: generation,
      bytes: KeyDerivation.randomBytes(32),
    );
    await store.write(
      key.toRecord(
        databaseId: databaseId,
        cipherProfileId: cipherProfileId,
        createdAt: createdAt ?? AppClock.now().toUtc(),
      ),
    );
    await store.markActive(keyId);
    return key;
  }

  Future<DatabaseKey?> load(String keyId) async {
    final record = await store.read(keyId);
    if (record == null) return null;
    return DatabaseKey(
      keyId: record.keyId,
      generation: record.generation,
      bytes: record.bytes,
    );
  }

  Future<void> retire(String keyId) => store.delete(keyId);

  Future<void> activate(String keyId) => store.markActive(keyId);
}
