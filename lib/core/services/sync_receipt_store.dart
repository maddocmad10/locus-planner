import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

class SyncPeerProgress {
  const SyncPeerProgress({
    required this.peerId,
    required this.epoch,
    required this.direction,
    required this.cursor,
    required this.lastAttempt,
    required this.lastExchange,
    required this.lastClean,
    required this.errorCode,
  });

  final String peerId;
  final String epoch;
  final String direction;
  final int cursor;
  final DateTime? lastAttempt;
  final DateTime? lastExchange;
  final DateTime? lastClean;
  final String? errorCode;
}

class SyncRejectedRecord {
  const SyncRejectedRecord({
    required this.peerId,
    required this.epoch,
    required this.direction,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.reasonCode,
    required this.attempts,
    required this.firstSeen,
    required this.lastSeen,
    required this.resolved,
  });

  final String peerId;
  final String epoch;
  final String direction;
  final String changeId;
  final String entityType;
  final String entityId;
  final String operation;
  final String reasonCode;
  final int attempts;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool resolved;
}

/// Reads and repairs the durable sync progress/repair records. Payloads stay
/// inside the encrypted database; callers only receive counts and reason codes.
class SyncReceiptStore {
  SyncReceiptStore(this._db);

  final AppDatabase _db;

  Future<List<SyncPeerProgress>> progress() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_peer_progress '
          'ORDER BY last_exchange_ms DESC',
        )
        .get();
    return [for (final row in rows) _progressFromRow(row)];
  }

  Future<SyncPeerProgress?> latestClean() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_peer_progress '
          'WHERE last_clean_ms IS NOT NULL '
          'ORDER BY last_clean_ms DESC LIMIT 1',
        )
        .get();
    return rows.isEmpty ? null : _progressFromRow(rows.first);
  }

  Future<int> openRejectionCount() async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM sync_rejected_changes '
          'WHERE resolved_ms IS NULL',
        )
        .get();
    return rows.first.read<int>('count');
  }

  Future<List<SyncRejectedRecord>> openRejections({int limit = 50}) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_rejected_changes '
          'WHERE resolved_ms IS NULL ORDER BY last_seen_ms DESC LIMIT ?',
          variables: [Variable.withInt(limit)],
        )
        .get();
    return [for (final row in rows) _rejectedFromRow(row)];
  }

  /// Explicitly discards one repair. This is the only local operation that
  /// resolves a rejected item without a successful retry.
  Future<void> discard({
    required String peerId,
    required String epoch,
    required String direction,
    required String changeId,
  }) async {
    await _db.customStatement(
      'UPDATE sync_rejected_changes SET resolved_ms = ? '
      'WHERE peer_id = ? AND epoch = ? AND direction = ? AND change_id = ?',
      [
        AppClock.now().millisecondsSinceEpoch,
        peerId,
        epoch,
        direction,
        changeId,
      ],
    );
  }

  /// Records a peer exchange attempt. A missing [clean] value intentionally
  /// leaves the previous clean time untouched instead of inventing one.
  Future<void> noteExchange({
    required String peerId,
    required String epoch,
    required String direction,
    required int cursor,
    bool clean = false,
    String? errorCode,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'INSERT INTO sync_peer_progress '
      '(peer_id, epoch, direction, cursor, last_attempt_ms, '
      'last_exchange_ms, last_clean_ms, error_code) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(peer_id, epoch, direction) DO UPDATE SET '
      'cursor = MAX(sync_peer_progress.cursor, excluded.cursor), '
      'last_attempt_ms = excluded.last_attempt_ms, '
      'last_exchange_ms = excluded.last_exchange_ms, '
      'last_clean_ms = CASE WHEN excluded.last_clean_ms IS NOT NULL '
      'THEN excluded.last_clean_ms ELSE sync_peer_progress.last_clean_ms END, '
      'error_code = excluded.error_code',
      [
        peerId,
        epoch,
        direction,
        cursor,
        now,
        now,
        clean ? now : null,
        errorCode,
      ],
    );
  }

  /// Migrates the pre-25 preference cursors into SQLite. Provenance that is
  /// missing stays unknown: no clean sync time is guessed.
  Future<void> recoverLegacyCursors({
    required String peerId,
    required String epoch,
    required int pushCursor,
    required int pullCursor,
  }) async {
    for (final entry in {'push': pushCursor, 'pull': pullCursor}.entries) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO sync_peer_progress '
        '(peer_id, epoch, direction, cursor, last_attempt_ms, '
        'last_exchange_ms, last_clean_ms, error_code) '
        'VALUES (?, ?, ?, ?, NULL, NULL, NULL, NULL)',
        [peerId, epoch, entry.key, entry.value],
      );
    }
  }

  static SyncPeerProgress _progressFromRow(dynamic row) => SyncPeerProgress(
    peerId: row.read<String>('peer_id'),
    epoch: row.read<String>('epoch'),
    direction: row.read<String>('direction'),
    cursor: row.read<int>('cursor'),
    lastAttempt: _date(row.readNullable<int>('last_attempt_ms')),
    lastExchange: _date(row.readNullable<int>('last_exchange_ms')),
    lastClean: _date(row.readNullable<int>('last_clean_ms')),
    errorCode: row.readNullable<String>('error_code'),
  );

  static SyncRejectedRecord _rejectedFromRow(dynamic row) => SyncRejectedRecord(
    peerId: row.read<String>('peer_id'),
    epoch: row.read<String>('epoch'),
    direction: row.read<String>('direction'),
    changeId: row.read<String>('change_id'),
    entityType: row.read<String>('entity_type'),
    entityId: row.read<String>('entity_id'),
    operation: row.read<String>('operation'),
    reasonCode: row.read<String>('reason_code'),
    attempts: row.read<int>('attempts'),
    firstSeen: _date(row.read<int>('first_seen_ms'))!,
    lastSeen: _date(row.read<int>('last_seen_ms'))!,
    resolved: row.readNullable<int>('resolved_ms') != null,
  );

  static DateTime? _date(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}
