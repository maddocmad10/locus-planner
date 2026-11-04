import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'database_metadata.dart';
import 'database_security_errors.dart';

/// Authoritative identity record stored *inside* the encrypted database.
///
/// External metadata is only a hint; this row is the source of truth after the
/// database has been decrypted.
class DatabaseIdentity {
  const DatabaseIdentity({
    required this.databaseId,
    required this.keyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    required this.createdAt,
    this.formatVersion = currentFormatVersion,
  });

  static const currentFormatVersion = 2;
  static const tableName = 'db_security_identity';

  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final DateTime createdAt;
  final int formatVersion;

  DatabaseIdentity copyWith({String? keyId, int? keyGeneration}) =>
      DatabaseIdentity(
        databaseId: databaseId,
        keyId: keyId ?? this.keyId,
        keyGeneration: keyGeneration ?? this.keyGeneration,
        cipherProfileId: cipherProfileId,
        createdAt: createdAt,
        formatVersion: formatVersion,
      );

  /// Fails closed when the external hint disagrees with the encrypted anchor.
  void requireMatches(DatabaseMetadata metadata) {
    if (metadata.databaseId != databaseId ||
        metadata.activeKeyId != keyId ||
        metadata.keyGeneration != keyGeneration ||
        metadata.cipherProfileId != cipherProfileId) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.identityMismatch,
        'Database metadata does not match the encrypted identity anchor.',
      );
    }
  }

  Map<String, Object?> toRow() => <String, Object?>{
    'database_id': databaseId,
    'key_id': keyId,
    'key_generation': keyGeneration,
    'cipher_profile_id': cipherProfileId,
    'format_version': formatVersion,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  static DatabaseIdentity fromRow(sqlite3.Row row) => DatabaseIdentity(
    databaseId: row['database_id'] as String,
    keyId: row['key_id'] as String,
    keyGeneration: row['key_generation'] as int,
    cipherProfileId: row['cipher_profile_id'] as String,
    formatVersion: row['format_version'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

abstract final class DatabaseIdentitySql {
  static const createTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseIdentity.tableName} (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      database_id TEXT NOT NULL,
      key_id TEXT NOT NULL,
      key_generation INTEGER NOT NULL,
      cipher_profile_id TEXT NOT NULL,
      format_version INTEGER NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  static const select =
      '''
    SELECT database_id, key_id, key_generation, cipher_profile_id,
           format_version, created_at
    FROM ${DatabaseIdentity.tableName}
    WHERE id = 1
  ''';

  static const upsert =
      '''
    INSERT INTO ${DatabaseIdentity.tableName}
      (id, database_id, key_id, key_generation, cipher_profile_id,
       format_version, created_at)
    VALUES (1, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      database_id = excluded.database_id,
      key_id = excluded.key_id,
      key_generation = excluded.key_generation,
      cipher_profile_id = excluded.cipher_profile_id,
      format_version = excluded.format_version,
      created_at = excluded.created_at
  ''';
}

/// Raw-SQLite access used by the connection factory and migration code.
abstract final class DatabaseIdentityStore {
  static void ensureTable(sqlite3.Database db) {
    db.execute(DatabaseIdentitySql.createTable);
  }

  static DatabaseIdentity? read(sqlite3.Database db) {
    final exists = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[DatabaseIdentity.tableName],
    );
    if (exists.isEmpty) return null;
    final rows = db.select(DatabaseIdentitySql.select);
    if (rows.isEmpty) return null;
    return DatabaseIdentity.fromRow(rows.first);
  }

  static void write(sqlite3.Database db, DatabaseIdentity identity) {
    ensureTable(db);
    final row = identity.toRow();
    db.execute(DatabaseIdentitySql.upsert, <Object?>[
      row['database_id'],
      row['key_id'],
      row['key_generation'],
      row['cipher_profile_id'],
      row['format_version'],
      row['created_at'],
    ]);
  }
}
