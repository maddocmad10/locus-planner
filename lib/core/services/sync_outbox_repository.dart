import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Durable outbox API for the future transport-agnostic SyncEngine.
/// The transport should only acknowledge rows after the peer has durably
/// accepted them. Retrying a batch is safe; the receiver must be idempotent.
class SyncOutboxRepository {
  SyncOutboxRepository(this._db);

  final AppDatabase _db;

  Future<List<SyncOutboxData>> pending({int limit = 100}) {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    return (_db.select(_db.syncOutbox)
          ..orderBy([(row) => OrderingTerm.asc(row.id)])
          ..limit(limit))
        .get();
  }

  /// Removes acknowledged rows only. Call this after remote durable receipt.
  Future<void> acknowledge(Iterable<int> ids) async {
    final values = ids.toSet().toList(growable: false);
    if (values.isEmpty) return;
    await (_db.delete(
      _db.syncOutbox,
    )..where((row) => row.id.isIn(values))).go();
  }

  Future<int> get pendingCount async {
    final count = _db.syncOutbox.id.count();
    final query = _db.selectOnly(_db.syncOutbox)..addColumns([count]);
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
