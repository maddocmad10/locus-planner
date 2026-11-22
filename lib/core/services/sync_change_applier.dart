import 'dart:convert';
import 'dart:developer' as developer;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../db/app_database.dart';
import '../domain/project_status.dart';
import '../utils/app_clock.dart';
import '../utils/completion_slot.dart';
import '../utils/diary_merge.dart';
import '../utils/recurrence.dart';
import '../utils/recurrence_spec.dart';
import 'sync_receipt_store.dart';

/// A row that an inbound change actually modified.
typedef SyncChangedEntity = ({String type, String id, bool deleted});

/// A change that was dropped because its shape or payload could not be
/// understood. The rest of the batch is still applied, so a single change from
/// a newer (or older) peer cannot wedge sync forever.
typedef SyncRejectedChange = ({String type, String id, String reason});

/// One durable outcome for a requested change. [changeId] is echoed so a peer
/// can remove the exact item it sent, even when several changes touch one row.
class SyncChangeReceipt {
  const SyncChangeReceipt({
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.outcome,
    this.reason,
    this.revision,
    this.counter,
    this.operation = 'unknown',
  });

  final String? changeId;
  final String entityType;
  final String entityId;

  /// applied, replay, superseded, rejected or unsupported.
  final String outcome;
  final String? reason;

  /// The requested revision tuple `wallMs/counter` for exact matching.
  final int? revision;
  final int? counter;
  final String operation;

  Map<String, Object?> toJson() => {
    if (changeId != null) 'changeId': changeId,
    'entityType': entityType,
    'entityId': entityId,
    'outcome': outcome,
    if (reason != null) 'reason': reason,
    if (revision != null) 'revision': revision,
    if (counter != null) 'counter': counter,
    'operation': operation,
  };
}

/// Where a batch came from, so receipts and repairs are committed with the
/// same transaction as the data they describe.
class SyncReceiptContext {
  const SyncReceiptContext({
    required this.peerId,
    required this.epoch,
    required this.direction,
  });

  final String peerId;
  final String epoch;

  /// push or pull.
  final String direction;
}

