import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'atomic_file.dart';
import 'database_security_errors.dart';
import 'windows_dpapi_store.dart';

/// One versioned key slot.
///
/// The record contains the 32-byte DEK, but its [toJson] output is only ever
/// handed to the platform secure store.  It must never be logged or written to
/// a plain file.
class DatabaseKeyRecord {
  const DatabaseKeyRecord({
    required this.keyId,
    required this.generation,
    required this.databaseId,
    required this.cipherProfileId,
    required this.bytes,
    required this.createdAt,
    this.active = false,
  });

  final String keyId;
  final int generation;
  final String databaseId;
  final String cipherProfileId;
  final Uint8List bytes;
  final DateTime createdAt;
  final bool active;

  String get hex =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

  DatabaseKeyRecord copyWith({bool? active}) => DatabaseKeyRecord(
    keyId: keyId,
    generation: generation,
    databaseId: databaseId,
    cipherProfileId: cipherProfileId,
    bytes: bytes,
    createdAt: createdAt,
    active: active ?? this.active,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'keyId': keyId,
    'generation': generation,
    'databaseId': databaseId,
    'cipherProfileId': cipherProfileId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'active': active,
    'key': base64Encode(bytes),
  };

  static DatabaseKeyRecord decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key must be a JSON object.',
      );
    }
    final keyId = decoded['keyId'];
    final generation = decoded['generation'];
    final databaseId = decoded['databaseId'];
    final cipherProfileId = decoded['cipherProfileId'];
    final createdAt = decoded['createdAt'];
    final rawKey = decoded['key'];
    if (keyId is! String ||
        generation is! int ||
        databaseId is! String ||
        cipherProfileId is! String ||
        createdAt is! String ||
        rawKey is! String) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key is incomplete.',
      );
    }
    final Uint8List bytes;
    try {
      bytes = base64Decode(rawKey);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key is not valid base64.',
        cause: error,
      );
    }
    if (bytes.length != 32) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key has the wrong length.',
      );
    }
    final created = DateTime.tryParse(createdAt);
    if (created == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'A stored database key has an invalid creation time.',
      );
    }
    return DatabaseKeyRecord(
      keyId: keyId,
      generation: generation,
      databaseId: databaseId,
      cipherProfileId: cipherProfileId,
      bytes: bytes,
      createdAt: created,
      active: decoded['active'] == true,
    );
  }
}

/// Versioned, non-overwriting key storage.
///
/// A decryption or parse error is surfaced as
/// [DatabaseSecurityErrorCode.keyStoreCorrupt]; implementations must not delete
/// the evidence.
abstract interface class DatabaseKeyStore {
  Future<List<DatabaseKeyRecord>> listVersions();
  Future<DatabaseKeyRecord?> read(String keyId);
  Future<void> write(DatabaseKeyRecord record);
  Future<void> delete(String keyId);
  Future<void> markActive(String keyId);
}

/// Stores each key slot as its own item in the platform credential store.
class SecureDatabaseKeyStore implements DatabaseKeyStore {
  SecureDatabaseKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'locus.db.dek.v1';
  static const _indexKey = '$_prefix.index';

  final FlutterSecureStorage _storage;

  String _recordKey(String keyId) => '$_prefix.$keyId';

  Future<List<String>> _index() async {
    try {
      final raw = await _storage.read(key: _indexKey);
      if (raw == null || raw.isEmpty) return <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.keyStoreCorrupt,
          'The database key index is malformed.',
        );
      }
      return decoded.whereType<String>().toList(growable: true);
    } on DatabaseSecurityException {
      rethrow;
    } catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The database key index could not be read.',
        cause: error,
      );
    }
  }

  Future<void> _writeIndex(List<String> keyIds) async {
    await _storage.write(key: _indexKey, value: jsonEncode(keyIds));
  }

  @override
  Future<List<DatabaseKeyRecord>> listVersions() async {
    final records = <DatabaseKeyRecord>[];
    for (final keyId in await _index()) {
      final record = await read(keyId);
      if (record != null) records.add(record);
    }
    records.sort((a, b) => a.generation.compareTo(b.generation));
    return records;
  }

  @override
  Future<DatabaseKeyRecord?> read(String keyId) async {
    final String? raw;
    try {
      raw = await _storage.read(key: _recordKey(keyId));
    } catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The database key slot $keyId could not be read.',
        cause: error,
      );
    }
    if (raw == null || raw.isEmpty) return null;
    return DatabaseKeyRecord.decode(raw);
  }

  @override
  Future<void> write(DatabaseKeyRecord record) async {
    await _storage.write(
      key: _recordKey(record.keyId),
      value: jsonEncode(record.toJson()),
    );
    final index = await _index();
    if (!index.contains(record.keyId)) {
      index.add(record.keyId);
      await _writeIndex(index);
    }
    // Read-back verification: never report a stored key that cannot be read.
    final stored = await read(record.keyId);
    if (stored == null || stored.hex != record.hex) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The database key slot did not survive a verification read.',
      );
    }
  }

  @override
  Future<void> delete(String keyId) async {
    await _storage.delete(key: _recordKey(keyId));
    final index = await _index();
    index.remove(keyId);
    await _writeIndex(index);
  }

  @override
  Future<void> markActive(String keyId) async {
    for (final record in await listVersions()) {
      final active = record.keyId == keyId;
      if (record.active == active) continue;
      await _storage.write(
        key: _recordKey(record.keyId),
        value: jsonEncode(record.copyWith(active: active).toJson()),
      );
    }
  }
}

