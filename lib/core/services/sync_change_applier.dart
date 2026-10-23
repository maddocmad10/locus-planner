import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

/// Outcome of applying a batch of inbound changes.
class SyncApplyResult {
  const SyncApplyResult({required this.applied, required this.skipped});

  /// Changes that modified local data.
  final int applied;

  /// Changes ignored because local data was newer, the change was a replay,
  /// or its parent row no longer exists.
  final int skipped;
}

/// Applies inbound sync changes to the local database. Shared by the desktop
/// server (phone -> desktop) and the Android client (desktop -> phone), so
/// both sides resolve conflicts with exactly the same rules.
///
/// Every synced row has a version in `sync_row_versions`, maintained by the
/// outbox triggers and carried in each payload as `updated_at` (epoch ms). An
/// incoming change only wins if its version is newer than the local one; an
/// exact tie is broken by device id so both devices pick the same winner.
/// Deletes are versioned tombstones, so a stale upsert cannot resurrect a row
/// that was deleted later.
class SyncChangeApplier {
  SyncChangeApplier(this._db);

  final AppDatabase _db;

  static const _schemas = <String, ({String table, List<String> columns})>{
    'project': (
      table: 'projects',
      columns: [
        'id',
        'name',
        'description',
        'created_at',
        'target_date',
        'target_progress',
      ],
    ),
    'event': (
      table: 'events',
      columns: [
        'id',
        'title',
        'description',
        'start_time',
        'end_time',
        'category',
        'has_reminder',
        'reminder_minutes',
        'recurrence_rule',
      ],
    ),
    'project_task': (
      table: 'tasks',
      columns: ['id', 'project_id', 'title', 'completed', 'sort_order'],
    ),
    'todo': (
      table: 'todo_items',
      columns: ['id', 'title', 'completed', 'created_at', 'due_date'],
    ),
    'diary_entry': (
      table: 'diary_entries',
      columns: ['id', 'date', 'mood', 'content'],
    ),
  };

  /// Every synced row as an upsert plus every delete tombstone, each carrying
  /// its sync version. Used for the desktop's initial snapshot and for the
  /// phone's full push after a resync; because receivers compare versions,
  /// sending rows they already have is harmless.
  static Future<List<Map<String, dynamic>>> readFullState(
    AppDatabase db,
  ) async {
    final changes = <Map<String, dynamic>>[];
    final liveIds = <String, Set<String>>{};
    for (final entry in _schemas.entries) {
      final type = entry.key;
      final rows = await db
          .customSelect(
            'SELECT t.*, COALESCE(v.updated_at, 0) AS sync_updated_at, '
            'v.device_id AS sync_device_id FROM ${entry.value.table} t '
            'LEFT JOIN sync_row_versions v '
            'ON v.entity_type = ? AND v.entity_id = t.id',
            variables: [Variable.withString(type)],
          )
          .get();
      final ids = liveIds.putIfAbsent(type, () => <String>{});
      for (final row in rows) {
        final payload = Map<String, dynamic>.from(row.data);
        final deviceId = payload.remove('sync_device_id');
        payload['updated_at'] = payload.remove('sync_updated_at');
        ids.add(payload['id'] as String);
        changes.add({
          'entityType': type,
          'entityId': payload['id'],
          'operation': 'upsert',
          'payload': payload,
          'deviceId': deviceId,
        });
      }
    }
    final tombstones = await db
        .customSelect(
          'SELECT entity_type, entity_id, updated_at, device_id '
          'FROM sync_row_versions WHERE deleted = 1',
        )
        .get();
    for (final row in tombstones) {
      final type = row.read<String>('entity_type');
      final id = row.read<String>('entity_id');
      final isLive = liveIds[type]?.contains(id) ?? false;
      if (!_schemas.containsKey(type) || isLive) continue;
      changes.add({
        'entityType': type,
        'entityId': id,
        'operation': 'delete',
        'payload': {'id': id, 'updated_at': row.read<int>('updated_at')},
        'deviceId': row.readNullable<String>('device_id'),
      });
    }
    return changes;
  }

