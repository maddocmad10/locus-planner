import 'dart:convert';

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

  /// Exact envelopes for retry, oldest first. The payload is decoded only for
  /// the sync client; UI callers use [openRejections] and see reason codes.
  Future<List<Map<String, dynamic>>> openRepairPayloads({
    required String peerId,
    required String epoch,
    required String direction,
    int limit = 100,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT change_id, payload_json FROM sync_rejected_changes '
          'WHERE peer_id = ? AND epoch = ? AND direction = ? '
          'AND resolved_ms IS NULL ORDER BY first_seen_ms LIMIT ?',
          variables: [
            Variable.withString(peerId),
            Variable.withString(epoch),
            Variable.withString(direction),
            Variable.withInt(limit),
          ],
        )
        .get();
    final result = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final decoded = jsonDecode(row.read<String>('payload_json'));
        if (decoded is Map<String, dynamic>) {
          result.add({...decoded, 'changeId': row.read<String>('change_id')});
        }
      } catch (_) {
        // Leave the repair open; a corrupt envelope is never discarded.
      }
    }
    return result;
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
      'UPDATE sync_rejected_changes SET resolved_ms = ?, '
      "resolution_kind = 'discarded', last_attempt_ms = ? "
      'WHERE peer_id = ? AND epoch = ? AND direction = ? AND change_id = ?',
      [
        AppClock.now().millisecondsSinceEpoch,
        AppClock.now().millisecondsSinceEpoch,
        peerId,
        epoch,
        direction,
        changeId,
      ],
    );
  }

  /// Creates a resumable bootstrap capture. The caller keeps the same id until
  /// every captured row has a durable client-side disposition.
  Future<void> createSnapshotSession({
    required String snapshotId,
    required String peerId,
    required String epoch,
    int? trustedBaselineServerMs,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'INSERT OR IGNORE INTO snapshot_session '
      '(snapshot_id, peer_id, epoch, phase, remote_cursor, resume_token, '
      'trusted_baseline_server_ms, created_at, updated_at) '
      "VALUES (?, ?, ?, 'capture', NULL, NULL, ?, ?, ?)",
      [snapshotId, peerId, epoch, trustedBaselineServerMs, now, now],
    );
  }

  Future<Map<String, Object?>?> latestSnapshotSession({
    required String peerId,
    required String epoch,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM snapshot_session '
          'WHERE peer_id = ? AND epoch = ? AND phase != ? '
          'ORDER BY created_at DESC LIMIT 1',
          variables: [
            Variable.withString(peerId),
            Variable.withString(epoch),
            Variable.withString('complete'),
          ],
        )
        .get();
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first.data);
  }

  Future<void> saveSnapshotItems(
    String snapshotId,
    List<({String changeId, int ordinal, String payloadJson})> items,
  ) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    for (final item in items) {
      var entityType = '';
      var entityId = '';
      try {
        final decoded = jsonDecode(item.payloadJson);
        if (decoded is Map) {
          if (decoded['entityType'] is String) {
            entityType = decoded['entityType'] as String;
          }
          if (decoded['entityId'] is String) {
            entityId = decoded['entityId'] as String;
          }
        }
      } catch (_) {
        // Leave empty; review cannot safely act on an unreadable item.
      }
      await _db.customStatement(
        'INSERT OR IGNORE INTO snapshot_item '
        '(snapshot_id, change_id, ordinal, payload_json, disposition, '
        'updated_at, entity_type, entity_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          snapshotId,
          item.changeId,
          item.ordinal,
          item.payloadJson,
          'pending',
          now,
          entityType,
          entityId,
        ],
      );
    }
  }

  Future<List<Map<String, Object?>>> snapshotItems(String snapshotId) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM snapshot_item WHERE snapshot_id = ? '
          'ORDER BY ordinal',
          variables: [Variable.withString(snapshotId)],
        )
        .get();
    return [for (final row in rows) Map<String, Object?>.from(row.data)];
  }

  /// Remembers that a captured row also exists in the desktop snapshot. The
  /// flag is durable so a capture resumed after a restart still knows which
  /// rows came from earlier desktop pages.
  Future<void> markSnapshotItemsOnDesktop(
    String snapshotId,
    Iterable<String> entityKeys,
  ) async {
    if (entityKeys.isEmpty) return;
    await _db.transaction(() async {
      for (final key in entityKeys) {
        final separator = key.indexOf(':');
        if (separator <= 0 || separator == key.length - 1) continue;
        await _db.customStatement(
          'UPDATE snapshot_item SET desktop_present = 1 '
          'WHERE snapshot_id = ? AND entity_type = ? AND entity_id = ?',
          [
            snapshotId,
            key.substring(0, separator),
            key.substring(separator + 1),
          ],
        );
      }
    });
  }

  Future<void> markSnapshotItem({
    required String snapshotId,
    required String changeId,
    required String disposition,
    String? reason,
  }) async {
    await _db.customStatement(
      'UPDATE snapshot_item SET disposition = ?, reason = ?, updated_at = ? '
      'WHERE snapshot_id = ? AND change_id = ?',
      [
        disposition,
        reason,
        AppClock.now().millisecondsSinceEpoch,
        snapshotId,
        changeId,
      ],
    );
  }

  Future<void> updateSnapshotSession({
    required String snapshotId,
    String? phase,
    int? remoteCursor,
    String? resumeToken,
  }) async {
    await _db.customStatement(
      'UPDATE snapshot_session SET phase = COALESCE(?, phase), '
      'remote_cursor = COALESCE(?, remote_cursor), '
      'resume_token = COALESCE(?, resume_token), updated_at = ? '
      'WHERE snapshot_id = ?',
      [
        phase,
        remoteCursor,
        resumeToken,
        AppClock.now().millisecondsSinceEpoch,
        snapshotId,
      ],
    );
  }

  Future<void> completeSnapshotSession(String snapshotId) async {
    await _db.transaction(() async {
      await _db.customStatement(
        'UPDATE snapshot_session SET phase = ?, updated_at = ? '
        'WHERE snapshot_id = ?',
        ['complete', AppClock.now().millisecondsSinceEpoch, snapshotId],
      );
      await _db.customStatement(
        'DELETE FROM snapshot_item WHERE snapshot_id = ?',
        [snapshotId],
      );
    });
  }

  Future<void> noteExchange({
    required String peerId,
    required String epoch,
    required String direction,
    required int? cursor,
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
        cursor ?? 0,
        now,
        now,
        clean ? now : null,
        errorCode,
      ],
    );
  }

  /// Records the server's own clock for the last trusted checkpoint.
  Future<void> noteTrustedServerTime({
    required String peerId,
    required String epoch,
    required int serverTimeMs,
  }) async {
    await _db.customStatement(
      'INSERT INTO sync_peer_exchange '
      '(peer_id, epoch, last_attempt_ms, last_trusted_server_ms) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT(peer_id, epoch) DO UPDATE SET '
      'last_trusted_server_ms = MAX('
      'COALESCE(sync_peer_exchange.last_trusted_server_ms, 0), '
      'excluded.last_trusted_server_ms)',
      [peerId, epoch, AppClock.now().millisecondsSinceEpoch, serverTimeMs],
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
