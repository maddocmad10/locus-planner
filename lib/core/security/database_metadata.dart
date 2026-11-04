import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';

/// Non-secret description of the database identity.
///
/// This file is an **untrusted hint**.  It must never contain the DEK or any
/// reversible representation of it.  The authoritative identity lives inside
/// the encrypted database (`db_security_identity`).
class DatabaseMetadata {
  const DatabaseMetadata({
    required this.databaseId,
    required this.activeKeyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    required this.encryptionEnabled,
    required this.databaseFile,
    required this.createdAt,
    this.lastOpenedAt,
  });

  static const formatVersion = 2;

  final String databaseId;
  final String activeKeyId;
  final int keyGeneration;
  final String cipherProfileId;
  final bool encryptionEnabled;
  final String databaseFile;
  final DateTime createdAt;
  final DateTime? lastOpenedAt;

  DatabaseMetadata copyWith({
    String? activeKeyId,
    int? keyGeneration,
    DateTime? lastOpenedAt,
  }) => DatabaseMetadata(
    databaseId: databaseId,
    activeKeyId: activeKeyId ?? this.activeKeyId,
    keyGeneration: keyGeneration ?? this.keyGeneration,
    cipherProfileId: cipherProfileId,
    encryptionEnabled: encryptionEnabled,
    databaseFile: databaseFile,
    createdAt: createdAt,
    lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'formatVersion': formatVersion,
    'databaseId': databaseId,
    'activeKeyId': activeKeyId,
    'keyGeneration': keyGeneration,
    'cipherProfileId': cipherProfileId,
    'encryptionEnabled': encryptionEnabled,
    'databaseFile': databaseFile,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastOpenedAt': lastOpenedAt?.toUtc().toIso8601String(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static DatabaseMetadata decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata must be a JSON object.',
      );
    }
    final version = decoded['formatVersion'];
    if (version is! int || version > formatVersion || version < 1) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Unsupported database metadata version: $version.',
      );
    }
    final databaseId = _requiredString(decoded, 'databaseId');
    final activeKeyId = _requiredString(decoded, 'activeKeyId');
    final cipherProfileId = _requiredString(decoded, 'cipherProfileId');
    final databaseFile = _requiredString(decoded, 'databaseFile');
    final keyGeneration = decoded['keyGeneration'];
    if (keyGeneration is! int || keyGeneration < 0) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata has an invalid key generation.',
      );
    }
    final createdAt = _requiredDate(decoded, 'createdAt');
    final lastOpened = decoded['lastOpenedAt'];
    return DatabaseMetadata(
      databaseId: databaseId,
      activeKeyId: activeKeyId,
      keyGeneration: keyGeneration,
      cipherProfileId: cipherProfileId,
      encryptionEnabled: decoded['encryptionEnabled'] == true,
      databaseFile: databaseFile,
      createdAt: createdAt,
      lastOpenedAt: lastOpened is String ? DateTime.tryParse(lastOpened) : null,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.trim().isEmpty) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata is missing "$key".',
      );
    }
    return value;
  }

  static DateTime _requiredDate(Map<String, dynamic> json, String key) {
    final value = json[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata has an invalid "$key".',
      );
    }
    return parsed;
  }
}

class DatabaseMetadataStore {
  DatabaseMetadataStore(this.file);

  final File file;

  Future<bool> get exists => file.exists();

  /// Returns `null` when the file is absent.
  ///
  /// Throws [DatabaseSecurityException] with
  /// [DatabaseSecurityErrorCode.metadataCorrupt] for an unreadable or
  /// unsupported file.  The caller must fail closed rather than assume the
  /// database is plaintext.
  Future<DatabaseMetadata?> read() async {
    if (!await file.exists()) return null;
    try {
      return DatabaseMetadata.decode(await file.readAsString());
    } on FileSystemException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Database metadata could not be read.',
        cause: error,
      );
    }
  }

  Future<void> write(DatabaseMetadata metadata) =>
      AtomicFile.writeString(file, metadata.encode());

  Future<void> touch({DateTime? at}) async {
    final current = await read();
    if (current == null) return;
    await write(current.copyWith(lastOpenedAt: at ?? AppClock.now()));
  }
}
