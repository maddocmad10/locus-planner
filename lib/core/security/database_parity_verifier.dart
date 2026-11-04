import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'database_security_errors.dart';
import 'database_identity.dart';

/// Result of a source-to-destination database comparison.
class DatabaseParityReport {
  const DatabaseParityReport({
    required this.sourceSchemaVersion,
    required this.targetSchemaVersion,
    required this.tableCount,
    required this.rowCount,
    required this.mismatches,
  });

  final int sourceSchemaVersion;
  final int targetSchemaVersion;
  final int tableCount;
  final int rowCount;
  final List<String> mismatches;

  bool get matches => mismatches.isEmpty;

  void requireParity() {
    if (matches) return;
    throw DatabaseSecurityException(
      DatabaseSecurityErrorCode.databaseDamaged,
      'The converted database did not match its source: '
      '${mismatches.take(5).join('; ')}',
    );
  }
}

/// Full structural and row-content comparison.
///
/// `PRAGMA integrity_check` only proves that SQLite can read its own pages. It
/// cannot prove that a conversion copied every table, column, index, foreign
/// key, row, tombstone or version value. This verifier compares:
///
/// * table, index, trigger and view definitions;
/// * column and foreign-key definitions;
/// * row counts and canonical row checksums for every application table.
abstract final class DatabaseParityVerifier {
  static const defaultExcludedTables = <String>{DatabaseIdentity.tableName};

  static DatabaseParityReport compare({
    required sqlite3.Database source,
    required sqlite3.Database target,
    Set<String> excludedTables = defaultExcludedTables,
  }) {
    final mismatches = <String>[];
    final sourceVersion = _userVersion(source);
    final targetVersion = _userVersion(target);
    if (sourceVersion != targetVersion) {
      mismatches.add('user_version $sourceVersion != $targetVersion');
    }

    final sourceSchema = _schemaObjects(source, excludedTables);
    final targetSchema = _schemaObjects(target, excludedTables);
    if (sourceSchema.length != targetSchema.length) {
      mismatches.add(
        'schema object count ${sourceSchema.length} != '
        '${targetSchema.length}',
      );
    }
    for (final entry in sourceSchema.entries) {
      final other = targetSchema[entry.key];
      if (other == null) {
        mismatches.add('missing schema object ${entry.key}');
      } else if (entry.value != other) {
        mismatches.add('schema definition differs: ${entry.key}');
      }
    }
    for (final key in targetSchema.keys) {
      if (!sourceSchema.containsKey(key)) {
        mismatches.add('extra schema object $key');
      }
    }

    final sourceTables = _applicationTables(source, excludedTables);
    final targetTables = _applicationTables(target, excludedTables);
    if (sourceTables.length != targetTables.length ||
        !sourceTables.every(targetTables.contains)) {
      mismatches.add(
        'table list differs: ${sourceTables.join(',')} != '
        '${targetTables.join(',')}',
      );
    }

    var totalRows = 0;
    for (final table in sourceTables) {
      if (!targetTables.contains(table)) continue;
      final sourceColumns = _columns(source, table);
      final targetColumns = _columns(target, table);
      if (!_sameList(sourceColumns, targetColumns)) {
        mismatches.add('columns differ for $table');
      }

      final sourceForeignKeys = _foreignKeys(source, table);
      final targetForeignKeys = _foreignKeys(target, table);
      if (!_sameList(sourceForeignKeys, targetForeignKeys)) {
        mismatches.add('foreign keys differ for $table');
      }

      final sourceCount = _rowCount(source, table);
      final targetCount = _rowCount(target, table);
      totalRows += sourceCount;
      if (sourceCount != targetCount) {
        mismatches.add('row count for $table: $sourceCount != $targetCount');
        continue;
      }
      final sourceChecksum = _tableChecksum(source, table);
      final targetChecksum = _tableChecksum(target, table);
      if (sourceChecksum != targetChecksum) {
        mismatches.add('row checksum differs for $table');
      }
    }

    return DatabaseParityReport(
      sourceSchemaVersion: sourceVersion,
      targetSchemaVersion: targetVersion,
      tableCount: sourceTables.length,
      rowCount: totalRows,
      mismatches: mismatches,
    );
  }

  static void requireParity({
    required sqlite3.Database source,
    required sqlite3.Database target,
    Set<String> excludedTables = defaultExcludedTables,
  }) => compare(
    source: source,
    target: target,
    excludedTables: excludedTables,
  ).requireParity();

