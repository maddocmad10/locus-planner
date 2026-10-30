import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../utils/diary_merge.dart';

/// A row that an inbound change actually modified.
typedef SyncChangedEntity = ({String type, String id, bool deleted});

/// A change that was dropped because its shape or payload could not be
/// understood. The rest of the batch is still applied, so a single change from
/// a newer (or older) peer cannot wedge sync forever.
typedef SyncRejectedChange = ({String type, String id, String reason});

/// Outcome of applying a batch of inbound changes.
class SyncApplyResult {
  const SyncApplyResult({
    required this.applied,
    required this.skipped,
    this.changes = const [],
    this.rejected = const [],
  });

  /// Changes that modified local data.
  final int applied;

  /// Changes ignored because local data was newer, the change was a replay,
  /// or its parent row no longer exists.
  final int skipped;

  /// The rows behind [applied], in the order they were applied.
  final List<SyncChangedEntity> changes;

  /// Changes whose payload could not be applied. They are reported back to the
  /// sender so the problem is visible, but they never reject the batch.
  final List<SyncRejectedChange> rejected;
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

  /// Diary rows whose merged text the other device does not have yet. They are
  /// re-saved once outbox capture is back on, so the merge is sent back.
  final _republish = <String>[];

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
  ///
  /// The result is ordered by [snapshotTypeRank] and then entity id. That order
  /// is independent of row positions, so a snapshot page can resume after the
  /// last row it sent (the server's `after` token) even if an earlier row is
  /// deleted while the transfer is in progress. Tombstones are sorted into the
  /// same buckets as live rows, which also keeps a delete in place of the row
  /// it replaced.
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
    changes.sort(_compareSnapshotRows);
    return changes;
  }

  /// Rank of a synced entity type in snapshot order. Unknown types sort last
  /// and are rejected as snapshot resume tokens by the server.
  static int snapshotTypeRank(String type) {
    final index = _schemaOrder.indexOf(type);
    return index < 0 ? _schemaOrder.length : index;
  }

  /// Whether [type] is a synced entity this version understands.
  static bool isSnapshotEntityType(String type) => _schemas.containsKey(type);

  static final _schemaOrder = _schemas.keys.toList(growable: false);

  static int _compareSnapshotRows(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final rankA = snapshotTypeRank(a['entityType'] as String);
    final rankB = snapshotTypeRank(b['entityType'] as String);
    if (rankA != rankB) return rankA.compareTo(rankB);
    return (a['entityId'] as String).compareTo(b['entityId'] as String);
  }

  /// Applies [changes] in order inside one transaction with trigger-based
  /// outbox capture suppressed. The desktop may supply
  /// [fanOutOriginDeviceId] to enqueue accepted changes for other phones;
  /// mobile callers omit it so pulled changes are not relayed back.
  ///
  /// A malformed change is skipped and listed in [SyncApplyResult.rejected];
  /// it never rejects the rest of the batch. That keeps a newer peer's payload
  /// shape from poisoning an older peer's sync cursor.
  Future<SyncApplyResult> apply(
    List<Map<String, dynamic>> changes, {
    String? fanOutOriginDeviceId,
  }) async {
    var skipped = 0;
    final changed = <SyncChangedEntity>[];
    final rejected = <SyncRejectedChange>[];
    await _db.transaction(() async {
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        for (final change in changes) {
          try {
            if (await _applyOne(change)) {
              changed.add((
                type: change['entityType'] as String,
                id: change['entityId'] as String,
                deleted: change['operation'] == 'delete',
              ));
            } else {
              skipped++;
            }
          } on FormatException catch (error) {
            developer.log(
              'Skipping a malformed sync change',
              name: 'SyncChangeApplier',
              error: error,
            );
            rejected.add(_rejection(change, error.message));
          } on SqliteException catch (error, stackTrace) {
            // A malformed value can still reach SQLite as a constraint or type
            // error. Isolating it keeps the rest of the batch (and the sender's
            // cursor) moving instead of retrying the same page forever.
            developer.log(
              'Skipping a sync change that SQLite rejected',
              name: 'SyncChangeApplier',
              error: error,
              stackTrace: stackTrace,
            );
            rejected.add(_rejection(change, 'could not be applied'));
          }
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
      // Outbox capture is on again, so this update bumps the row's version and
      // queues it for the sender, which still holds the unmerged text.
      final republishedDiaryIds = _republish.toSet();
      for (final id in republishedDiaryIds) {
        await _db.customStatement(
          'UPDATE diary_entries SET content = content WHERE id = ?',
          [id],
        );
      }
      _republish.clear();

      // The desktop must relay accepted phone changes to the other paired
      // phones. Mobile callers omit fanOutOriginDeviceId, so applying desktop
      // changes on a phone never creates a relay loop. Diary merges are already
      // queued above as desktop-originated changes and must not be duplicated.
      if (fanOutOriginDeviceId != null && fanOutOriginDeviceId.isNotEmpty) {
        await _enqueueFanOut(
          changed,
          fanOutOriginDeviceId,
          republishedDiaryIds,
        );
      }
    });
    _notifyStreams(changed);
    return SyncApplyResult(
      applied: changed.length,
      skipped: skipped,
      changes: changed,
      rejected: rejected,
    );
  }

  static SyncRejectedChange _rejection(
    Map<String, dynamic> change,
    String reason,
  ) {
    final type = change['entityType'];
    final id = change['entityId'];
    return (
      type: type is String && type.isNotEmpty ? type : 'unknown',
      id: id is String && id.isNotEmpty ? id : 'unknown',
      reason: reason,
    );
  }

  Future<void> _enqueueFanOut(
    List<SyncChangedEntity> changed,
    String originDeviceId,
    Set<String> republishedDiaryIds,
  ) async {
    final queued = <String>{};
    for (final entity in changed) {
      final key = '${entity.type}:${entity.id}';
      if (!queued.add(key) ||
          (entity.type == 'diary_entry' &&
              republishedDiaryIds.contains(entity.id))) {
        continue;
      }
      final schema = _schemas[entity.type]!;
      final versions = await _db
          .customSelect(
            'SELECT updated_at, deleted FROM sync_row_versions '
            'WHERE entity_type = ? AND entity_id = ?',
            variables: [
              Variable.withString(entity.type),
              Variable.withString(entity.id),
            ],
          )
          .get();
      if (versions.isEmpty) continue;
      final version = versions.first.read<int>('updated_at');
      final deleted = versions.first.read<int>('deleted') == 1;
      final operation = deleted ? 'delete' : 'upsert';
      Map<String, dynamic> payload;
      if (deleted) {
        payload = {'id': entity.id, 'updated_at': version};
      } else {
        final rows = await _db
            .customSelect(
              'SELECT ${schema.columns.join(', ')} FROM ${schema.table} WHERE id = ?',
              variables: [Variable.withString(entity.id)],
            )
            .get();
        if (rows.isEmpty) continue;
        payload = Map<String, dynamic>.from(rows.first.data)
          ..['updated_at'] = version;
      }
      await _db.customStatement(
        'INSERT INTO sync_outbox '
        '(entity_type, entity_id, operation, payload, device_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          entity.type,
          entity.id,
          operation,
          jsonEncode(payload),
          originDeviceId,
          AppClock.now().millisecondsSinceEpoch,
        ],
      );
    }
  }

  /// Rows are written with raw SQL, which Drift cannot see, so watch() streams
  /// (every screen) would keep showing old data. Tell Drift which tables
  /// changed. Deleting a project also cascades to dependent tables.
  void _notifyStreams(List<SyncChangedEntity> changed) {
    if (changed.isEmpty) return;
    final tables = <String>{};
    for (final entity in changed) {
      tables.add(_schemas[entity.type]!.table);
      if (entity.type == 'project' && entity.deleted) {
        tables.addAll(const ['tasks', 'progress_logs', 'focus_sessions']);
      }
      // A diary clash can also delete a differently-keyed row in the same
      // table, which the table name above already covers.
    }
    _db.markTablesUpdated(tables.map(_tableInfo));
  }

  TableInfo<Table, dynamic> _tableInfo(String name) => switch (name) {
    'projects' => _db.projects,
    'events' => _db.events,
    'tasks' => _db.tasks,
    'todo_items' => _db.todoItems,
    'diary_entries' => _db.diaryEntries,
    'progress_logs' => _db.progressLogs,
    'focus_sessions' => _db.focusSessions,
    _ => throw ArgumentError.value(name, 'name', 'Unknown synced table'),
  };

  Future<bool> _applyOne(Map<String, dynamic> change) async {
    final type = change['entityType'];
    final operation = change['operation'];
    final id = change['entityId'];
    if (type is! String) {
      throw const FormatException('Unsupported change');
    }
    // Older clients must tolerate entities introduced by a newer peer.
    // Skip unknown entity types so they cannot permanently block a batch,
    // while still validating the shape and payload of supported entities.
    if (!_schemas.containsKey(type)) return false;
    if (id is! String ||
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
      // id keeps its id on every device and the text of the other row is
      // merged into it (see mergeDiaryContent), so both sides converge, a
      // same-day clash can never fail the whole batch, and nothing the user
      // wrote is discarded.
      final date = payload['date'];
      final incomingContent = payload['content'];
      if (date is! int) {
        throw const FormatException('Invalid diary date');
      }
      if (incomingContent is! String) {
        throw const FormatException('Invalid diary content');
      }
      final clash = await _db
          .customSelect(
            'SELECT id, content FROM diary_entries WHERE date = ? AND id != ?',
            variables: [Variable.withInt(date), Variable.withString(id)],
          )
          .get();
      if (clash.isNotEmpty) {
        // The date column is unique, so there is at most one clashing row.
        final localId = clash.first.read<String>('id');
        final localContent = clash.first.read<String>('content');
        if (localId.compareTo(id) < 0) {
          // The local row keeps its id: fold the incoming text into it and do
          // not insert the incoming row at all.
          final merged = mergeDiaryContent(localContent, incomingContent);
          if (merged == localContent) return false;
          await _db.customStatement(
            'UPDATE diary_entries SET content = ? WHERE id = ?',
            [merged, localId],
          );
          _republish.add(localId);
          return true;
        }
        // The incoming row keeps its id: fold the local text into it, drop
        // the local row and fall through to the normal upsert below.
        final merged = mergeDiaryContent(incomingContent, localContent);
        values[schema.columns.indexOf('content')] = merged;
        await _db.customStatement('DELETE FROM diary_entries WHERE id = ?', [
          localId,
        ]);
        if (merged != incomingContent) _republish.add(id);
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