/// Windows implementation that writes a DPAPI-protected blob under
/// `%LOCALAPPDATA%`, which does not roam and is never auto-deleted.
class WindowsDpapiDatabaseKeyStore implements DatabaseKeyStore {
  WindowsDpapiDatabaseKeyStore({required this.file});

  final File file;

  /// The previous committed key store, preserved before every replacement.
  ///
  /// This is a recovery aid, not a second active store: normal reads never
  /// silently fall back to it.
  File get previousFile => File('${file.path}.previous');

  Future<Map<String, DatabaseKeyRecord>> _load([File? source]) async {
    final target = source ?? file;
    if (!await target.exists()) return <String, DatabaseKeyRecord>{};
    try {
      final plaintext = WindowsDpapiStore.unprotect(await target.readAsBytes());
      final decoded = jsonDecode(plaintext);
      if (decoded is! Map<String, dynamic>) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.keyStoreCorrupt,
          'The Windows key store must contain a JSON object.',
        );
      }
      final records = <String, DatabaseKeyRecord>{};
      for (final entry in decoded.entries) {
        if (entry.value is! String) continue;
        records[entry.key] = DatabaseKeyRecord.decode(entry.value as String);
      }
      return records;
    } on DatabaseSecurityException {
      rethrow;
    } catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The Windows key store could not be decrypted. The file was preserved.',
        cause: error,
      );
    }
  }

  Future<void> _save(Map<String, DatabaseKeyRecord> records) async {
    final plaintext = jsonEncode(<String, String>{
      for (final entry in records.entries)
        entry.key: jsonEncode(entry.value.toJson()),
    });
    // Preserve the last committed generation before replacing the live blob.
    // If the process dies inside the replacement, the previous file remains a
    // deterministic, checksum-verified recovery point.
    if (await file.exists()) {
      try {
        await AtomicFile.copyAndVerify(file, previousFile);
      } on FileSystemException {
        // Keep going: the live file is still intact and the new write is
        // verified before it becomes visible.
      }
    }
    await AtomicFile.writeBytes(file, WindowsDpapiStore.protect(plaintext));
  }

  @override
  Future<List<DatabaseKeyRecord>> listVersions() async {
    final records = (await _load()).values.toList();
    records.sort((a, b) => a.generation.compareTo(b.generation));
    return records;
  }

  /// Reads the preserved previous generation without using it as the active
  /// key store. Recovery UI uses this to offer an explicit rollback.
  Future<List<DatabaseKeyRecord>> listPreviousVersions() async {
    final records = (await _load(previousFile)).values.toList();
    records.sort((a, b) => a.generation.compareTo(b.generation));
    return records;
  }

  @override
  Future<DatabaseKeyRecord?> read(String keyId) async => (await _load())[keyId];

  @override
  Future<void> write(DatabaseKeyRecord record) async {
    final records = await _load();
    records[record.keyId] = record;
    await _save(records);
    final stored = await read(record.keyId);
    if (stored == null || stored.hex != record.hex) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'The Windows key slot did not survive a verification read.',
      );
    }
  }

  @override
  Future<void> delete(String keyId) async {
    final records = await _load();
    records.remove(keyId);
    await _save(records);
  }

  @override
  Future<void> markActive(String keyId) async {
    final records = await _load();
    for (final entry in records.entries.toList()) {
      records[entry.key] = entry.value.copyWith(active: entry.key == keyId);
    }
    await _save(records);
  }
}

/// In-memory store for tests.
class InMemoryDatabaseKeyStore implements DatabaseKeyStore {
  final Map<String, DatabaseKeyRecord> _records = <String, DatabaseKeyRecord>{};

  bool failReads = false;
  bool failWrites = false;
  int writeCount = 0;

  @override
  Future<List<DatabaseKeyRecord>> listVersions() async {
    if (failReads) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'Test key store read failure.',
      );
    }
    final records = _records.values.toList();
    records.sort((a, b) => a.generation.compareTo(b.generation));
    return records;
  }

  @override
  Future<DatabaseKeyRecord?> read(String keyId) async {
    if (failReads) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'Test key store read failure.',
      );
    }
    return _records[keyId];
  }

  @override
  Future<void> write(DatabaseKeyRecord record) async {
    if (failWrites) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.keyStoreCorrupt,
        'Test key store write failure.',
      );
    }
    writeCount++;
    _records[record.keyId] = record;
  }

  @override
  Future<void> delete(String keyId) async {
    _records.remove(keyId);
  }

  @override
  Future<void> markActive(String keyId) async {
    for (final entry in _records.entries.toList()) {
      _records[entry.key] = entry.value.copyWith(active: entry.key == keyId);
    }
  }
}

/// Selects a non-roaming, non-deleting key store on Windows.
///
/// Android uses Keystore-backed `flutter_secure_storage`; its shared-prefs file
/// is excluded from OS backup by the Android rules.
DatabaseKeyStore createDefaultDatabaseKeyStore() {
  if (Platform.isWindows) {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    final base = (localAppData == null || localAppData.isEmpty)
        ? Directory.current.path
        : localAppData;
    return WindowsDpapiDatabaseKeyStore(
      file: File(
        '$base${Platform.pathSeparator}LocusPlanner'
        '${Platform.pathSeparator}keys'
        '${Platform.pathSeparator}database_keys.dat',
      ),
    );
  }
  return SecureDatabaseKeyStore();
}
