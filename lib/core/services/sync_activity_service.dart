import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

class SyncLogEntry {
  const SyncLogEntry({
    required this.startedAt,
    required this.durationMs,
    required this.peerId,
    required this.transport,
    required this.direction,
    required this.applied,
    required this.skipped,
    required this.rejected,
    required this.errorCode,
  });

  final DateTime startedAt;
  final int durationMs;
  final String? peerId;
  final String transport;
  final String direction;
  final int applied;
  final int skipped;
  final int rejected;
  final String? errorCode;
}

class SyncConflictEntry {
  const SyncConflictEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.field,
    required this.kind,
    required this.loserValue,
    required this.loserDevice,
    required this.loserWall,
    required this.winnerWall,
    required this.createdAt,
  });

  final int id;
  final String entityType;
  final String entityId;
  final String? field;
  final String kind;
  final String? loserValue;
  final String? loserDevice;
  final int loserWall;
  final int winnerWall;
  final DateTime createdAt;
}

class SyncActivityService {
  SyncActivityService(this._db);

  final AppDatabase _db;

  Future<void> record({
    required DateTime startedAt,
    required int durationMs,
    String? peerId,
    String transport = 'lan',
    required String direction,
    int applied = 0,
    int skipped = 0,
    int rejected = 0,
    String? errorCode,
  }) async {
    await _db.customStatement(
      'INSERT INTO sync_log '
      '(started_at, duration_ms, peer_id, transport, direction, applied, '
      'skipped, rejected, error_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        startedAt.millisecondsSinceEpoch,
        durationMs,
        peerId,
        transport,
        direction,
        applied,
        skipped,
        rejected,
        errorCode,
      ],
    );
  }

  Future<List<SyncLogEntry>> recent({int limit = 50}) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_log ORDER BY started_at DESC LIMIT ?',
          variables: [Variable.withInt(limit.clamp(1, 500))],
        )
        .get();
    return [
      for (final row in rows)
        SyncLogEntry(
          startedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('started_at'),
          ),
          durationMs: row.read<int>('duration_ms'),
          peerId: row.readNullable<String>('peer_id'),
          transport: row.read<String>('transport'),
          direction: row.read<String>('direction'),
          applied: row.read<int>('applied'),
          skipped: row.read<int>('skipped'),
          rejected: row.read<int>('rejected'),
          errorCode: row.readNullable<String>('error_code'),
        ),
    ];
  }

  Future<List<SyncConflictEntry>> openConflicts({int limit = 100}) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM sync_conflicts WHERE reviewed_at IS NULL '
          'ORDER BY created_at DESC LIMIT ?',
          variables: [Variable.withInt(limit.clamp(1, 500))],
        )
        .get();
    return [
      for (final row in rows)
        SyncConflictEntry(
          id: row.read<int>('id'),
          entityType: row.read<String>('entity_type'),
          entityId: row.read<String>('entity_id'),
          field: row.readNullable<String>('field'),
          kind: row.read<String>('kind'),
          loserValue: row.readNullable<String>('loser_value'),
          loserDevice: row.readNullable<String>('loser_device'),
          loserWall: row.read<int>('loser_wall'),
          winnerWall: row.read<int>('winner_wall'),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at'),
          ),
        ),
    ];
  }

  Future<void> markReviewed(int id) async {
    await _db.customStatement(
      'UPDATE sync_conflicts SET reviewed_at = ? WHERE id = ?',
      [AppClock.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> prune() async {
    final cutoff = AppClock.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await _db.customStatement('DELETE FROM sync_log WHERE started_at < ?', [
      cutoff,
    ]);
    await _db.customStatement(
      'DELETE FROM sync_conflicts '
      'WHERE reviewed_at IS NOT NULL AND reviewed_at < ?',
      [cutoff],
    );
  }
}
