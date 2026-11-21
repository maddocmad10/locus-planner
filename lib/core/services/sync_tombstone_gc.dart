import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

/// Horizon-based garbage collection for delete tombstones.
///
/// A tombstone may be removed only when it is older than the retention window,
/// no outbox row still references it, and every currently paired client has
/// acknowledged at least the current outbox head. The retained horizon lets a
/// returning phone distinguish "the desktop deleted this" from "the phone has
/// a newer edit" without keeping tombstones forever.
class SyncTombstoneGc {
  SyncTombstoneGc(this._db);

  static const retention = Duration(days: 180);

  final AppDatabase _db;

  Future<int> prune() async {
    final cutoff = AppClock.now().subtract(retention).millisecondsSinceEpoch;
    final clientsRaw = await _db.getSetting(
      AppDatabase.syncServerPairedClientsSettingKey,
    );
    if (clientsRaw != null && clientsRaw.isNotEmpty) {
      // If any paired client still has an unacknowledged outbox position,
      // deleting tombstones would remove the evidence it needs to converge.
      final head = await _db.outboxHead();
      final clients = _decodeCursors(clientsRaw);
      if (clients.any((cursor) => cursor < head)) return 0;
    }

    final rows = await _db
        .customSelect(
          'SELECT entity_type, entity_id, updated_at FROM sync_row_versions v '
          'WHERE v.deleted = 1 AND v.updated_at < ? '
          'AND NOT EXISTS (SELECT 1 FROM sync_outbox o '
          '  WHERE o.entity_type = v.entity_type '
          '  AND o.entity_id = v.entity_id)',
          variables: [Variable.withInt(cutoff)],
        )
        .get();
    if (rows.isEmpty) return 0;

    var horizon = 0;
    for (final row in rows) {
      final updatedAt = row.read<int>('updated_at');
      if (updatedAt > horizon) horizon = updatedAt;
    }
    await _db.transaction(() async {
      for (final row in rows) {
        await _db.customStatement(
          'DELETE FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ? AND deleted = 1',
          [row.read<String>('entity_type'), row.read<String>('entity_id')],
        );
        await _db.customStatement(
          'DELETE FROM sync_field_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          [row.read<String>('entity_type'), row.read<String>('entity_id')],
        );
      }
      final oldHorizon =
          int.tryParse(
            await _db.getSetting(AppDatabase.syncTombstoneHorizonSettingKey) ??
                '0',
          ) ??
          0;
      if (horizon > oldHorizon) {
        await _db.setSetting(
          AppDatabase.syncTombstoneHorizonSettingKey,
          '$horizon',
        );
      }
    });
    return rows.length;
  }

  static List<int> _decodeCursors(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final entry in decoded.whereType<Map<String, dynamic>>())
          (entry['cursors'] as Map<String, dynamic>?)?['desktop'] is int
              ? (entry['cursors'] as Map<String, dynamic>)['desktop'] as int
              : 0,
      ];
    } catch (_) {
      return const [];
    }
  }
}