  /// Applies [changes] in order inside one transaction with outbox capture
  /// suppressed, so nothing echoes back to the sender. Any malformed change
  /// rejects the whole batch.
  Future<SyncApplyResult> apply(List<Map<String, dynamic>> changes) async {
    var applied = 0;
    var skipped = 0;
    await _db.transaction(() async {
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        for (final change in changes) {
          if (await _applyOne(change)) {
            applied++;
          } else {
            skipped++;
          }
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
    });
    return SyncApplyResult(applied: applied, skipped: skipped);
  }

  Future<bool> _applyOne(Map<String, dynamic> change) async {
    final type = change['entityType'];
    final operation = change['operation'];
    final id = change['entityId'];
    if (type is! String ||
        !_schemas.containsKey(type) ||
        id is! String ||
        id.isEmpty ||
        (operation != 'upsert' && operation != 'delete')) {
      throw const FormatException('Unsupported change');
    }
    final schema = _schemas[type]!;
    final payload = change['payload'];
    if (payload is! Map<String, dynamic> || payload['id'] != id) {
      throw const FormatException('Invalid payload');
    }

    final rawVersion = payload['updated_at'];
    final incomingVersion = rawVersion is int ? rawVersion : null;
    final rawDevice = change['deviceId'];
    final incomingDevice = rawDevice is String ? rawDevice : null;
    final local = await _localVersion(type, id);
    if (incomingVersion != null &&
        local != null &&
        !_incomingWins(incomingVersion, incomingDevice, local)) {
      return false;
    }

    if (operation == 'delete') {
      await _db.customStatement('DELETE FROM ${schema.table} WHERE id = ?', [
        id,
      ]);
      await _recordVersion(
        type,
        id,
        incomingVersion,
        incomingDevice,
        local,
        deleted: true,
      );
      return true;
    }

    final values = schema.columns.map((column) {
      if (!payload.containsKey(column)) {
        throw const FormatException('Missing payload field');
      }
      final value = payload[column];
      if (value == null || value is String || value is int || value is double) {
        return value;
      }
      if (value is bool) return value ? 1 : 0;
      throw const FormatException('Invalid payload value');
    }).toList();

    if (type == 'diary_entry') {
      // Diary dates are unique independently of id. The row with the lowest
      // id wins on every device, so both sides converge and a same-day clash
      // can never fail the whole batch.
      final date = payload['date'];
      if (date is! int) {
        throw const FormatException('Invalid diary date');
      }
      final clash = await _db
          .customSelect(
            'SELECT id FROM diary_entries WHERE date = ? AND id != ?',
            variables: [Variable.withInt(date), Variable.withString(id)],
          )
          .get();
      final lowerIdExists = clash.any(
        (row) => row.read<String>('id').compareTo(id) < 0,
      );
      if (lowerIdExists) return false;
      if (clash.isNotEmpty) {
        await _db.customStatement(
          'DELETE FROM diary_entries WHERE date = ? AND id != ?',
          [date, id],
        );
      }
    }
    if (type == 'project_task') {
      // The parent project may have been deleted since this change was
      // recorded. The delete wins; skip instead of failing the foreign key.
      final parent = payload['project_id'];
      if (parent is! String) {
        throw const FormatException('Invalid task project');
      }
      final parentRows = await _db
          .customSelect(
            'SELECT 1 AS present FROM projects WHERE id = ?',
            variables: [Variable.withString(parent)],
          )
          .get();
      if (parentRows.isEmpty) return false;
    }

    final placeholders = List.filled(schema.columns.length, '?').join(', ');
    final columns = schema.columns.join(', ');
    final updates = schema.columns
        .where((column) => column != 'id')
        .map((column) => '$column = excluded.$column')
        .join(', ');
    await _db.customStatement(
      'INSERT INTO ${schema.table} ($columns) VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      values,
    );
    await _recordVersion(
      type,
      id,
      incomingVersion,
      incomingDevice,
      local,
      deleted: false,
    );
    return true;
  }

  bool _incomingWins(
    int incomingVersion,
    String? incomingDevice,
    _LocalVersion local,
  ) {
    if (incomingVersion != local.updatedAt) {
      return incomingVersion > local.updatedAt;
    }
    // Exact tie: the higher device id wins on both sides. The same device with
    // the same version is a replay of a change that was already applied.
    return (incomingDevice ?? '').compareTo(local.deviceId ?? '') > 0;
  }

  Future<_LocalVersion?> _localVersion(String type, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT updated_at, device_id FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          variables: [Variable.withString(type), Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return _LocalVersion(
      rows.first.read<int>('updated_at'),
      rows.first.readNullable<String>('device_id'),
    );
  }

  Future<void> _recordVersion(
    String type,
    String id,
    int? incomingVersion,
    String? incomingDevice,
    _LocalVersion? local, {
    required bool deleted,
  }) async {
    // Changes from a peer that predates versioning are applied unconditionally
    // and stamped just after whatever version this row already had.
    final version =
        incomingVersion ??
        _maxInt(
          AppClock.now().millisecondsSinceEpoch,
          (local?.updatedAt ?? 0) + 1,
        );
    await _db.customStatement(
      'INSERT INTO sync_row_versions '
      '(entity_type, entity_id, updated_at, device_id, deleted) '
      'VALUES (?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id) DO UPDATE SET '
      'updated_at = excluded.updated_at, device_id = excluded.device_id, '
      'deleted = excluded.deleted',
      [type, id, version, incomingDevice, deleted ? 1 : 0],
    );
  }

  static int _maxInt(int a, int b) => a > b ? a : b;
}

class _LocalVersion {
  const _LocalVersion(this.updatedAt, this.deviceId);

  final int updatedAt;
  final String? deviceId;
}
