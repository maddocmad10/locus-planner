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
    this.updatedAt,
    this.formatVersion = currentFormatVersion,
  });

  static const currentFormatVersion = 3;
  static const tableName = 'db_security_identity';

  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int formatVersion;

  DateTime get lastUpdated => updatedAt ?? createdAt;

  DatabaseIdentity copyWith({
    String? keyId,
    int? keyGeneration,
    DateTime? updatedAt,
  }) => DatabaseIdentity(
    databaseId: databaseId,
    keyId: keyId ?? this.keyId,
    keyGeneration: keyGeneration ?? this.keyGeneration,
    cipherProfileId: cipherProfileId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
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
    'updated_at': lastUpdated.toUtc().toIso8601String(),
  };

  static DatabaseIdentity fromRow(
    sqlite3.Row row, {
    bool hasUpdatedAt = true,
  }) => DatabaseIdentity(
    databaseId: row['database_id'] as String,
    keyId: row['key_id'] as String,
    keyGeneration: row['key_generation'] as int,
    cipherProfileId: row['cipher_profile_id'] as String,
    formatVersion: row['format_version'] as int,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: hasUpdatedAt && row['updated_at'] is String
        ? DateTime.tryParse(row['updated_at'] as String)
        : null,
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
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''';

  static const select =
      '''
    SELECT database_id, key_id, key_generation, cipher_profile_id,
           format_version, created_at, updated_at
    FROM ${DatabaseIdentity.tableName}
    WHERE id = 1
  ''';

  /// Format-2 identity tables predate `updated_at` and must stay readable.
  static const legacySelect =
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
       format_version, created_at, updated_at)
    VALUES (1, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      database_id = excluded.database_id,
      key_id = excluded.key_id,
      key_generation = excluded.key_generation,
      cipher_profile_id = excluded.cipher_profile_id,
      format_version = excluded.format_version,
      created_at = excluded.created_at,
      updated_at = excluded.updated_at
  ''';
}

/// Raw-SQLite access used by the connection factory and migration code.
abstract final class DatabaseIdentityStore {
  static void ensureTable(sqlite3.Database db) {
    db.execute(DatabaseIdentitySql.createTable);
    if (!_hasUpdatedAt(db)) {
      db.execute(
        'ALTER TABLE ${DatabaseIdentity.tableName} '
        'ADD COLUMN updated_at TEXT',
      );
      db.execute(
        'UPDATE ${DatabaseIdentity.tableName} '
        'SET updated_at = created_at WHERE updated_at IS NULL',
      );
    }
  }

  static DatabaseIdentity? read(sqlite3.Database db) {
    final exists = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[DatabaseIdentity.tableName],
    );
    if (exists.isEmpty) return null;
    final hasUpdatedAt = _hasUpdatedAt(db);
    final rows = db.select(
      hasUpdatedAt
          ? DatabaseIdentitySql.select
          : DatabaseIdentitySql.legacySelect,
    );
    if (rows.isEmpty) return null;
    return DatabaseIdentity.fromRow(rows.first, hasUpdatedAt: hasUpdatedAt);
  }

  static bool _hasUpdatedAt(sqlite3.Database db) {
    final columns = db.select(
      'PRAGMA table_info(${DatabaseIdentity.tableName})',
    );
    return columns.any((row) => row['name'] == 'updated_at');
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
      row['updated_at'],
    ]);
  }
}