  /// Runs `integrity_check` and fails with a security exception instead of a
  /// bare StateError so callers have one recovery taxonomy.
  static void requireIntegrity(sqlite3.Database db) {
    final rows = db.select('PRAGMA integrity_check');
    if (rows.length != 1 || rows.first.values.first != 'ok') {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.databaseDamaged,
        'The database failed SQLite integrity_check.',
      );
    }
  }

  static int _userVersion(sqlite3.Database db) {
    final rows = db.select('PRAGMA user_version');
    return rows.isEmpty ? 0 : rows.first['user_version'] as int;
  }

  static Map<String, String> _schemaObjects(
    sqlite3.Database db,
    Set<String> excluded,
  ) {
    final rows = db.select(
      "SELECT type, name, tbl_name, sql FROM sqlite_master "
      "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
    );
    final objects = <String, String>{};
    for (final row in rows) {
      final name = row['name'] as String;
      final table = row['tbl_name'] as String? ?? name;
      if (excluded.contains(name) || excluded.contains(table)) continue;
      final sql = row['sql'] as String?;
      if (sql == null) continue;
      objects['${row['type']}:$name'] = _normalizeSql(sql);
    }
    return objects;
  }

  static List<String> _applicationTables(
    sqlite3.Database db,
    Set<String> excluded,
  ) {
    final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    return <String>[
      for (final row in rows)
        if (!excluded.contains(row['name'] as String)) row['name'] as String,
    ];
  }

  static List<String> _columns(sqlite3.Database db, String table) {
    final rows = db.select('PRAGMA table_info(${_quote(table)})');
    return <String>[
      for (final row in rows)
        '${row['name']}|${row['type']}|${row['notnull']}|'
            '${row['dflt_value']}|${row['pk']}',
    ];
  }

  static List<String> _foreignKeys(sqlite3.Database db, String table) {
    final rows = db.select('PRAGMA foreign_key_list(${_quote(table)})');
    return <String>[
      for (final row in rows)
        '${row['id']}|${row['seq']}|${row['table']}|${row['from']}|'
            '${row['to']}|${row['on_update']}|${row['on_delete']}|'
            '${row['match']}',
    ];
  }

  static int _rowCount(sqlite3.Database db, String table) {
    final rows = db.select('SELECT COUNT(*) AS count FROM ${_quote(table)}');
    return rows.isEmpty ? 0 : rows.first['count'] as int;
  }

  static String _tableChecksum(sqlite3.Database db, String table) {
    final createSql = _createSql(db, table);
    final withoutRowid =
        createSql != null && createSql.toUpperCase().contains('WITHOUT ROWID');
    final rows = db.select(
      'SELECT * FROM ${_quote(table)}'
      '${withoutRowid ? '' : ' ORDER BY rowid'}',
    );
    final columns = rows.columnNames.map((name) => name).toList()..sort();

    if (withoutRowid) {
      final lines = <String>[for (final row in rows) _rowLine(row, columns)]
        ..sort();
      return 'sha256:${crypto.sha256.convert(utf8.encode(lines.join('\u0002')))}';
    }

    final sink = AccumulatorSink<crypto.Digest>();
    final output = crypto.sha256.startChunkedConversion(sink);
    for (final row in rows) {
      output.add(utf8.encode(_rowLine(row, columns)));
      output.add(const <int>[2]);
    }
    output.close();
    return 'sha256:${sink.events.single}';
  }

  static String? _createSql(sqlite3.Database db, String table) {
    final rows = db.select(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      <Object?>[table],
    );
    return rows.isEmpty ? null : rows.first['sql'] as String?;
  }

  static String _rowLine(sqlite3.Row row, List<String> columns) {
    final buffer = StringBuffer();
    for (final column in columns) {
      buffer.write(_encodeValue(row[column]));
      buffer.write('\u0001');
    }
    return buffer.toString();
  }

  static bool _sameList(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  static String _encodeValue(Object? value) {
    if (value == null) return 'n';
    if (value is int) return 'i:$value';
    if (value is double) return 'd:${value.toStringAsPrecision(17)}';
    if (value is String) return 's:${value.length}:$value';
    if (value is Uint8List) return 'b:${hex.encode(value)}';
    if (value is List<int>) return 'b:${hex.encode(value)}';
    return 'x:$value';
  }

  static String _normalizeSql(String sql) =>
      sql.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';
}
