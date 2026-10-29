import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

/// Deletes outbox rows that no paired phone still needs.
///
/// The outbox records every local edit until a phone acknowledges it, so it
/// must be trimmed even when LAN sync has never been switched on. Otherwise the
/// database grows without bound and deleted diary text stays there forever.
///
/// This class is shared by the desktop server (which knows the paired clients
/// and their cursors) and by desktop startup (which prunes before the server is
/// started). It must not be used to prune a paired phone's outbox: a phone's
/// rows are its unsent changes, so only [SyncOutboxPruner.clearAll] is safe
/// there, and only while the phone is unpaired.
class SyncOutboxPruner {
  const SyncOutboxPruner(this._db);

  final AppDatabase _db;

  /// Outbox rows older than this are dropped even if a paired phone never
  /// acknowledged them, so a lost phone cannot make the outbox grow forever.
  /// That phone is told to re-sync from a snapshot the next time it connects.
  static const retention = Duration(days: 60);

  /// Deletes acknowledged rows, and rows older than [retention] that no phone
  /// has acknowledged. With no paired phones the whole outbox is cleared,
  /// because a newly paired phone starts from a snapshot.
  Future<void> prune() async {
    await _db.transaction(() async {
      final clients = await _readClients();
      if (clients.isEmpty) {
        await _clearAllRows();
        return;
      }
      final head = await _db.outboxHead();
      var through = head;
      for (final client in clients) {
        final cursors = client['cursors'];
        final acked = cursors is Map && cursors['desktop'] is int
            ? cursors['desktop'] as int
            : 0;
        if (acked < through) through = acked;
      }
      final cutoff = AppClock.now().subtract(retention).millisecondsSinceEpoch;
      final staleRow = await _db
          .customSelect(
            'SELECT COALESCE(MAX(id), 0) AS stale FROM sync_outbox '
            'WHERE created_at < ?',
            variables: [Variable.withInt(cutoff)],
          )
          .getSingle();
      final stale = staleRow.read<int>('stale');
      if (stale > through) through = stale;
      if (through > head) through = head;
      await _deleteThrough(through);
    });
  }

  /// Deletes every outbox row, keeping `sync.outbox.pruned_through` at the
  /// highest issued id so ids and cursors never move backwards.
  ///
  /// Only safe when there is no paired desktop to receive the changes: a
  /// newly paired phone takes a snapshot, and a freshly paired desktop starts
  /// every phone from a snapshot.
  Future<void> clearAll() async {
    await _db.transaction(_clearAllRows);
  }

  Future<void> _clearAllRows() async {
    await _deleteThrough(await _db.outboxHead());
  }

  Future<void> _deleteThrough(int through) async {
    if (through <= await _db.outboxPrunedThrough()) return;
    await _db.customStatement('DELETE FROM sync_outbox WHERE id <= ?', [
      through,
    ]);
    await _db.setSetting(
      AppDatabase.syncOutboxPrunedThroughSettingKey,
      '$through',
    );
  }

  Future<List<Map<String, dynamic>>> _readClients() async {
    final raw = await _db.getSetting(
      AppDatabase.syncServerPairedClientsSettingKey,
    );
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
