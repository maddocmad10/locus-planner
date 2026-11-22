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

/// Whole-exchange result. Directional cursors stay in `sync_peer_progress`;
/// this summary is the one source for Today/Sync/completion status.
class SyncExchangeSummary {
  const SyncExchangeSummary({
    required this.peerId,
    required this.epoch,
    required this.outcome,
    required this.continuationCursor,
    required this.requested,
    required this.accounted,
    required this.lastAttempt,
    required this.lastClean,
    required this.errorCode,
  });

  final String peerId;
  final String epoch;

  /// `clean`, `partial`, `attention` or `failed`.
  final String outcome;
  final int? continuationCursor;
  final int requested;
  final int accounted;
  final DateTime? lastAttempt;
  final DateTime? lastClean;
  final String? errorCode;

  bool get isClean => outcome == SyncExchangeOutcome.clean;
  bool get isPartial => outcome == SyncExchangeOutcome.partial;
}

abstract final class SyncExchangeOutcome {
  static const clean = 'clean';
  static const partial = 'partial';
  static const attention = 'attention';
  static const failed = 'failed';
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

  /// Bumped when this build can process a previously unsupported handler or
  /// capability. Repairs recorded below this value become retryable.
  static const currentCapabilityVersion = 1;

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

  Future<SyncExchangeSummary?> latestClean() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_peer_exchange '
          "WHERE outcome = 'clean' AND last_clean_ms IS NOT NULL "
          'ORDER BY last_clean_ms DESC LIMIT 1',
        )
        .get();
    return rows.isEmpty ? null : _exchangeFromRow(rows.first);
  }

  Future<SyncExchangeSummary?> latestExchange({
    String? peerId,
    String? epoch,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_peer_exchange '
          '${peerId != null && epoch != null ? 'WHERE peer_id = ? AND epoch = ? ' : ''}'
          'ORDER BY COALESCE(last_attempt_ms, 0) DESC LIMIT 1',
          variables: [
            if (peerId != null && epoch != null) ...[
              Variable.withString(peerId),
              Variable.withString(epoch),
            ],
          ],
        )
        .get();
    return rows.isEmpty ? null : _exchangeFromRow(rows.first);
  }

  Future<int?> directionCursor({
    required String peerId,
    required String epoch,
    required String direction,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT cursor FROM sync_peer_progress '
          'WHERE peer_id = ? AND epoch = ? AND direction = ?',
          variables: [
            Variable.withString(peerId),
            Variable.withString(epoch),
            Variable.withString(direction),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('cursor');
  }

  /// Persists the whole-exchange outcome. Only a clean exchange advances both
  /// directional clean timestamps; a partial or attention result leaves the
  /// previous clean checkpoint untouched.
  Future<void> recordExchangeOutcome({
    required String peerId,
    required String epoch,
    required String outcome,
    required int requested,
    required int accounted,
    int? continuationCursor,
    String? errorCode,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    final clean = outcome == SyncExchangeOutcome.clean;
    await _db.transaction(() async {
      await _db.customStatement(
        'INSERT INTO sync_peer_exchange '
        '(peer_id, epoch, last_attempt_ms, last_clean_ms, '
        'last_trusted_server_ms, outcome, continuation_cursor, '
        'requested_count, accounted_count, error_code, updated_at) '
        'VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(peer_id, epoch) DO UPDATE SET '
        'last_attempt_ms = excluded.last_attempt_ms, '
        'last_clean_ms = CASE WHEN excluded.last_clean_ms IS NOT NULL '
        'THEN excluded.last_clean_ms '
        'ELSE sync_peer_exchange.last_clean_ms END, '
        'outcome = excluded.outcome, '
        'continuation_cursor = excluded.continuation_cursor, '
        'requested_count = excluded.requested_count, '
        'accounted_count = excluded.accounted_count, '
        'error_code = excluded.error_code, '
        'updated_at = excluded.updated_at',
        [
          peerId,
          epoch,
          now,
          clean ? now : null,
          outcome,
          continuationCursor,
          requested,
          accounted,
          errorCode,
          now,
        ],
      );
      if (clean) {
        await _db.customStatement(
          'UPDATE sync_peer_progress SET last_clean_ms = ? '
          'WHERE peer_id = ? AND epoch = ?',
          [now, peerId, epoch],
        );
      }
    });
  }

  /// Clears proven cursor state for a resync. The old snapshot session is
  /// retired rather than deleted so its captured evidence remains available.
  Future<void> resetPeerForResync({
    required String peerId,
    required String epoch,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        'UPDATE sync_peer_progress SET cursor = 0, last_clean_ms = NULL, '
        "error_code = 'resync' WHERE peer_id = ? AND epoch = ?",
        [peerId, epoch],
      );
      await _db.customStatement(
        'UPDATE sync_peer_exchange SET last_clean_ms = NULL, '
        "outcome = 'failed', error_code = 'resync', continuation_cursor = NULL "
        'WHERE peer_id = ? AND epoch = ?',
        [peerId, epoch],
      );
      await _db.customStatement(
        'UPDATE snapshot_session SET phase = ?, retired_at = ?, updated_at = ? '
        "WHERE peer_id = ? AND epoch = ? "
        "AND phase IN ('capture', 'download', 'upload')",
        ['retired', now, now, peerId, epoch],
      );
    });
  }

  Future<int> openRejectionCount({
    String? peerId,
    String? epoch,
    String? direction,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM sync_rejected_changes '
          'WHERE resolved_ms IS NULL'
          '${peerId != null ? ' AND peer_id = ?' : ''}'
          '${epoch != null ? ' AND epoch = ?' : ''}'
          '${direction != null ? ' AND direction = ?' : ''}',
          variables: [
            if (peerId != null) Variable.withString(peerId),
            if (epoch != null) Variable.withString(epoch),
            if (direction != null) Variable.withString(direction),
          ],
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
    int committedItemCount = 0,
    bool captureComplete = false,
    String phase = 'capture',
    String? peerName,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'INSERT OR IGNORE INTO snapshot_session '
      '(snapshot_id, peer_id, epoch, phase, remote_cursor, resume_token, '
      'trusted_baseline_server_ms, committed_item_count, capture_complete, '
      'peer_name, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?, ?)',
      [
        snapshotId,
        peerId,
        epoch,
        phase,
        trustedBaselineServerMs,
        committedItemCount,
        captureComplete ? 1 : 0,
        peerName,
        now,
        now,
      ],
    );
  }

  /// Captures the local inventory, session and every immutable envelope in one
  /// transaction. A crash before commit leaves no partial capture; a committed
  /// empty inventory is valid.
  Future<void> captureSnapshot({
    required String snapshotId,
    required String peerId,
    required String epoch,
    required Future<List<({String changeId, int ordinal, String payloadJson})>>
    Function()
    readInventory,
    int? trustedBaselineServerMs,
    String? peerName,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final items = await readInventory();
      await _db.customStatement(
        'INSERT OR IGNORE INTO snapshot_session '
        '(snapshot_id, peer_id, epoch, phase, remote_cursor, resume_token, '
        'trusted_baseline_server_ms, committed_item_count, capture_complete, '
        'peer_name, created_at, updated_at) '
        "VALUES (?, ?, ?, 'download', NULL, NULL, ?, ?, 1, ?, ?, ?)",
        [
          snapshotId,
          peerId,
          epoch,
          trustedBaselineServerMs,
          items.length,
          peerName,
          now,
          now,
        ],
      );
      for (final item in items) {
        final (entityType, entityId) = _identityFromPayload(item.payloadJson);
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
    });
  }

  (String, String) _identityFromPayload(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map) {
        final type = decoded['entityType'];
        final id = decoded['entityId'];
        if (type is String && id is String) return (type, id);
      }
    } catch (_) {
      // Leave empty; review cannot safely act on an unreadable item.
    }
    return ('', '');
  }

  Future<Map<String, Object?>?> latestSnapshotSession({
    required String peerId,
    required String epoch,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM snapshot_session '
          'WHERE peer_id = ? AND epoch = ? '
          "AND phase IN ('capture', 'download', 'upload') "
          'ORDER BY created_at DESC LIMIT 1',
          variables: [Variable.withString(peerId), Variable.withString(epoch)],
        )
        .get();
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first.data);
  }

  Future<void> retireSnapshotSessions({
    required String peerId,
    required String epoch,
    String reason = 'retired',
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'UPDATE snapshot_session SET phase = ?, retired_at = ?, updated_at = ? '
      'WHERE peer_id = ? AND epoch = ? '
      "AND phase IN ('capture', 'download', 'upload')",
      [reason, now, now, peerId, epoch],
    );
  }

  /// Marks a recovered item approved for upload. The old staged change is
  /// removed and replaced by an immutable envelope under a fresh change id.
  Future<void> approveSnapshotUpload({
    required String snapshotId,
    required String changeId,
    required String uploadChangeId,
    required String payloadJson,
    required int? reviewedRevision,
    required String? reviewedDigest,
    required String entityType,
    required String entityId,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        'DELETE FROM snapshot_item WHERE snapshot_id = ? AND change_id = ?',
        [snapshotId, changeId],
      );
      await _db.customStatement(
        'INSERT INTO snapshot_item '
        '(snapshot_id, change_id, ordinal, payload_json, disposition, reason, '
        'updated_at, entity_type, entity_id, reviewed_revision, '
        'reviewed_digest, upload_change_id) '
        'VALUES (?, ?, (SELECT COALESCE(MAX(ordinal), 0) + 1 FROM snapshot_item '
        'WHERE snapshot_id = ?), ?, ?, NULL, ?, ?, ?, ?, ?, ?)',
        [
          snapshotId,
          uploadChangeId,
          snapshotId,
          payloadJson,
          'approved_upload',
          now,
          entityType,
          entityId,
          reviewedRevision,
          reviewedDigest,
          uploadChangeId,
        ],
      );
    });
  }

  Future<void> recordRecoveryMapping({
    required String snapshotId,
    required String entityType,
    required String originalId,
    required String recoveredId,
  }) async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO snapshot_recovery_map '
      '(snapshot_id, entity_type, original_id, recovered_id, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        snapshotId,
        entityType,
        originalId,
        recoveredId,
        AppClock.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<String?> recoveredIdFor({
    required String snapshotId,
    required String entityType,
    required String originalId,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT recovered_id FROM snapshot_recovery_map '
          'WHERE snapshot_id = ? AND entity_type = ? AND original_id = ?',
          variables: [
            Variable.withString(snapshotId),
            Variable.withString(entityType),
            Variable.withString(originalId),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<String>('recovered_id');
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
    int? reviewedRevision,
    String? reviewedDigest,
  }) async {
    await _db.customStatement(
      'UPDATE snapshot_item SET disposition = ?, reason = ?, updated_at = ?, '
      'reviewed_revision = COALESCE(?, reviewed_revision), '
      'reviewed_digest = COALESCE(?, reviewed_digest) '
      'WHERE snapshot_id = ? AND change_id = ?',
      [
        disposition,
        reason,
        AppClock.now().millisecondsSinceEpoch,
        reviewedRevision,
        reviewedDigest,
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
      'cursor = excluded.cursor, '
      'last_attempt_ms = excluded.last_attempt_ms, '
      'last_exchange_ms = excluded.last_exchange_ms, '
      'error_code = excluded.error_code',
      [peerId, epoch, direction, cursor ?? 0, now, now, null, errorCode],
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

  static SyncExchangeSummary _exchangeFromRow(dynamic row) =>
      SyncExchangeSummary(
        peerId: row.read<String>('peer_id'),
        epoch: row.read<String>('epoch'),
        outcome:
            row.readNullable<String>('outcome') ??
            SyncExchangeOutcome.attention,
        continuationCursor: row.readNullable<int>('continuation_cursor'),
        requested: row.readNullable<int>('requested_count') ?? 0,
        accounted: row.readNullable<int>('accounted_count') ?? 0,
        lastAttempt: _date(row.readNullable<int>('last_attempt_ms')),
        lastClean: _date(row.readNullable<int>('last_clean_ms')),
        errorCode: row.readNullable<String>('error_code'),
      );

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