/// Outcome of applying a batch of inbound changes.
class SyncApplyResult {
  const SyncApplyResult({
    required this.applied,
    required this.skipped,
    this.changes = const [],
    this.rejected = const [],
    this.receipts = const [],
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

  /// One result per requested change, suitable for the receipts wire field.
  final List<SyncChangeReceipt> receipts;
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

  /// Plan items moved to a winning plan while two same-day plans clashed. They
  /// are re-saved after outbox capture is back on so the other device learns
  /// their new parent.
  final _republishPlanItems = <String>[];

  /// To-do notes and event descriptions whose losing text was merged into the
  /// winner. Re-saved with capture on so the sender receives the merged text.
  final _republishTextRows = <({String type, String id})>{};

  /// Tasks whose recurrence should be normalized after a completion arrives.
  final _completionTasks = <String>{};

  static const _schemas =
      <
        String,
        ({
          String table,
          List<String> columns,
          Map<String, Object?> defaults,
          String versionKey,
        })
      >{
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
          defaults: {},
          versionKey: 'updated_at',
        ),
        'event': (
          table: 'events',
          columns: [
            'id',
            'title',
            'description',
            'description_format',
            'start_time',
            'end_time',
            'category',
            'has_reminder',
            'reminder_minutes',
            'recurrence_rule',
            'recurrence_spec',
            'all_day',
            'recurrence_end',
            'recurrence_exceptions',
          ],
          // A peer from before schema 15 sends the old payload shape. Treat the
          // added columns as their database defaults instead of rejecting it.
          defaults: {
            'description_format': 'plain',
            'all_day': 0,
            'recurrence_end': null,
            'recurrence_exceptions': '[]',
            'recurrence_spec': null,
          },
          versionKey: 'updated_at',
        ),
        'project_task': (
          table: 'tasks',
          columns: [
            'id',
            'project_id',
            'title',
            'completed',
            'status_key',
            'start_date',
            'due_date',
            'estimated_minutes',
            'priority',
            'sort_order',
          ],
          // An old peer only knows the checklist shape. Derive status_key from
          // its completed flag in _applyOne; these defaults are the fallback
          // for payloads that omit the newer columns entirely.
          defaults: {
            'status_key': 'todo',
            'start_date': null,
            'due_date': null,
            'estimated_minutes': null,
            'priority': 0,
          },
          versionKey: 'updated_at',
        ),
        'project_status': (
          table: 'project_statuses',
          columns: [
            'id',
            'project_id',
            'status_key',
            'name',
            'color_token',
            'position',
            'is_done',
            'is_default',
            'created_at',
            'updated_at',
          ],
          defaults: {
            'color_token': 'blue',
            'position': 0,
            'is_done': 0,
            'is_default': 1,
          },
          versionKey: 'sync_updated_at',
        ),
        'project_milestone': (
          table: 'project_milestones',
          columns: [
            'id',
            'project_id',
            'title',
            'description',
            'target_date',
            'completed_at',
            'position',
            'created_at',
            'updated_at',
          ],
          defaults: {'description': null, 'position': 0},
          versionKey: 'sync_updated_at',
        ),
        'task_dependency': (
          table: 'task_dependencies',
          columns: [
            'id',
            'predecessor_task_id',
            'successor_task_id',
            'dependency_type',
            'lag_minutes',
            'created_at',
            'updated_at',
          ],
          defaults: {'dependency_type': 'finish_to_start', 'lag_minutes': 0},
          versionKey: 'sync_updated_at',
        ),
        'habit': (
          table: 'habits',
          columns: ['id', 'name', 'icon', 'created_at', 'target_per_week'],
          // A peer from before schema 11 has no habit payloads at all, but a
          // hand-built or partially upgraded payload should still fit defaults.
          defaults: {'icon': '🔥', 'target_per_week': 5},
          versionKey: 'updated_at',
        ),
        'habit_log': (
          table: 'habit_logs',
          columns: ['id', 'habit_id', 'date', 'completed'],
          defaults: {'completed': 1},
          versionKey: 'updated_at',
        ),
        'todo': (
          table: 'todo_items',
          columns: [
            'id',
            'title',
            'notes',
            'notes_format',
            'completed',
            'created_at',
            'start_date',
            'due_date',
            'priority',
            'tags',
            'recurrence_rule',
            'recurrence_spec',
            'parent_id',
            'project_id',
            'reminder_at',
            'estimated_minutes',
            'is_important',
            'urgency_override',
            'due_kind',
            'due_date_key',
            'undated_generation',
          ],
          // A peer from before schema 12 sends the old payload shape. Treat the
          // missing fields as their database defaults instead of rejecting the
          // change, so an upgraded device and an older phone still sync.
          defaults: {
            'notes': null,
            'notes_format': 'plain',
            'start_date': null,
            'due_date': null,
            'priority': 0,
            'tags': '[]',
            'recurrence_rule': null,
            'recurrence_spec': null,
            'parent_id': null,
            'project_id': null,
            'reminder_at': null,
            'estimated_minutes': null,
            'is_important': 0,
            'urgency_override': null,
            'due_kind': 'legacy_instant',
            'due_date_key': null,
            'undated_generation': null,
          },
          versionKey: 'updated_at',
        ),
        // Append-only completion history. Rows are never edited, so normal
        // version ordering is enough; deleting a to-do cascades the rows and
        // the delete triggers produce the tombstones.
        'todo_completion': (
          table: 'todo_completions',
          columns: [
            'id',
            'todo_id',
            'occurrence_due',
            'completed_at',
            'occurrence_key',
            'slot_kind',
            'slot_date',
            'slot_generation',
          ],
          defaults: {
            'occurrence_key': null,
            'slot_kind': 'legacy_instant',
            'slot_date': null,
            'slot_generation': null,
          },
          versionKey: 'updated_at',
        ),
        'diary_entry': (
          table: 'diary_entries',
          columns: ['id', 'date', 'mood', 'content'],
          defaults: {},
          versionKey: 'updated_at',
        ),
        // My Day tables store a real `updated_at` business column, so their
        // sync version travels as `sync_updated_at`. Plans are listed before
        // items so a snapshot always creates a parent before its children.
        'daily_plan': (
          table: 'daily_plans',
          columns: ['id', 'day_key', 'intention', 'created_at', 'updated_at'],
          defaults: {},
          versionKey: 'sync_updated_at',
        ),
        'daily_plan_item': (
          table: 'daily_plan_items',
          columns: [
            'id',
            'plan_id',
            'todo_item_id',
            'project_task_id',
            'sort_order',
            'planned_minutes',
            'created_at',
            'updated_at',
          ],
          defaults: {},
          versionKey: 'sync_updated_at',
        ),
        // Phase 2 calendar blocks. They reference either a personal to-do or a
        // project checklist task and travel after both in a snapshot.
        'task_schedule_block': (
          table: 'task_schedule_blocks',
          columns: [
            'id',
            'todo_item_id',
            'project_task_id',
            'start_at',
            'end_at',
            'timezone_id',
            'block_kind',
            'note',
            'created_at',
            'updated_at',
            'sort_order',
          ],
          defaults: {'block_kind': 'work', 'sort_order': 0},
          versionKey: 'sync_updated_at',
        ),
        // Saved views are user data but contain only validated JSON.
        'saved_filter': (
          table: 'saved_filters',
          columns: [
            'id',
            'name',
            'entity_scope',
            'filter_json',
            'sort_json',
            'is_pinned',
            'position',
            'created_at',
            'updated_at',
            'definition_version',
          ],
          defaults: {
            'sort_json': '[]',
            'is_pinned': 0,
            'position': 0,
            'definition_version': 1,
          },
          versionKey: 'sync_updated_at',
        ),
        'planning_preference': (
          table: 'planning_preferences',
          columns: [
            'id',
            'timezone_id',
            'default_slot_minutes',
            'week_start_day',
            'day_start_minute',
            'day_end_minute',
            'buffer_minutes',
            'urgency_window_days',
            'created_at',
            'updated_at',
          ],
          defaults: {
            'timezone_id': null,
            'default_slot_minutes': 30,
            'week_start_day': 1,
            'day_start_minute': 480,
            'day_end_minute': 1080,
            'buffer_minutes': 10,
            'urgency_window_days': 3,
          },
          versionKey: 'sync_updated_at',
        ),
        'working_hours': (
          table: 'working_hours',
          columns: [
            'id',
            'weekday',
            'enabled',
            'start_minute',
            'end_minute',
            'created_at',
            'updated_at',
          ],
          defaults: {'enabled': 1},
          versionKey: 'sync_updated_at',
        ),
        'working_break': (
          table: 'working_breaks',
          columns: [
            'id',
            'weekday',
            'start_minute',
            'end_minute',
            'label',
            'created_at',
            'updated_at',
          ],
          defaults: {'label': null},
          versionKey: 'sync_updated_at',
        ),
        // Metadata only. Blob bytes travel through the paired-LAN blob routes
        // in a later phase; older peers never see this entity type and simply
        // ignore it.
        'attachment': (
          table: 'attachments',
          columns: [
            'id',
            'todo_id',
            'event_id',
            'kind',
            'display_name',
            'mime_type',
            'size_bytes',
            'sha256',
            'width',
            'height',
            'alt_text',
            'position',
            'created_at',
            'updated_at',
          ],
          defaults: {
            'todo_id': null,
            'event_id': null,
            'width': null,
            'height': null,
            'alt_text': null,
            'position': 0,
          },
          versionKey: 'sync_updated_at',
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
    return db.transaction(() async {
      final changes = <Map<String, dynamic>>[];
      final liveIds = <String, Set<String>>{};
      // field-origins-v2 travels with snapshots and relays as well as ordinary
      // trigger output. Read it once from committed rows.
      final fieldOriginRows = await db
          .customSelect(
            'SELECT entity_type, entity_id, field, updated_at, hlc_counter, '
            'device_id FROM sync_field_versions',
          )
          .get();
      final fieldOrigins = <String, Map<String, List<Object?>>>{};
      for (final row in fieldOriginRows) {
        final key =
            '${row.read<String>('entity_type')}:${row.read<String>('entity_id')}';
        fieldOrigins.putIfAbsent(key, () => {})[row.read<String>('field')] = [
          row.read<int>('updated_at'),
          row.read<int>('hlc_counter'),
          row.readNullable<String>('device_id'),
        ];
      }
      for (final entry in _schemas.entries) {
        final type = entry.key;
        final rows = await db
            .customSelect(
              'SELECT t.*, COALESCE(v.updated_at, 0) AS sync_updated_at, '
              'COALESCE(v.hlc_counter, 0) AS sync_hlc_counter, '
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
          payload[entry.value.versionKey] = payload.remove('sync_updated_at');
          payload['hlc_counter'] = payload.remove('sync_hlc_counter');
          payload['deleted'] = false;
          payload['fv'] = fieldOrigins['$type:${payload['id']}'] ?? const {};
          ids.add(payload['id'] as String);
          changes.add({
            'entityType': type,
            'entityId': payload['id'],
            'operation': 'upsert',
            'payload': payload,
            'deviceId': deviceId,
            'originDeviceId': deviceId,
          });
        }
      }
      final tombstones = await db
          .customSelect(
            'SELECT entity_type, entity_id, updated_at, hlc_counter, device_id '
            'FROM sync_row_versions WHERE deleted = 1',
          )
          .get();
      for (final row in tombstones) {
        final type = row.read<String>('entity_type');
        final id = row.read<String>('entity_id');
        final isLive = liveIds[type]?.contains(id) ?? false;
        final schema = _schemas[type];
        if (schema == null || isLive) continue;
        final deviceId = row.readNullable<String>('device_id');
        changes.add({
          'entityType': type,
          'entityId': id,
          'operation': 'delete',
          'payload': {
            'id': id,
            schema.versionKey: row.read<int>('updated_at'),
            'hlc_counter': row.read<int>('hlc_counter'),
            'deleted': true,
            'fv': fieldOrigins['$type:$id'] ?? const {},
          },
          'deviceId': deviceId,
          'originDeviceId': deviceId,
        });
      }
      changes.sort(_compareSnapshotRows);
      return changes;
    });
  }

  /// Rank of a synced entity type in snapshot order. Unknown types sort last
  /// and are rejected as snapshot resume tokens by the server.
  static int snapshotTypeRank(String type) {
    final index = _schemaOrder.indexOf(type);
    return index < 0 ? _schemaOrder.length : index;
  }

  /// Whether [type] is a synced entity this version understands.
  static bool isSnapshotEntityType(String type) => _schemas.containsKey(type);

  /// Payload key that carries the row version for [type], or null when the
  /// entity is unknown to this build.
  static String? versionKeyFor(String type) => _schemas[type]?.versionKey;

  static final _schemaOrder = _schemas.keys.toList(growable: false);

  static const _fieldMergeTypes = <String>{
    'project',
    'event',
    'project_task',
    'habit',
    'todo',
  };

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
    SyncReceiptContext? receiptContext,
  }) async {
    var skipped = 0;
    final changed = <SyncChangedEntity>[];
    final rejected = <SyncRejectedChange>[];
    final receipts = <SyncChangeReceipt>[];
    // A previous batch that failed outside the per-change handlers must not
    // leak ids into this one.
    _republishPlanItems.clear();
    _republishTextRows.clear();
    _completionTasks.clear();
    await _db.transaction(() async {
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        for (var index = 0; index < changes.length; index++) {
          final change = changes[index];
          final type = change['entityType'] is String
              ? change['entityType'] as String
              : 'unknown';
          final id = change['entityId'] is String
              ? change['entityId'] as String
              : 'unknown';
          final operation = change['operation'] is String
              ? change['operation'] as String
              : 'unknown';
          final changeId = change['changeId'] is String
              ? change['changeId'] as String
              : null;
          final rawPayload = change['payload'];
          final schema = _schemas[type];
          final rawVersion = rawPayload is Map && schema != null
              ? rawPayload[schema.versionKey]
              : null;
          final revision = rawVersion is int ? rawVersion : null;
          final counter = rawPayload is Map && rawPayload['hlc_counter'] is int
              ? rawPayload['hlc_counter'] as int
              : 0;
          final payloadSha256 = rawPayload == null
              ? ''
              : sha256.convert(utf8.encode(jsonEncode(rawPayload))).toString();
          SyncChangeReceipt makeReceipt(String outcome, {String? reason}) =>
              SyncChangeReceipt(
                changeId: changeId,
                entityType: type,
                entityId: id,
                outcome: outcome,
                reason: reason,
                revision: revision,
                counter: counter,
                operation: operation,
              );

          // A receipt is bound to the exact identity and revision. A different
          // payload under the same change id is a protocol error, not a retry.
          if (receiptContext != null && changeId != null) {
            final prior = await _db
                .customSelect(
                  'SELECT payload_sha256, outcome, reason '
                  'FROM sync_change_receipts '
                  'WHERE peer_id = ? AND epoch = ? AND direction = ? '
                  'AND change_id = ?',
                  variables: [
                    Variable.withString(receiptContext.peerId),
                    Variable.withString(receiptContext.epoch),
                    Variable.withString(receiptContext.direction),
                    Variable.withString(changeId),
                  ],
                )
                .getSingleOrNull();
            if (prior != null) {
              if (prior.read<String>('payload_sha256') != payloadSha256) {
                final receipt = makeReceipt(
                  'rejected',
                  reason: 'change_id_conflict',
                );
                receipts.add(receipt);
                rejected.add((
                  type: type,
                  id: id,
                  reason: 'change_id_conflict',
                ));
                await _persistReceipt(receiptContext, change, receipt);
                continue;
              }
              final priorOutcome = prior.read<String>('outcome');
              if (priorOutcome != 'rejected') {
                final receipt = makeReceipt(
                  priorOutcome == 'applied' || priorOutcome == 'replay'
                      ? 'replay'
                      : priorOutcome,
                  reason: prior.readNullable<String>('reason'),
                );
                receipts.add(receipt);
                await _persistReceipt(receiptContext, change, receipt);
                continue;
              }
            }
          }

          final savepoint = 'locus_change_$index';
          await _db.customStatement('SAVEPOINT $savepoint');
          try {
            if (await _applyOne(change)) {
              changed.add((type: type, id: id, deleted: operation == 'delete'));
              if (type == 'todo_completion' &&
                  rawPayload is Map<String, dynamic> &&
                  rawPayload['todo_id'] is String) {
                _completionTasks.add(rawPayload['todo_id'] as String);
              }
              receipts.add(makeReceipt('applied'));
            } else {
              skipped++;
              final receipt = await _classifySkipped(
                change,
                type: type,
                id: id,
                operation: operation,
                changeId: changeId,
                revision: revision,
                counter: counter,
              );
              receipts.add(receipt);
              if (receipt.outcome == 'rejected' ||
                  receipt.outcome == 'unsupported') {
                rejected.add((type: type, id: id, reason: receipt.reason!));
              }
            }
            await _db.customStatement('RELEASE $savepoint');
          } on FormatException catch (error) {
            await _db.customStatement('ROLLBACK TO $savepoint');
            await _db.customStatement('RELEASE $savepoint');
            developer.log(
              'Skipping a malformed sync change',
              name: 'SyncChangeApplier',
              error: error,
            );
            rejected.add(_rejection(change, error.message));
            receipts.add(makeReceipt('rejected', reason: error.message));
          } on SqliteException catch (error, stackTrace) {
            await _db.customStatement('ROLLBACK TO $savepoint');
            await _db.customStatement('RELEASE $savepoint');
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
            receipts.add(
              makeReceipt('rejected', reason: 'could_not_be_applied'),
            );
          }
          if (receiptContext != null) {
            await _persistReceipt(
              receiptContext,
              change,
              receipts.last,
              cursor: change['cursor'] is int ? change['cursor'] as int : null,
            );
          }
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
      // Outbox capture is on again, so this update bumps the row's version and
      // queues it for the sender, which still holds the unmerged text.
      if (receiptContext != null) {
        await _persistExchangeSummary(receiptContext, receipts);
      }
      await _normalizeCompletedTasks();
      final republishedDiaryIds = _republish.toSet();
      for (final id in republishedDiaryIds) {
        await _db.customStatement(
          'UPDATE diary_entries SET content = content WHERE id = ?',
          [id],
        );
      }
      _republish.clear();

      // Items re-parented by a same-day plan clash are written again with
      // outbox capture on, so the sender learns their new plan.
      for (final id in _republishPlanItems) {
        await _db.customStatement(
          "UPDATE daily_plan_items SET plan_id = plan_id, "
          "updated_at = CAST(strftime('%s','now') AS INTEGER) WHERE id = ?",
          [id],
        );
      }
      _republishPlanItems.clear();

      // Merged notes and descriptions are re-saved with capture on, so both
      // the origin device and any other paired phone receive the merged text.
      for (final row in _republishTextRows) {
        final table = _schemas[row.type]!.table;
        await _db.customStatement('UPDATE $table SET id = id WHERE id = ?', [
          row.id,
        ]);
      }
      _republishTextRows.clear();

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
      receipts: receipts,
    );
  }

  /// Recomputes a recurring task's next due date from the canonical latest
  /// completion. This runs with outbox capture on so both peers converge even
  /// when they completed the same opposite offline occurrences.
  Future<void> _normalizeCompletedTasks() async {
    for (final taskId in _completionTasks) {
      try {
        final task = await _db.getTodoItem(taskId);
        if (task == null || task.completed) continue;
        final rule = task.recurrenceRule;
        final spec = RecurrenceSpec.tryParse(task.recurrenceSpec);
        if (!Recurrence.isRecurring(rule) && spec == null) continue;
        final rows = await _db
            .customSelect(
              'SELECT c.occurrence_due, c.completed_at, c.slot_kind, '
              'c.slot_date, c.slot_generation, v.updated_at, '
              'v.hlc_counter FROM todo_completions c '
              'LEFT JOIN sync_row_versions v '
              "ON v.entity_type = 'todo_completion' AND v.entity_id = c.id "
              'WHERE c.todo_id = ? ORDER BY COALESCE(v.updated_at, 0) DESC, '
              'COALESCE(v.hlc_counter, 0) DESC LIMIT 1',
              variables: [Variable.withString(taskId)],
            )
            .getSingleOrNull();
        if (rows == null) continue;
        final dueSeconds = rows.readNullable<int>('occurrence_due');
        final completedSeconds = rows.read<int>('completed_at');
        final slotKind =
            rows.readNullable<String>('slot_kind') ?? 'legacy_instant';
        final slotGeneration = rows.readNullable<String>('slot_generation');
        final due = dueSeconds == null
            ? task.dueDate
            : DateTime.fromMillisecondsSinceEpoch(dueSeconds * 1000);
        final completedAt = DateTime.fromMillisecondsSinceEpoch(
          completedSeconds * 1000,
        );
        DateTime? next;
        if (spec?.isAfterCompletion == true) {
          next = spec!.nextAfterCompletion(due, completedAt);
        } else if (due != null && Recurrence.isRecurring(rule)) {
          final pivot = due.isAfter(completedAt) ? due : completedAt;
          next = Recurrence.next(due, rule, from: pivot);
        }
        if (next == null || task.dueDate == next) continue;
        final shift = task.dueDate == null
            ? Duration.zero
            : next.difference(task.dueDate!);
        final reminder = task.reminderAt?.add(shift);
        final reminderSeconds = reminder == null
            ? null
            : reminder.millisecondsSinceEpoch ~/ 1000;
        final nextKind = slotKind == 'date_only'
            ? 'date_only'
            : slotKind == 'undated'
            ? 'undated'
            : slotKind == 'instant'
            ? 'instant'
            : 'legacy_instant';
        final nextDate = nextKind == 'date_only'
            ? CompletionSlot.civilDateKey(next)
            : null;
        final nextGeneration = nextKind == 'undated'
            ? CompletionSlot.newGeneration()
            : slotGeneration;
        await _db.customStatement(
          'UPDATE todo_items SET due_date = ?, reminder_at = ?, '
          'due_kind = ?, due_date_key = ?, undated_generation = ? '
          'WHERE id = ?',
          [
            next.millisecondsSinceEpoch ~/ 1000,
            reminderSeconds,
            nextKind,
            nextDate,
            nextGeneration,
            taskId,
          ],
        );
      } catch (_) {
        // History normalization is best-effort; the completion itself is
        // already durable and must not be rolled back.
      }
    }
    _completionTasks.clear();
  }

  Future<SyncChangeReceipt> _classifySkipped(
    Map<String, dynamic> change, {
    required String type,
    required String id,
    required String operation,
    required String? changeId,
    required int? revision,
    required int counter,
  }) async {
    SyncChangeReceipt receipt(String outcome, {String? reason}) =>
        SyncChangeReceipt(
          changeId: changeId,
          entityType: type,
          entityId: id,
          outcome: outcome,
          reason: reason,
          revision: revision,
          counter: counter,
          operation: operation,
        );

    if (!_schemas.containsKey(type)) {
      return receipt('unsupported', reason: 'unsupported_entity');
    }
    final schema = _schemas[type]!;
    final payload = change['payload'];
    if (payload is! Map<String, dynamic>) {
      return receipt('rejected', reason: 'invalid_payload');
    }
    final local = await _localVersion(type, id);
    if (local == null) {
      // A dependency is missing. This is a repairable rejection, not a
      // supersession: the exact revision is retained for automatic retry.
      return receipt('rejected', reason: 'missing_parent');
    }
    final rawVersion = payload[schema.versionKey];
    final version = rawVersion is int
        ? _clampIncomingVersion(rawVersion)
        : null;
    final incomingCounter = payload['hlc_counter'] is int
        ? payload['hlc_counter'] as int
        : 0;
    final origin = change['originDeviceId'] ?? change['deviceId'];
    final originText = origin is String ? origin : null;
    if (version != null &&
        version == local.updatedAt &&
        incomingCounter == local.counter &&
        (originText ?? '') == (local.deviceId ?? '')) {
      return receipt('replay');
    }
    if (local.deleted && operation == 'upsert') {
      return receipt('superseded', reason: 'newer_deletion');
    }
    if (version != null &&
        !_incomingWins(version, incomingCounter, originText, local)) {
      return receipt('superseded');
    }
    return receipt('rejected', reason: 'missing_parent');
  }

  Future<void> _persistExchangeSummary(
    SyncReceiptContext context,
    List<SyncChangeReceipt> receipts,
  ) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    final needsAttention =
        receipts.isEmpty ||
        receipts.any(
          (receipt) =>
              receipt.outcome == 'rejected' || receipt.outcome == 'unsupported',
        );
    await _db.customStatement(
      'UPDATE sync_peer_progress SET error_code = ? '
      'WHERE peer_id = ? AND epoch = ? AND direction = ?',
      [
        needsAttention ? 'changes_need_attention' : null,
        context.peerId,
        context.epoch,
        context.direction,
      ],
    );
    await _db.customStatement(
      'INSERT INTO sync_peer_exchange '
      '(peer_id, epoch, last_attempt_ms) VALUES (?, ?, ?) '
      'ON CONFLICT(peer_id, epoch) DO UPDATE SET '
      'last_attempt_ms = excluded.last_attempt_ms',
      [context.peerId, context.epoch, now],
    );
  }

  Future<void> _persistReceipt(
    SyncReceiptContext context,
    Map<String, dynamic> change,
    SyncChangeReceipt receipt, {
    int? cursor,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    final needsAttention =
        receipt.outcome == 'rejected' || receipt.outcome == 'unsupported';
    final payloadSha256 = sha256
        .convert(utf8.encode(jsonEncode(change['payload'])))
        .toString();
    await _db.customStatement(
      'INSERT INTO sync_peer_progress '
      '(peer_id, epoch, direction, cursor, last_attempt_ms, '
      'last_exchange_ms, error_code) '
      'VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(peer_id, epoch, direction) DO UPDATE SET '
      'cursor = excluded.cursor, '
      'last_attempt_ms = excluded.last_attempt_ms, '
      'last_exchange_ms = excluded.last_exchange_ms, '
      'error_code = COALESCE(sync_peer_progress.error_code, '
      'excluded.error_code)',
      [
        context.peerId,
        context.epoch,
        context.direction,
        cursor ?? 0,
        now,
        now,
        needsAttention ? 'changes_need_attention' : null,
      ],
    );
    await _db.customStatement(
      'INSERT INTO sync_peer_exchange '
      '(peer_id, epoch, last_attempt_ms) VALUES (?, ?, ?) '
      'ON CONFLICT(peer_id, epoch) DO UPDATE SET '
      'last_attempt_ms = excluded.last_attempt_ms',
      [context.peerId, context.epoch, now],
    );
    final changeId = receipt.changeId;
    if (changeId == null) return;
    await _db.customStatement(
      'INSERT INTO sync_change_receipts '
      '(peer_id, epoch, direction, change_id, entity_type, entity_id, '
      'payload_sha256, revision, counter, operation, outcome, reason, '
      'capability_version, first_seen_ms, last_seen_ms) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(peer_id, epoch, direction, change_id) DO UPDATE SET '
      'outcome = excluded.outcome, reason = excluded.reason, '
      'entity_type = COALESCE(excluded.entity_type, '
      'sync_change_receipts.entity_type), '
      'entity_id = COALESCE(excluded.entity_id, '
      'sync_change_receipts.entity_id), '
      'capability_version = COALESCE(excluded.capability_version, '
      'sync_change_receipts.capability_version), '
      'last_seen_ms = excluded.last_seen_ms',
      [
        context.peerId,
        context.epoch,
        context.direction,
        changeId,
        receipt.entityType,
        receipt.entityId,
        payloadSha256,
        receipt.revision,
        receipt.counter,
        receipt.operation,
        receipt.outcome,
        receipt.reason,
        receipt.outcome == 'unsupported'
            ? SyncReceiptStore.currentCapabilityVersion
            : null,
        now,
        now,
      ],
    );
    if (needsAttention) {
      await _db.customStatement(
        'INSERT INTO sync_rejected_changes '
        '(peer_id, epoch, direction, change_id, entity_type, entity_id, '
        'operation, payload_json, reason_code, attempts, first_seen_ms, '
        'last_seen_ms, resolved_ms, last_attempt_ms, payload_sha256) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL, ?, ?) '
        'ON CONFLICT(peer_id, epoch, direction, change_id) DO UPDATE SET '
        'attempts = sync_rejected_changes.attempts + 1, '
        'last_seen_ms = excluded.last_seen_ms, '
        'last_attempt_ms = excluded.last_attempt_ms, '
        'reason_code = excluded.reason_code, '
        'resolved_ms = NULL',
        [
          context.peerId,
          context.epoch,
          context.direction,
          changeId,
          receipt.entityType,
          receipt.entityId,
          change['operation'] is String ? change['operation'] : 'unknown',
          jsonEncode(change),
          receipt.reason ?? 'rejected',
          now,
          now,
          now,
          payloadSha256,
        ],
      );
    } else {
      // A successful retry, a confirmed newer repair or an explicit user
      // discard is the only way an open repair becomes resolved.
      await _db.customStatement(
        'UPDATE sync_rejected_changes SET resolved_ms = ?, '
        'resolution_kind = ?, last_attempt_ms = ? '
        'WHERE peer_id = ? AND epoch = ? AND direction = ? '
        'AND change_id = ? AND resolved_ms IS NULL',
        [
          now,
          receipt.outcome,
          now,
          context.peerId,
          context.epoch,
          context.direction,
          changeId,
        ],
      );
    }
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
            'SELECT updated_at, hlc_counter, device_id, deleted '
            'FROM sync_row_versions '
            'WHERE entity_type = ? AND entity_id = ?',
            variables: [
              Variable.withString(entity.type),
              Variable.withString(entity.id),
            ],
          )
          .get();
      if (versions.isEmpty) continue;
      final version = versions.first.read<int>('updated_at');
      final counter = versions.first.read<int>('hlc_counter');
      final writer = versions.first.readNullable<String>('device_id');
      final deleted = versions.first.read<int>('deleted') == 1;
      final operation = deleted ? 'delete' : 'upsert';
      Map<String, dynamic> payload;
      if (deleted) {
        payload = {
          'id': entity.id,
          schema.versionKey: version,
          'hlc_counter': counter,
          'deleted': true,
          'originDeviceId': writer,
        };
      } else {
        final rows = await _db
            .customSelect(
              'SELECT ${schema.columns.join(', ')} FROM ${schema.table} WHERE id = ?',
              variables: [Variable.withString(entity.id)],
            )
            .get();
        if (rows.isEmpty) continue;
        final fieldRows = await _db
            .customSelect(
              'SELECT field, updated_at, hlc_counter, device_id '
              'FROM sync_field_versions WHERE entity_type = ? AND entity_id = ?',
              variables: [
                Variable.withString(entity.type),
                Variable.withString(entity.id),
              ],
            )
            .get();
        final fieldOrigins = <String, List<Object?>>{
          for (final row in fieldRows)
            row.read<String>('field'): [
              row.read<int>('updated_at'),
              row.read<int>('hlc_counter'),
              row.readNullable<String>('device_id'),
            ],
        };
        payload = Map<String, dynamic>.from(rows.first.data)
          ..[schema.versionKey] = version
          ..['hlc_counter'] = counter
          ..['deleted'] = false
          ..['fv'] = fieldOrigins
          ..['originDeviceId'] = writer;
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
        tables.addAll(const [
          'tasks',
          'progress_logs',
          'focus_sessions',
          'project_statuses',
          'project_milestones',
          'task_dependencies',
        ]);
      }
      if (entity.type == 'habit' && entity.deleted) {
        tables.add('habit_logs');
      }
      if (entity.type == 'todo' && entity.deleted) {
        tables.add('todo_completions');
        tables.add('task_schedule_blocks');
        tables.add('attachments');
      }
      if (entity.type == 'event' && entity.deleted) {
        tables.add('attachments');
      }
      if (entity.type == 'project_task' && entity.deleted) {
        tables.add('task_schedule_blocks');
        tables.add('task_dependencies');
      }
      if (entity.type == 'daily_plan') {
        // An upsert can delete a losing same-day plan, whose items are moved to
        // the winner; both tables changed even though the plan row survived.
        tables.add('daily_plan_items');
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
    'habits' => _db.habits,
    'habit_logs' => _db.habitLogs,
    'todo_items' => _db.todoItems,
    'todo_completions' => _db.todoCompletions,
    'diary_entries' => _db.diaryEntries,
    'daily_plans' => _db.dailyPlans,
    'daily_plan_items' => _db.dailyPlanItems,
    'task_schedule_blocks' => _db.taskScheduleBlocks,
    'project_statuses' => _db.projectStatuses,
    'project_milestones' => _db.projectMilestones,
    'task_dependencies' => _db.taskDependencies,
    'saved_filters' => _db.savedFilters,
    'planning_preferences' => _db.planningPreferences,
    'working_hours' => _db.workingHours,
    'working_breaks' => _db.workingBreaks,
    'attachments' => _db.attachments,
    'progress_logs' => _db.progressLogs,
    'focus_sessions' => _db.focusSessions,
    _ => throw ArgumentError.value(name, 'name', 'Unknown synced table'),
  };

  Future<bool> _applyFieldMerge({
    required String type,
    required String id,
    required ({
      String table,
      List<String> columns,
      Map<String, Object?> defaults,
      String versionKey,
    })
    schema,
    required Map<String, dynamic> payload,
    required Map<String, dynamic> fieldVersions,
    required int incomingVersion,
    required int incomingCounter,
    required String? incomingDevice,
    required _LocalVersion? local,
    required bool revivingDeleted,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT ${schema.columns.join(', ')} FROM ${schema.table} '
          'WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    final localRow = rows.isEmpty ? null : rows.first.data;

    final localFields = <String, _LocalVersion>{};
    final fieldRows = await _db
        .customSelect(
          'SELECT field, updated_at, hlc_counter, device_id '
          'FROM sync_field_versions WHERE entity_type = ? AND entity_id = ?',
          variables: [Variable.withString(type), Variable.withString(id)],
        )
        .get();
    for (final row in fieldRows) {
      localFields[row.read<String>('field')] = _LocalVersion(
        row.read<int>('updated_at'),
        row.read<int>('hlc_counter'),
        row.readNullable<String>('device_id'),
      );
    }

    final updates = <String, Object?>{};
    final winning = <String, _LocalVersion>{};
    final conflicts =
        <
          ({String field, Object? loser, int wall, int winner, String? device})
        >[];

    for (final column in schema.columns) {
      if (column == 'id') continue;
      if (!payload.containsKey(column) &&
          !schema.defaults.containsKey(column)) {
        continue;
      }
      final raw = payload.containsKey(column)
          ? payload[column]
          : schema.defaults[column];
      if (raw != null &&
          raw is! String &&
          raw is! int &&
          raw is! double &&
          raw is! bool) {
        throw const FormatException('Invalid payload value');
      }
      final remoteValue = raw is bool ? (raw ? 1 : 0) : raw;

      var remoteWall = incomingVersion;
      var remoteCounter = incomingCounter;
      var remoteDevice = incomingDevice;
      final fieldVersion = fieldVersions[column];
      if (fieldVersion is List &&
          fieldVersion.length >= 2 &&
          fieldVersion[0] is int &&
          fieldVersion[1] is int) {
        remoteWall = _clampIncomingVersion(fieldVersion[0] as int);
        remoteCounter = fieldVersion[1] as int;
        // field-origins-v2 carries the original writer. A legacy two-element
        // tuple uses the row origin supplied by the trusted transport path.
        if (fieldVersion.length >= 3 &&
            fieldVersion[2] is String &&
            (fieldVersion[2] as String).isNotEmpty) {
          remoteDevice = fieldVersion[2] as String;
        }
      }
      final localField = localFields[column] ?? local;
      final wins =
          localRow == null ||
          localField == null ||
          _incomingWins(remoteWall, remoteCounter, remoteDevice, localField);
      if (wins) {
        updates[column] = remoteValue;
        winning[column] = _LocalVersion(
          remoteWall,
          remoteCounter,
          remoteDevice,
        );
      } else if (!_valuesEqual(localRow[column], remoteValue)) {
        conflicts.add((
          field: column,
          loser: remoteValue,
          wall: remoteWall,
          winner: localField.updatedAt,
          device: remoteDevice,
        ));
      }
    }

    // The legacy rule and the richer spec are one logical schedule. Compare
    // the pair with the pair's field versions so a peer cannot replace one
    // half and leave an inconsistent combination.
    if (type == 'event' || type == 'todo') {
      final localSpec = localRow?['recurrence_spec'];
      if (localSpec is String &&
          localSpec.isNotEmpty &&
          !payload.containsKey('recurrence_spec')) {
        // An older peer cannot carry the richer half. Keep the local pair
        // intact rather than writing an inconsistent schedule.
        updates.remove('recurrence_rule');
        updates.remove('recurrence_spec');
        winning.remove('recurrence_rule');
        winning.remove('recurrence_spec');
      } else {
        final incomingPair = [
          fieldVersions['recurrence_rule'],
          fieldVersions['recurrence_spec'],
        ].whereType<List>().toList();
        final localPair = [
          localFields['recurrence_rule'],
          localFields['recurrence_spec'],
        ].whereType<_LocalVersion>().toList();
        var incomingWall = incomingVersion;
        var incomingPairCounter = incomingCounter;
        var incomingPairDevice = incomingDevice;
        for (final value in incomingPair) {
          if (value.length >= 2 &&
              value[0] is int &&
              value[1] is int &&
              (value[0] as int) >= incomingWall) {
            incomingWall = _clampIncomingVersion(value[0] as int);
            incomingPairCounter = value[1] as int;
            if (value.length >= 3 && value[2] is String) {
              incomingPairDevice = value[2] as String;
            }
          }
        }
        _LocalVersion? localPairVersion;
        for (final value in localPair) {
          if (localPairVersion == null ||
              value.updatedAt > localPairVersion.updatedAt ||
              (value.updatedAt == localPairVersion.updatedAt &&
                  value.counter > localPairVersion.counter)) {
            localPairVersion = value;
          }
        }
        final pairWins =
            localRow == null ||
            localPairVersion == null ||
            _incomingWins(
              incomingWall,
              incomingPairCounter,
              incomingPairDevice,
              localPairVersion,
            );
        if (pairWins) {
          updates['recurrence_rule'] = payload['recurrence_rule'];
          updates['recurrence_spec'] = payload['recurrence_spec'];
          winning['recurrence_rule'] = _LocalVersion(
            incomingWall,
            incomingPairCounter,
            incomingPairDevice,
          );
          winning['recurrence_spec'] = _LocalVersion(
            incomingWall,
            incomingPairCounter,
            incomingPairDevice,
          );
        } else {
          updates.remove('recurrence_rule');
          updates.remove('recurrence_spec');
          winning.remove('recurrence_rule');
          winning.remove('recurrence_spec');
        }
      }
    }

    if (localRow == null) {
      if (revivingDeleted) {
        // Undo may only recreate a fully supplied row with valid parents.
        final complete = schema.columns.every(
          (column) => column == 'id' || payload.containsKey(column),
        );
        if (!complete || !await _revivalParentsValid(type, payload)) {
          return false;
        }
      }
      final values = schema.columns.map((column) {
        if (column == 'id') return id;
        if (!payload.containsKey(column)) {
          if (schema.defaults.containsKey(column)) {
            return schema.defaults[column];
          }
          throw const FormatException('Missing payload field');
        }
        final value = payload[column];
        if (value is bool) return value ? 1 : 0;
        if (value == null ||
            value is String ||
            value is int ||
            value is double) {
          return value;
        }
        throw const FormatException('Invalid payload value');
      }).toList();
      await _db.customStatement(
        'INSERT OR REPLACE INTO ${schema.table} '
        '(${schema.columns.join(', ')}) '
        'VALUES (${List.filled(schema.columns.length, '?').join(', ')})',
        values,
      );
      var rowWall = incomingVersion;
      var rowCounter = incomingCounter;
      var rowDevice = incomingDevice;
      for (final column in schema.columns) {
        if (column == 'id') continue;
        final version =
            winning[column] ??
            _LocalVersion(incomingVersion, incomingCounter, incomingDevice);
        await _writeFieldVersion(type, id, column, version);
        if (version.updatedAt > rowWall ||
            (version.updatedAt == rowWall && version.counter > rowCounter)) {
          rowWall = version.updatedAt;
          rowCounter = version.counter;
          rowDevice = version.deviceId;
        }
      }
      await _recordVersion(
        type,
        id,
        rowWall,
        rowDevice,
        local,
        incomingCounter: rowCounter,
        deleted: false,
      );
      return true;
    }

    if (updates.isEmpty) {
      // The row-level version lost, but a rich text field may still contain
      // new text from the peer. Fold it into the winning local value so the
      // field merge cannot silently discard it.
      if ((type == 'todo' || type == 'event') &&
          await _mergeLosingText(type, id, payload)) {
        _republishTextRows.add((type: type, id: id));
        return true;
      }
      return false;
    }

    // Preserve rich note text even when the other fields merge independently.
    if ((type == 'todo' || type == 'event') &&
        updates.containsKey(_textColumn(type))) {
      final column = _textColumn(type);
      final localText = localRow[column];
      final merged = updates[column];
      if (localText is String &&
          merged is String &&
          localText.trim().isNotEmpty &&
          merged.trim().isNotEmpty &&
          localText != merged) {
        updates[column] = mergeDiaryContent(merged, localText);
        _republishTextRows.add((type: type, id: id));
      }
    } else if (type == 'todo' || type == 'event') {
      if (await _mergeLosingText(type, id, payload)) {
        _republishTextRows.add((type: type, id: id));
      }
    }

    final assignments = updates.keys.map((column) => '$column = ?').join(', ');
    await _db.customStatement(
      'UPDATE ${schema.table} SET $assignments WHERE id = ?',
      [...updates.values, id],
    );
    for (final entry in winning.entries) {
      await _writeFieldVersion(type, id, entry.key, entry.value);
    }

    var rowWall = local?.updatedAt ?? 0;
    var rowCounter = local?.counter ?? 0;
    var rowDevice = local?.deviceId;
    if (incomingVersion > rowWall ||
        (incomingVersion == rowWall && incomingCounter > rowCounter)) {
      rowWall = incomingVersion;
      rowCounter = incomingCounter;
      rowDevice = incomingDevice;
    }
    for (final version in winning.values) {
      if (version.updatedAt > rowWall ||
          (version.updatedAt == rowWall && version.counter > rowCounter)) {
        rowWall = version.updatedAt;
        rowCounter = version.counter;
        rowDevice = version.deviceId;
      }
    }
    await _recordVersion(
      type,
      id,
      rowWall,
      rowDevice,
      local,
      incomingCounter: rowCounter,
      deleted: false,
    );

    for (final conflict in conflicts) {
      await _recordConflict(
        type: type,
        id: id,
        field: conflict.field,
        kind: 'field',
        loserValue: conflict.loser,
        loserDevice: conflict.device,
        loserWall: conflict.wall,
        winnerWall: conflict.winner,
      );
    }
    return true;
  }

  Future<void> _writeFieldVersion(
    String type,
    String id,
    String field,
    _LocalVersion version,
  ) async {
    await _db.customStatement(
      'INSERT INTO sync_field_versions '
      '(entity_type, entity_id, field, updated_at, hlc_counter, device_id) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id, field) DO UPDATE SET '
      'updated_at = excluded.updated_at, '
      'hlc_counter = excluded.hlc_counter, '
      'device_id = excluded.device_id',
      [type, id, field, version.updatedAt, version.counter, version.deviceId],
    );
  }

  Future<void> _recordConflict({
    required String type,
    required String id,
    required String field,
    required String kind,
    required Object? loserValue,
    required String? loserDevice,
    required int loserWall,
    required int winnerWall,
  }) async {
    await _db.customStatement(
      'INSERT INTO sync_conflicts '
      '(entity_type, entity_id, field, kind, loser_value, loser_device, '
      'loser_wall, winner_wall, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        type,
        id,
        field,
        kind,
        loserValue == null ? null : jsonEncode(loserValue),
        loserDevice,
        loserWall,
        winnerWall,
        AppClock.now().millisecondsSinceEpoch,
      ],
    );
  }

  static bool _valuesEqual(Object? a, Object? b) =>
      (a is bool ? (a ? 1 : 0) : a) == (b is bool ? (b ? 1 : 0) : b);

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

    final rawVersion = payload[schema.versionKey];
    final incomingVersion = rawVersion is int ? rawVersion : null;
    final rawDevice = change['deviceId'];
    final incomingDevice = rawDevice is String ? rawDevice : null;
    // The authenticated transport sender is not necessarily the author of a
    // relayed change. Origin travels separately and falls back to the sender.
    final rawOrigin = change['originDeviceId'];
    final incomingOrigin = rawOrigin is String && rawOrigin.isNotEmpty
        ? rawOrigin
        : incomingDevice;
    final rawCounter = payload['hlc_counter'];
    final incomingCounter = rawCounter is int ? rawCounter : 0;
    final local = await _localVersion(type, id);
    final localDeleted = local?.deleted ?? false;
    final clampedVersion = incomingVersion == null
        ? null
        : _clampIncomingVersion(incomingVersion);
    if (clampedVersion != null && local != null) {
      await _advanceClock(
        clampedVersion,
        incomingCounter,
        local.updatedAt,
        local.counter,
      );
    }

    // A retained tombstone is a versioned record. A legacy unversioned upsert
    // can never revive it; a strictly newer, complete upsert may (Undo).
    if (localDeleted && operation == 'upsert') {
      if (clampedVersion == null ||
          local == null ||
          !_incomingWins(
            clampedVersion,
            incomingCounter,
            incomingOrigin,
            local,
          )) {
        return false;
      }
    }

    // Per-field merge must run before the row-level short circuit: the losing
    // row version may still carry newer values for individual fields.
    final fv = payload['fv'];
    if (operation == 'upsert' &&
        fv is Map<String, dynamic> &&
        _fieldMergeTypes.contains(type) &&
        clampedVersion != null &&
        (fv.isNotEmpty || local == null)) {
      return _applyFieldMerge(
        type: type,
        id: id,
        schema: schema,
        payload: payload,
        fieldVersions: fv,
        incomingVersion: clampedVersion,
        incomingCounter: incomingCounter,
        incomingDevice: incomingOrigin,
        local: local,
        revivingDeleted: localDeleted,
      );
    }

    final identicalTuple =
        clampedVersion != null &&
        local != null &&
        clampedVersion == local.updatedAt &&
        incomingCounter == local.counter &&
        (incomingOrigin ?? '') == (local.deviceId ?? '');
    if (identicalTuple && operation == 'upsert') {
      // An identical operation and version is a replay, not a new edit.
      return false;
    }
    if (!identicalTuple &&
        clampedVersion != null &&
        local != null &&
        !_incomingWins(
          clampedVersion,
          incomingCounter,
          incomingOrigin,
          local,
        )) {
      // Rich notes are one text value, so a plain last-writer-wins would drop
      // the losing side. Fold it into the winning local text under the same
      // deterministic divider the diary uses, then republish the result.
      if (operation == 'upsert' &&
          _isMergeableTextType(type) &&
          await _mergeLosingText(type, id, payload)) {
        _republishTextRows.add((type: type, id: id));
        return true;
      }
      return false;
    }

    if (operation == 'delete') {
      var deleteId = id;
      if (type == 'todo_completion') {
        final alias = await _db
            .customSelect(
              'SELECT canonical_id FROM todo_completion_aliases '
              'WHERE alias_id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingleOrNull();
        if (alias != null) deleteId = alias.read<String>('canonical_id');
      }
      await _db.customStatement('DELETE FROM ${schema.table} WHERE id = ?', [
        deleteId,
      ]);
      if (type == 'todo_completion') {
        await _db.customStatement(
          'DELETE FROM todo_completion_aliases '
          'WHERE alias_id = ? OR canonical_id = ?',
          [id, deleteId],
        );
      }
      await _recordVersion(
        type,
        id,
        clampedVersion,
        incomingOrigin,
        local,
        incomingCounter: incomingCounter,
        deleted: true,
      );
      return true;
    }

    final localSlotValues =
        type == 'todo' && schema.columns.contains('due_kind')
        ? await _db
              .customSelect(
                'SELECT due_kind, due_date_key, undated_generation '
                'FROM todo_items WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull()
        : null;

    final values = schema.columns.map((column) {
      if (!payload.containsKey(column)) {
        if (localSlotValues != null &&
            (column == 'due_kind' ||
                column == 'due_date_key' ||
                column == 'undated_generation')) {
          // An older peer does not represent these fields. Its unrelated edit
          // must not erase the local portable-slot semantics.
          return localSlotValues.data[column];
        }
        if (schema.defaults.containsKey(column)) {
          return schema.defaults[column];
        }
        throw const FormatException('Missing payload field');
      }
      final value = payload[column];
      if (value == null || value is String || value is int || value is double) {
        return value;
      }
      if (value is bool) return value ? 1 : 0;
      throw const FormatException('Invalid payload value');
    }).toList();

    // A future peer may introduce another note format. Keep its text visible
    // as plain text instead of rejecting the whole change.
    if (type == 'todo' || type == 'event') {
      final formatIndex = schema.columns.indexOf(_formatColumn(type));
      final format = values[formatIndex];
      values[formatIndex] = format == 'md1' ? 'md1' : 'plain';
      // The incoming text won the version comparison. Preserve any different
      // local text by appending it to the winner before the row is written.
      if (operation == 'upsert' &&
          await _foldLocalTextIntoIncoming(type, id, values, schema.columns)) {
        _republishTextRows.add((type: type, id: id));
      }
    }

    if (type == 'attachment') {
      final todo = payload['todo_id'];
      final event = payload['event_id'];
      if ((todo is String) == (event is String)) {
        throw const FormatException(
          'An attachment must belong to exactly one parent',
        );
      }
      final kind = payload['kind'];
      if (kind != 'file' && kind != 'image') {
        throw const FormatException('Invalid attachment kind');
      }
      final sha = payload['sha256'];
      if (sha is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
        throw const FormatException('Invalid attachment hash');
      }
      final size = payload['size_bytes'];
      if (size is! int || size < 0) {
        throw const FormatException('Invalid attachment size');
      }
      final name = payload['display_name'];
      if (name is! String || name.trim().isEmpty || name.length > 200) {
        throw const FormatException('Invalid attachment name');
      }
      final mime = payload['mime_type'];
      if (mime is! String || mime.isEmpty || mime.length > 120) {
        throw const FormatException('Invalid attachment media type');
      }
      final altText = payload['alt_text'];
      if (altText != null && (altText is! String || altText.length > 500)) {
        throw const FormatException('Invalid attachment alt text');
      }
      for (final dimension in const ['width', 'height']) {
        final value = payload[dimension];
        if (value != null && (value is! int || value <= 0)) {
          throw const FormatException('Invalid attachment dimensions');
        }
      }
      if (todo is String && !(await _rowExists('todo_items', todo))) {
        return false;
      }
      if (event is String && !(await _rowExists('events', event))) {
        return false;
      }
    }

    if (type == 'project_task') {
      final statusIndex = schema.columns.indexOf('status_key');
      final completedIndex = schema.columns.indexOf('completed');
      final startIndex = schema.columns.indexOf('start_date');
      final dueIndex = schema.columns.indexOf('due_date');
      final estimateIndex = schema.columns.indexOf('estimated_minutes');
      final priorityIndex = schema.columns.indexOf('priority');
      final rawKey = payload['status_key'];
      final completedFlag = values[completedIndex] == 1;
      final key = rawKey is String && ProjectStatusCatalog.contains(rawKey)
          ? rawKey
          : (completedFlag
                ? ProjectStatusCatalog.done.key
                : ProjectStatusCatalog.todo.key);
      values[statusIndex] = key;
      values[completedIndex] = ProjectStatusCatalog.isDoneKey(key) ? 1 : 0;
      final start = values[startIndex];
      final due = values[dueIndex];
      if (start is int && due is int && start > due) {
        throw const FormatException('Task start date is after its due date');
      }
      final estimate = values[estimateIndex];
      if (estimate is int && (estimate < 1 || estimate > 525600)) {
        throw const FormatException('Task estimate is out of range');
      }
      final priority = values[priorityIndex];
      if (priority is int && (priority < 0 || priority > 3)) {
        throw const FormatException('Task priority is out of range');
      }
    }
    if (type == 'project_status') {
      final keyIndex = schema.columns.indexOf('status_key');
      final nameIndex = schema.columns.indexOf('name');
      final colorIndex = schema.columns.indexOf('color_token');
      final doneIndex = schema.columns.indexOf('is_done');
      final rawKey = values[keyIndex];
      final name = values[nameIndex];
      if (rawKey is! String || !ProjectStatusCatalog.contains(rawKey)) {
        throw const FormatException('Unknown project status key');
      }
      if (name is! String || name.trim().isEmpty || name.length > 40) {
        throw const FormatException('Invalid project status name');
      }
      final color = values[colorIndex];
      if (color is! String ||
          !ProjectStatusCatalog.colorTokens.contains(color)) {
        throw const FormatException('Invalid project status colour');
      }
      values[doneIndex] = ProjectStatusCatalog.isDoneKey(rawKey) ? 1 : 0;
    }
    if (type == 'project_status' || type == 'project_milestone') {
      final projectId = payload['project_id'];
      if (projectId is! String) {
        throw const FormatException('Invalid project reference');
      }
      if (!(await _rowExists('projects', projectId))) return false;
    }
    if (type == 'project_milestone') {
      final title = payload['title'];
      if (title is! String || title.trim().isEmpty) {
        throw const FormatException('Invalid milestone title');
      }
    }
    if (type == 'task_dependency') {
      final predecessor = payload['predecessor_task_id'];
      final successor = payload['successor_task_id'];
      if (predecessor is! String || successor is! String) {
        throw const FormatException('Invalid dependency endpoints');
      }
      if (predecessor == successor) {
        throw const FormatException('A task cannot depend on itself');
      }
      final endpoints = await _db
          .customSelect(
            'SELECT id, project_id FROM tasks WHERE id IN (?, ?)',
            variables: [
              Variable.withString(predecessor),
              Variable.withString(successor),
            ],
          )
          .get();
      final projects = {
        for (final row in endpoints)
          row.read<String>('id'): row.read<String>('project_id'),
      };
      if (!projects.containsKey(predecessor) ||
          !projects.containsKey(successor)) {
        throw const FormatException(
          'Dependency endpoint task is missing; keeping it rejected for a '
          'later resync.',
        );
      }
      if (projects[predecessor] != projects[successor]) {
        throw const FormatException('Dependencies cannot cross projects');
      }
      final edges = await _db
          .customSelect(
            'SELECT predecessor_task_id, successor_task_id '
            'FROM task_dependencies',
          )
          .get();
      final adjacency = <String, List<String>>{};
      for (final row in edges) {
        adjacency
            .putIfAbsent(row.read<String>('predecessor_task_id'), () => [])
            .add(row.read<String>('successor_task_id'));
      }
      final stack = <String>[successor];
      final seen = <String>{};
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (current == predecessor) {
          throw const FormatException(
            'Dependency would create a cycle; the change was rejected.',
          );
        }
        if (!seen.add(current)) continue;
        stack.addAll(adjacency[current] ?? const []);
      }
    }
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
    if (type == 'habit_log') {
      // A habit can be deleted on the other device before its log arrives.
      final parent = payload['habit_id'];
      if (parent is! String) {
        throw const FormatException('Invalid habit log habit');
      }
      final parentRows = await _db
          .customSelect(
            'SELECT 1 AS present FROM habits WHERE id = ?',
            variables: [Variable.withString(parent)],
          )
          .get();
      if (parentRows.isEmpty) return false;

      // habit_logs is unique on (habit_id, date). A tick on both devices while
      // offline creates two ids for one fact; the lowest id wins on every
      // device so they converge without coordination. The losing local row is
      // deleted with outbox capture suppressed, so no tombstone is sent for
      // it. The surviving row is the one the other device also keeps.
      final date = payload['date'];
      if (date is! int) {
        throw const FormatException('Invalid habit log date');
      }
      final clash = await _db
          .customSelect(
            'SELECT id FROM habit_logs '
            'WHERE habit_id = ? AND date = ? AND id != ?',
            variables: [
              Variable.withString(parent),
              Variable.withInt(date),
              Variable.withString(id),
            ],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        if (localId.compareTo(id) < 0) return false;
        await _db.customStatement('DELETE FROM habit_logs WHERE id = ?', [
          localId,
        ]);
      }
    }
    if (type == 'todo_completion') {
      // A completion for a to-do that has been deleted here cannot be linked.
      // Deleting a to-do cascades its completions, so the tombstone wins.
      final parent = payload['todo_id'];
      if (parent is! String) {
        throw const FormatException('Invalid completion todo');
      }
      if (!(await _rowExists('todo_items', parent))) return false;
      final occurrenceKey = payload['occurrence_key'];
      if (occurrenceKey is String && occurrenceKey.isNotEmpty) {
        final existing = await _db
            .customSelect(
              'SELECT id FROM todo_completions '
              'WHERE todo_id = ? AND occurrence_key = ? AND id != ?',
              variables: [
                Variable.withString(parent),
                Variable.withString(occurrenceKey),
                Variable.withString(id),
              ],
            )
            .getSingleOrNull();
        if (existing != null) {
          // One canonical completion per occurrence. Persist a proven alias so
          // a later replay or deletion of the legacy id reaches the survivor.
          final canonicalId = existing.read<String>('id');
          await _db.customStatement(
            'INSERT OR IGNORE INTO todo_completion_aliases '
            '(alias_id, canonical_id, todo_id, created_at) VALUES (?, ?, ?, ?)',
            [id, canonicalId, parent, AppClock.now().millisecondsSinceEpoch],
          );
          return false;
        }
      }
    }
    if (type == 'todo') {
      // A to-do may point at a project or parent that no longer exists here,
      // or a parent chain may have formed a cycle on a peer. Fall back to a
      // root/unlinked task instead of rejecting the whole change.
      final projectIndex = schema.columns.indexOf('project_id');
      final projectId = values[projectIndex];
      if (projectId is String) {
        final rows = await _db
            .customSelect(
              'SELECT 1 AS present FROM projects WHERE id = ?',
              variables: [Variable.withString(projectId)],
            )
            .get();
        if (rows.isEmpty) values[projectIndex] = null;
      }
      final parentIndex = schema.columns.indexOf('parent_id');
      final parentId = values[parentIndex];
      if (parentId is String) {
        var cursor = parentId;
        final seen = <String>{};
        var cycle = parentId == id || !(await _todoExists(cursor));
        while (!cycle && seen.add(cursor)) {
          if (cursor == id) {
            cycle = true;
            break;
          }
          final rows = await _db
              .customSelect(
                'SELECT parent_id FROM todo_items WHERE id = ?',
                variables: [Variable.withString(cursor)],
              )
              .get();
          if (rows.isEmpty) break;
          final next = rows.first.read<String?>('parent_id');
          if (next == null) break;
          cursor = next;
        }
        if (cycle) values[parentIndex] = null;
      }
    }
    if (type == 'daily_plan') {
      // One plan per local calendar day. If both devices created a plan for the
      // same day, the newer version wins; the losing plan row disappears.
      final dayKey = payload['day_key'];
      if (dayKey is! String || dayKey.isEmpty) {
        throw const FormatException('Invalid plan day');
      }
      final clash = await _db
          .customSelect(
            'SELECT id FROM daily_plans WHERE day_key = ? AND id != ?',
            variables: [Variable.withString(dayKey), Variable.withString(id)],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        final localVersion = await _localVersion(type, localId);
        if (incomingVersion != null &&
            localVersion != null &&
            !_incomingWins(
              clampedVersion ?? incomingVersion,
              incomingCounter,
              incomingOrigin,
              localVersion,
            )) {
          return false;
        }
        // The incoming plan wins. Deleting the loser cascades to its items, so
        // capture them first and re-create them under the winner. Losing tasks
        // would otherwise vanish without an error. The write itself happens
        // with outbox capture suppressed; the moved rows are queued afterwards.
        final movedItems = await _db
            .customSelect(
              'SELECT * FROM daily_plan_items WHERE plan_id = ?',
              variables: [Variable.withString(localId)],
            )
            .get();
        await _db.customStatement('DELETE FROM daily_plans WHERE id = ?', [
          localId,
        ]);
        await _upsertRow(schema.table, schema.columns, values);
        await _restorePlanItems(id, movedItems);
        await _recordVersion(
          type,
          id,
          clampedVersion,
          incomingOrigin,
          local,
          incomingCounter: incomingCounter,
          deleted: false,
        );
        return true;
      }
    }
    if (type == 'daily_plan_item') {
      // Both task-reference columns are constrained, so reject a payload that
      // would fail the CHECK instead of rejecting the whole batch.
      final todoId = payload['todo_item_id'];
      final projectTaskId = payload['project_task_id'];
      if ((todoId is String) == (projectTaskId is String)) {
        throw const FormatException('Invalid plan item task');
      }
      final planId = payload['plan_id'];
      if (planId is! String || !(await _rowExists('daily_plans', planId))) {
        return false;
      }
      final taskTable = todoId is String ? 'todo_items' : 'tasks';
      final taskId = todoId is String ? todoId : projectTaskId as String;
      if (!(await _rowExists(taskTable, taskId))) return false;

      // A task can appear only once per plan. When the other device already
      // has a different row for the same task, keep whichever version is newer
      // and drop the loser.
      final taskColumn = todoId is String ? 'todo_item_id' : 'project_task_id';
      final clash = await _db
          .customSelect(
            'SELECT id FROM daily_plan_items '
            'WHERE plan_id = ? AND $taskColumn = ? AND id != ?',
            variables: [
              Variable.withString(planId),
              Variable.withString(taskId),
              Variable.withString(id),
            ],
          )
          .get();
      if (clash.isNotEmpty) {
        final localId = clash.first.read<String>('id');
        final localVersion = await _localVersion(type, localId);
        if (incomingVersion != null &&
            localVersion != null &&
            !_incomingWins(
              clampedVersion ?? incomingVersion,
              incomingCounter,
              incomingOrigin,
              localVersion,
            )) {
          return false;
        }
        await _db.customStatement('DELETE FROM daily_plan_items WHERE id = ?', [
          localId,
        ]);
      }
    }

    await _upsertRow(schema.table, schema.columns, values);
    await _recordVersion(
      type,
      id,
      clampedVersion,
      incomingOrigin,
      local,
      incomingCounter: incomingCounter,
      deleted: false,
    );
    return true;
  }

  Future<void> _upsertRow(
    String table,
    List<String> columns,
    List<Object?> values,
  ) async {
    final placeholders = List.filled(columns.length, '?').join(', ');
    final columnList = columns.join(', ');
    final updates = columns
        .where((column) => column != 'id')
        .map((column) => '$column = excluded.$column')
        .join(', ');
    await _db.customStatement(
      'INSERT INTO $table ($columnList) VALUES ($placeholders) '
      'ON CONFLICT(id) DO UPDATE SET $updates',
      values,
    );
  }

  /// Re-creates a losing plan's items under [planId], skipping any task the
  /// winner already plans. The rows are touched again after outbox capture is
  /// re-enabled, so the other device learns their new parent.
  Future<void> _restorePlanItems(String planId, List<QueryRow> rows) async {
    if (rows.isEmpty) return;
    final existing = await _db
        .customSelect(
          'SELECT todo_item_id, project_task_id FROM daily_plan_items '
          'WHERE plan_id = ?',
          variables: [Variable.withString(planId)],
        )
        .get();
    final planned = <String>{
      for (final row in existing)
        if (row.readNullable<String>('todo_item_id') != null)
          'todo:${row.readNullable<String>('todo_item_id')}'
        else
          'task:${row.readNullable<String>('project_task_id')}',
    };
    for (final row in rows) {
      final itemId = row.read<String>('id');
      final todoId = row.readNullable<String>('todo_item_id');
      final taskId = row.readNullable<String>('project_task_id');
      final key = todoId != null ? 'todo:$todoId' : 'task:$taskId';
      if (!planned.add(key)) continue;
      if (await _rowExists('daily_plan_items', itemId)) continue;
      await _db.customStatement(
        'INSERT INTO daily_plan_items '
        '(id, plan_id, todo_item_id, project_task_id, sort_order, '
        'planned_minutes, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          itemId,
          planId,
          todoId,
          taskId,
          row.read<int>('sort_order'),
          row.readNullable<int>('planned_minutes'),
          row.read<int>('created_at'),
          row.read<int>('updated_at'),
        ],
      );
      _republishPlanItems.add(itemId);
    }
  }

  static bool _isMergeableTextType(String type) =>
      type == 'todo' || type == 'event';

  static String _textColumn(String type) =>
      type == 'todo' ? 'notes' : 'description';

  static String _formatColumn(String type) =>
      type == 'todo' ? 'notes_format' : 'description_format';

  Future<({String? text, String format})?> _readLocalText(
    String type,
    String id,
  ) async {
    final schema = _schemas[type]!;
    final rows = await _db
        .customSelect(
          'SELECT ${_textColumn(type)} AS text, '
          '${_formatColumn(type)} AS format '
          'FROM ${schema.table} WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    final rawText = rows.first.data['text'];
    final rawFormat = rows.first.data['format'];
    return (
      text: rawText is String ? rawText : null,
      format: rawFormat == 'md1' ? 'md1' : 'plain',
    );
  }

  /// The incoming change lost; append its text to the local winner.
  Future<bool> _mergeLosingText(
    String type,
    String id,
    Map<String, dynamic> payload,
  ) async {
    final incoming = payload[_textColumn(type)];
    if (incoming is! String || incoming.trim().isEmpty) return false;
    final local = await _readLocalText(type, id);
    if (local == null) return false;
    final localText = local.text ?? '';
    final merged = mergeDiaryContent(localText, incoming);
    if (merged == localText) return false;
    final incomingFormat = payload[_formatColumn(type)];
    final format = local.format == 'md1' || incomingFormat == 'md1'
        ? 'md1'
        : 'plain';
    final schema = _schemas[type]!;
    await _db.customStatement(
      'UPDATE ${schema.table} SET ${_textColumn(type)} = ?, '
      '${_formatColumn(type)} = ? WHERE id = ?',
      [merged, format, id],
    );
    return true;
  }

  /// The incoming change won; append the local loser to the incoming text.
  Future<bool> _foldLocalTextIntoIncoming(
    String type,
    String id,
    List<Object?> values,
    List<String> columns,
  ) async {
    final textIndex = columns.indexOf(_textColumn(type));
    final formatIndex = columns.indexOf(_formatColumn(type));
    final incoming = values[textIndex];
    if (incoming is! String || incoming.trim().isEmpty) return false;
    final local = await _readLocalText(type, id);
    if (local == null) return false;
    final localText = local.text ?? '';
    if (localText.trim().isEmpty || localText == incoming) return false;
    final merged = mergeDiaryContent(incoming, localText);
    if (merged == incoming) return false;
    values[textIndex] = merged;
    values[formatIndex] = values[formatIndex] == 'md1' || local.format == 'md1'
        ? 'md1'
        : 'plain';
    return true;
  }

  int _clampIncomingVersion(int value) {
    final now = AppClock.now().millisecondsSinceEpoch;
    final maxFuture = now + const Duration(minutes: 10).inMilliseconds;
    return value > maxFuture ? maxFuture : value;
  }

  Future<void> _advanceClock(
    int incomingWall,
    int incomingCounter,
    int localWall,
    int localCounter,
  ) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    final wall = _maxInt(now, _maxInt(incomingWall, localWall));
    final int counter;
    if (wall == localWall && wall == incomingWall) {
      counter = _maxInt(localCounter, incomingCounter) + 1;
    } else if (wall == localWall) {
      counter = localCounter + 1;
    } else if (wall == incomingWall) {
      counter = incomingCounter + 1;
    } else {
      counter = 0;
    }
    await _db.customStatement(
      'UPDATE sync_clock SET last_wall = ?, last_counter = ? WHERE id = 1',
      [wall, counter],
    );
  }

  bool _incomingWins(
    int incomingVersion,
    int incomingCounter,
    String? incomingDevice,
    _LocalVersion local,
  ) {
    if (incomingVersion != local.updatedAt) {
      return incomingVersion > local.updatedAt;
    }
    if (incomingCounter != local.counter) {
      return incomingCounter > local.counter;
    }
    // Exact tie: the higher device id wins on both sides. The same device with
    // the same version is a replay of a change that was already applied.
    return (incomingDevice ?? '').compareTo(local.deviceId ?? '') > 0;
  }

  /// A revived tombstone must have valid parents; an incomplete or orphaned
  /// Undo stays deleted instead of writing a dangling row.
  Future<bool> _revivalParentsValid(
    String type,
    Map<String, dynamic> payload,
  ) async {
    final id = payload['id'];
    switch (type) {
      case 'project_task':
        final parent = payload['project_id'];
        return parent is String && await _rowExists('projects', parent);
      case 'todo':
        final project = payload['project_id'];
        if (project is String && !await _rowExists('projects', project)) {
          return false;
        }
        final parent = payload['parent_id'];
        if (parent is String) {
          if (parent == id || !await _rowExists('todo_items', parent)) {
            return false;
          }
        }
        return true;
      case 'attachment':
        final todo = payload['todo_id'];
        final event = payload['event_id'];
        if ((todo is String) == (event is String)) return false;
        return todo is String
            ? _rowExists('todo_items', todo)
            : _rowExists('events', event as String);
      case 'habit_log':
        final parent = payload['habit_id'];
        return parent is String && await _rowExists('habits', parent);
      case 'todo_completion':
        final parent = payload['todo_id'];
        return parent is String && await _rowExists('todo_items', parent);
      case 'project_status':
      case 'project_milestone':
        final parent = payload['project_id'];
        return parent is String && await _rowExists('projects', parent);
      case 'task_dependency':
        final predecessor = payload['predecessor_task_id'];
        final successor = payload['successor_task_id'];
        return predecessor is String &&
            successor is String &&
            predecessor != successor &&
            await _rowExists('tasks', predecessor) &&
            await _rowExists('tasks', successor);
      case 'daily_plan_item':
        final parent = payload['plan_id'];
        return parent is String && await _rowExists('daily_plans', parent);
      default:
        return true;
    }
  }

  Future<bool> _todoExists(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM todo_items WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<bool> _rowExists(String table, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 AS present FROM $table WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<_LocalVersion?> _localVersion(String type, String id) async {
    final rows = await _db
        .customSelect(
          'SELECT updated_at, hlc_counter, device_id, deleted '
          'FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          variables: [Variable.withString(type), Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return _LocalVersion(
      rows.first.read<int>('updated_at'),
      rows.first.read<int>('hlc_counter'),
      rows.first.readNullable<String>('device_id'),
      deleted: rows.first.read<int>('deleted') == 1,
    );
  }

  Future<void> _recordVersion(
    String type,
    String id,
    int? incomingVersion,
    String? incomingDevice,
    _LocalVersion? local, {
    int incomingCounter = 0,
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
      '(entity_type, entity_id, updated_at, hlc_counter, device_id, deleted) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(entity_type, entity_id) DO UPDATE SET '
      'updated_at = excluded.updated_at, '
      'hlc_counter = excluded.hlc_counter, '
      'device_id = excluded.device_id, deleted = excluded.deleted',
      [type, id, version, incomingCounter, incomingDevice, deleted ? 1 : 0],
    );
  }

  static int _maxInt(int a, int b) => a > b ? a : b;
}

class _LocalVersion {
  const _LocalVersion(
    this.updatedAt,
    this.counter,
    this.deviceId, {
    this.deleted = false,
  });

  final int updatedAt;
  final int counter;
  final String? deviceId;
  final bool deleted;
}
