import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import 'sync_change_applier.dart';

class SnapshotReviewItem {
  const SnapshotReviewItem({
    required this.snapshotId,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.payloadJson,
    this.peerId = '',
    this.epoch = '',
    this.desktopName,
    this.title,
    this.attachmentCount = 0,
    this.childCount = 0,
    this.reviewedRevision,
    this.reviewedDigest,
  });

  final String snapshotId;
  final String changeId;
  final String entityType;
  final String entityId;
  final String reason;
  final String payloadJson;
  final String peerId;
  final String epoch;
  final String? desktopName;
  final String? title;
  final int attachmentCount;
  final int childCount;
  final int? reviewedRevision;
  final String? reviewedDigest;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title! : '$entityType $entityId';

  SnapshotReviewItem copyWith({int? attachmentCount, int? childCount}) =>
      SnapshotReviewItem(
        snapshotId: snapshotId,
        changeId: changeId,
        entityType: entityType,
        entityId: entityId,
        reason: reason,
        payloadJson: payloadJson,
        peerId: peerId,
        epoch: epoch,
        desktopName: desktopName,
        title: title,
        attachmentCount: attachmentCount ?? this.attachmentCount,
        childCount: childCount ?? this.childCount,
        reviewedRevision: reviewedRevision,
        reviewedDigest: reviewedDigest,
      );
}

class SnapshotReviewChangedException implements Exception {
  const SnapshotReviewChangedException(this.items);

  final List<SnapshotReviewItem> items;

  @override
  String toString() =>
      '${items.length} reviewed item${items.length == 1 ? '' : 's'} changed. '
      'Review the new title and choose again.';
}

class SnapshotRecoveryRequiresOwnerException implements Exception {
  const SnapshotRecoveryRequiresOwnerException(this.items);

  final List<SnapshotReviewItem> items;

  @override
  String toString() =>
      '${items.length} recovered row${items.length == 1 ? '' : 's'} need a '
      'surviving owner. Choose another parent or keep the desktop deletion.';
}

/// Resolves ambiguous phone-only rows captured during bootstrap. Recovering a
/// row allocates a fresh ID, remaps references and rewrites the staged receipt
/// in one transaction; keeping the desktop deletion discards the staged row.
class SnapshotReconciliationService {
  SnapshotReconciliationService(this._db);

  static const _tables = <String, String>{
    'project': 'projects',
    'event': 'events',
    'project_task': 'tasks',
    'project_status': 'project_statuses',
    'project_milestone': 'project_milestones',
    'task_dependency': 'task_dependencies',
    'habit': 'habits',
    'habit_log': 'habit_logs',
    'todo': 'todo_items',
    'todo_completion': 'todo_completions',
    'diary_entry': 'diary_entries',
    'daily_plan': 'daily_plans',
    'daily_plan_item': 'daily_plan_items',
    'task_schedule_block': 'task_schedule_blocks',
    'saved_filter': 'saved_filters',
    'planning_preference': 'planning_preferences',
    'working_hours': 'working_hours',
    'working_break': 'working_breaks',
    'attachment': 'attachments',
    'progress_log': 'progress_logs',
    'focus_session': 'focus_sessions',
  };

  static const _references = <String, List<String>>{
    'project_task': ['project_id'],
    'habit_log': ['habit_id'],
    'todo': ['parent_id', 'project_id'],
    'todo_completion': ['todo_id'],
    'daily_plan_item': ['plan_id', 'todo_item_id', 'project_task_id'],
    'task_schedule_block': ['todo_item_id', 'project_task_id'],
    'project_status': ['project_id'],
    'project_milestone': ['project_id'],
    'task_dependency': ['predecessor_task_id', 'successor_task_id'],
    'attachment': ['todo_id', 'event_id'],
    'progress_log': ['project_id'],
    'focus_session': ['project_id'],
  };

  final AppDatabase _db;

  Future<List<SnapshotReviewItem>> reviewItems({
    String? peerId,
    String? epoch,
    String? snapshotId,
  }) async {
    final rows = await _db
        .customSelect(
          'SELECT i.snapshot_id, i.change_id, i.entity_type, i.entity_id, '
          'i.reason, i.payload_json, i.reviewed_revision, i.reviewed_digest, '
          's.peer_id, s.epoch, s.peer_name '
          'FROM snapshot_item i '
          'JOIN snapshot_session s ON s.snapshot_id = i.snapshot_id '
          "WHERE i.disposition = 'review' "
          "AND s.phase IN ('capture', 'download', 'upload') "
          '${peerId != null ? 'AND s.peer_id = ? ' : ''}'
          '${epoch != null ? 'AND s.epoch = ? ' : ''}'
          '${snapshotId != null ? 'AND i.snapshot_id = ? ' : ''}'
          'ORDER BY i.ordinal',
          variables: [
            if (peerId != null) Variable.withString(peerId),
            if (epoch != null) Variable.withString(epoch),
            if (snapshotId != null) Variable.withString(snapshotId),
          ],
        )
        .get();
    final items = <SnapshotReviewItem>[];
    for (final row in rows) {
      final item = _reviewFromRow(row);
      items.add(
        item.copyWith(
          attachmentCount: await _attachmentCount(item),
          childCount: rows.where((other) {
            if (other.read<String>('change_id') == item.changeId) return false;
            final otherPayload = other.read<String>('payload_json');
            return _referencesToRaw(
              otherPayload,
            ).contains('${item.entityType}:${item.entityId}');
          }).length,
        ),
      );
    }
    return items;
  }

  Future<List<SnapshotReviewItem>> archivedReviewItems() async {
    final rows = await _db
        .customSelect(
          'SELECT i.snapshot_id, i.change_id, i.entity_type, i.entity_id, '
          'i.reason, i.payload_json, i.reviewed_revision, i.reviewed_digest, '
          's.peer_id, s.epoch, s.peer_name '
          'FROM snapshot_item i '
          'JOIN snapshot_session s ON s.snapshot_id = i.snapshot_id '
          "WHERE i.disposition = 'review' "
          "AND s.phase IN ('retired', 'stale', 'complete') "
          'ORDER BY i.ordinal',
        )
        .get();
    return [for (final row in rows) _reviewFromRow(row)];
  }

  SnapshotReviewItem _reviewFromRow(dynamic row) {
    var type = row.read<String>('entity_type');
    var id = row.read<String>('entity_id');
    final payloadJson = row.read<String>('payload_json');
    String? title;
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map) {
        if (type.isEmpty && decoded['entityType'] is String) {
          type = decoded['entityType'] as String;
        }
        if (id.isEmpty && decoded['entityId'] is String) {
          id = decoded['entityId'] as String;
        }
        final payload = decoded['payload'];
        if (payload is Map) {
          final rawTitle = payload['title'] ?? payload['name'];
          if (rawTitle is String) title = rawTitle;
        }
      }
    } catch (_) {
      // Leave empty; the UI will offer only Leave for an unreadable item.
    }
    return SnapshotReviewItem(
      snapshotId: row.read<String>('snapshot_id'),
      changeId: row.read<String>('change_id'),
      entityType: type,
      entityId: id,
      reason: row.readNullable<String>('reason') ?? 'phone_only',
      payloadJson: payloadJson,
      peerId: row.read<String>('peer_id'),
      epoch: row.read<String>('epoch'),
      desktopName: row.readNullable<String>('peer_name'),
      title: title,
      reviewedRevision: row.readNullable<int>('reviewed_revision'),
      reviewedDigest: row.readNullable<String>('reviewed_digest'),
    );
  }

  Future<int> _attachmentCount(SnapshotReviewItem item) async {
    if (item.entityType != 'todo' && item.entityType != 'event') return 0;
    final column = item.entityType == 'todo' ? 'todo_id' : 'event_id';
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM attachments WHERE $column = ?',
          variables: [Variable.withString(item.entityId)],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<int> reviewCount({
    String? peerId,
    String? epoch,
    String? snapshotId,
  }) async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM snapshot_item i '
          'JOIN snapshot_session s ON s.snapshot_id = i.snapshot_id '
          "WHERE i.disposition = 'review' "
          "AND s.phase IN ('capture', 'download', 'upload') "
          '${peerId != null ? 'AND s.peer_id = ? ' : ''}'
          '${epoch != null ? 'AND s.epoch = ? ' : ''}'
          '${snapshotId != null ? 'AND i.snapshot_id = ? ' : ''}',
          variables: [
            if (peerId != null) Variable.withString(peerId),
            if (epoch != null) Variable.withString(epoch),
            if (snapshotId != null) Variable.withString(snapshotId),
          ],
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<void> _rewriteStagedReferences(Map<String, String> idMap) async {
    final snapshotRows = await _db
        .customSelect(
          'SELECT snapshot_id, change_id, payload_json FROM snapshot_item',
        )
        .get();
    for (final row in snapshotRows) {
      final decoded = _decodePayload(row.read<String>('payload_json'));
      if (decoded == null) continue;
      if (_applyReferenceRemap(decoded, idMap)) {
        await _db.customStatement(
          'UPDATE snapshot_item SET payload_json = ? '
          'WHERE snapshot_id = ? AND change_id = ?',
          [
            jsonEncode(decoded),
            row.read<String>('snapshot_id'),
            row.read<String>('change_id'),
          ],
        );
      }
    }
    final repairs = await _db
        .customSelect(
          'SELECT peer_id, epoch, direction, change_id, entity_type, '
          'entity_id, payload_json FROM sync_rejected_changes '
          'WHERE resolved_ms IS NULL',
        )
        .get();
    final now = AppClock.now().millisecondsSinceEpoch;
    for (final row in repairs) {
      final type = row.read<String>('entity_type');
      final id = row.read<String>('entity_id');
      if (idMap.containsKey('$type:$id')) {
        // The old change can never be replayed under its acknowledged id.
        await _db.customStatement(
          'UPDATE sync_rejected_changes SET resolved_ms = ?, '
          "resolution_kind = 'superseded_by_recovery', last_attempt_ms = ? "
          'WHERE peer_id = ? AND epoch = ? AND direction = ? AND change_id = ?',
          [
            now,
            now,
            row.read<String>('peer_id'),
            row.read<String>('epoch'),
            row.read<String>('direction'),
            row.read<String>('change_id'),
          ],
        );
        continue;
      }
      final decoded = _decodePayload(row.read<String>('payload_json'));
      if (decoded == null) continue;
      if (_applyReferenceRemap(decoded, idMap)) {
        await _db.customStatement(
          'UPDATE sync_rejected_changes SET payload_json = ? '
          'WHERE peer_id = ? AND epoch = ? AND direction = ? AND change_id = ?',
          [
            jsonEncode(decoded),
            row.read<String>('peer_id'),
            row.read<String>('epoch'),
            row.read<String>('direction'),
            row.read<String>('change_id'),
          ],
        );
      }
    }
    final outbox = await _db
        .customSelect(
          "SELECT id, payload FROM sync_outbox WHERE operation = 'upsert'",
        )
        .get();
    for (final row in outbox) {
      final decoded = _decodePayload(row.read<String>('payload'));
      if (decoded == null) continue;
      if (_applyReferenceRemap(decoded, idMap)) {
        await _db.customStatement(
          'UPDATE sync_outbox SET payload = ? WHERE id = ?',
          [jsonEncode(decoded), row.read<int>('id')],
        );
      }
    }
  }

  Map<String, dynamic>? _decodePayload(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['payload'] is! Map) return null;
      return decoded;
    } catch (_) {
      return null;
    }
  }

  bool _applyReferenceRemap(
    Map<String, dynamic> envelope,
    Map<String, String> idMap,
  ) {
    final payload = envelope['payload'];
    if (payload is! Map) return false;
    final type = envelope['entityType'];
    final refs = type is String ? _references[type] : null;
    if (refs == null) return false;
    var changed = false;
    for (final field in refs) {
      final old = payload[field];
      final target = _referenceTargets[field];
      if (old is! String || target == null) continue;
      final replacement = idMap['$target:$old'];
      if (replacement != null) {
        payload[field] = replacement;
        changed = true;
      }
    }
    return changed;
  }

  static const _exclusiveOwnerFields = <String, Set<String>>{
    'attachment': {'todo_id', 'event_id'},
    'daily_plan_item': {'todo_item_id', 'project_task_id'},
    'task_schedule_block': {'todo_item_id', 'project_task_id'},
  };

  bool _exclusiveOwnerSurvives(SnapshotReviewItem item, Set<String> keptKeys) {
    final fields = _exclusiveOwnerFields[item.entityType];
    if (fields == null) return true;
    final owners = _referencesOf(
      item,
    ).where((ref) => fields.contains(ref.field)).toList();
    if (owners.isEmpty) return true;
    return owners.any((ref) => !keptKeys.contains(ref.key));
  }

  Future<bool> _sessionIsActive(String snapshotId) async {
    final rows = await _db
        .customSelect(
          'SELECT phase FROM snapshot_session WHERE snapshot_id = ?',
          variables: [Variable.withString(snapshotId)],
        )
        .get();
    if (rows.isEmpty) return false;
    final phase = rows.first.read<String>('phase');
    return phase == 'capture' || phase == 'download' || phase == 'upload';
  }

  Future<int?> _currentRevision(String entityType, String entityId) async {
    final rows = await _db
        .customSelect(
          'SELECT updated_at FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          variables: [
            Variable.withString(entityType),
            Variable.withString(entityId),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.first.read<int>('updated_at');
  }

  /// [decisions] maps change id to `keep` or `recover`. Omitted or `leave`
  /// rows stay for later unless a kept parent deletes their branch, in which
  /// case they follow it. Recovering a parent pulls its referenced children in.
  Future<({int recovered, int kept, int remaining})> resolve(
    Map<String, String> decisions,
  ) async {
    final all = await reviewItems();
    if (all.isEmpty) {
      return (recovered: 0, kept: 0, remaining: 0);
    }
    final changedItems = <SnapshotReviewItem>[];
    for (final item in all) {
      final active = await _sessionIsActive(item.snapshotId);
      final current = await _currentRevision(item.entityType, item.entityId);
      final reviewed = item.reviewedRevision;
      if (!active ||
          (reviewed != null && current != null && reviewed != current)) {
        changedItems.add(item);
      }
    }
    if (changedItems.isNotEmpty) {
      throw SnapshotReviewChangedException(changedItems);
    }
    final byId = {for (final item in all) item.changeId: item};
    final status = <String, String>{
      for (final item in all)
        item.changeId: decisions[item.changeId] ?? 'leave',
    };

    // Settle the graph before touching rows. Explicit decisions win unless
    // they are impossible (a recovered row cannot keep a NOT NULL reference to
    // a deleted row), and an undecided row follows its parent. Iterating to a
    // fixed point handles chains such as project -> task -> completion.
    final detach = <String, Set<String>>{};
    final needsOwner = <String, SnapshotReviewItem>{};
    var changed = true;
    while (changed) {
      changed = false;
      final keptKeys = <String>{
        for (final item in all)
          if (status[item.changeId] == 'keep')
            '${item.entityType}:${item.entityId}',
      };
      final recoveredKeys = <String>{
        for (final item in all)
          if (status[item.changeId] == 'recover')
            '${item.entityType}:${item.entityId}',
      };
      for (final item in all) {
        final current = status[item.changeId];
        if (current == 'keep') continue;
        final refs = _referencesOf(item);
        if (current == 'recover') {
          for (final ref in refs) {
            if (!keptKeys.contains(ref.key)) continue;
            if (_detachable(item.entityType, ref.field)) {
              (detach[item.changeId] ??= <String>{}).add(ref.field);
            } else {
              // The child cannot exist without the deleted parent.
              status[item.changeId] = 'keep';
              changed = true;
              break;
            }
          }
          if (status[item.changeId] == 'recover' &&
              !_exclusiveOwnerSurvives(item, keptKeys)) {
            if (decisions[item.changeId] == 'recover') {
              needsOwner[item.changeId] = item;
            } else {
              // An undecided dependent follows the deleted branch.
              status[item.changeId] = 'keep';
              changed = true;
            }
          }
        } else if (refs.any((ref) => keptKeys.contains(ref.key))) {
          status[item.changeId] = 'keep';
          changed = true;
        } else if (refs.any((ref) => recoveredKeys.contains(ref.key))) {
          status[item.changeId] = 'recover';
          changed = true;
        }
      }
    }

    if (needsOwner.isNotEmpty) {
      throw SnapshotRecoveryRequiresOwnerException(needsOwner.values.toList());
    }

    final recovered = <String, SnapshotReviewItem>{
      for (final item in all)
        if (status[item.changeId] == 'recover') item.changeId: item,
    };
    final kept = <String, SnapshotReviewItem>{
      for (final item in all)
        if (status[item.changeId] == 'keep') item.changeId: item,
    };
    final idMap = <String, String>{
      for (final item in recovered.values)
        '${item.entityType}:${item.entityId}': const Uuid().v4(),
    };
    var recoveredCount = 0;
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        // Detach explicitly recovered rows from deleted branches before the
        // deletes cascade them away.
        for (final entry in detach.entries) {
          final item = byId[entry.key];
          if (item == null || !recovered.containsKey(entry.key)) continue;
          final table = _tables[item.entityType];
          if (table == null) continue;
          for (final field in entry.value) {
            await _db.customStatement(
              'UPDATE $table SET $field = NULL WHERE id = ?',
              [item.entityId],
            );
          }
        }

        for (final item in kept.values) {
          final table = _tables[item.entityType];
          if (table != null) {
            await _db.customStatement('DELETE FROM $table WHERE id = ?', [
              item.entityId,
            ]);
            await _db.customStatement(
              'DELETE FROM sync_row_versions '
              'WHERE entity_type = ? AND entity_id = ?',
              [item.entityType, item.entityId],
            );
            await _db.customStatement(
              'DELETE FROM sync_field_versions '
              'WHERE entity_type = ? AND entity_id = ?',
              [item.entityType, item.entityId],
            );
          }
          await _db.customStatement(
            'UPDATE snapshot_item SET disposition = ?, reason = ?, '
            'updated_at = ? WHERE snapshot_id = ? AND change_id = ?',
            [
              'superseded',
              'kept_desktop_deletion',
              now,
              item.snapshotId,
              item.changeId,
            ],
          );
        }

        // Settle the incremental outbox. The staged snapshot is not the only
        // writer: a pending insert for a kept row would recreate it, and one
        // for a recovered row would recreate the old id beside the new one.
        for (final item in kept.values) {
          await _db.customStatement(
            'DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ?',
            [item.entityType, item.entityId],
          );
        }
        for (final item in recovered.values) {
          final newId = idMap['${item.entityType}:${item.entityId}']!;
          await _db.customStatement(
            'DELETE FROM sync_outbox WHERE entity_type = ? AND entity_id = ? '
            "AND operation != 'upsert'",
            [item.entityType, item.entityId],
          );
          final rows = await _db
              .customSelect(
                'SELECT id, payload FROM sync_outbox '
                "WHERE entity_type = ? AND entity_id = ? AND operation = 'upsert'",
                variables: [
                  Variable.withString(item.entityType),
                  Variable.withString(item.entityId),
                ],
              )
              .get();
          for (final row in rows) {
            final decoded = jsonDecode(row.read<String>('payload'));
            if (decoded is! Map<String, dynamic>) continue;
            decoded['id'] = newId;
            for (final field
                in _references[item.entityType] ?? const <String>[]) {
              final old = decoded[field];
              final target = _referenceTargets[field];
              if (old is! String || target == null) continue;
              final replacement = idMap['$target:$old'];
              if (replacement != null) {
                decoded[field] = replacement;
              } else if (detach[item.changeId]?.contains(field) ?? false) {
                decoded[field] = null;
              }
            }
            await _db.customStatement(
              'UPDATE sync_outbox SET entity_id = ?, payload = ? WHERE id = ?',
              [newId, jsonEncode(decoded), row.read<int>('id')],
            );
          }
        }

        // Update references before primary keys. Deferred foreign keys let the
        // whole graph settle at commit. Only columns whose target type matches
        // the recovered type are touched, so two unrelated records may share a
        // literal id without moving each other's references.
        for (final entry in idMap.entries) {
          final separator = entry.key.indexOf(':');
          final entityType = entry.key.substring(0, separator);
          final oldId = entry.key.substring(separator + 1);
          final newId = entry.value;
          for (final ref in _references.entries) {
            final table = _tables[ref.key];
            if (table == null) continue;
            for (final column in ref.value) {
              if (_referenceTargets[column] != entityType) continue;
              await _db.customStatement(
                'UPDATE $table SET $column = ? WHERE $column = ?',
                [newId, oldId],
              );
            }
          }
        }

        await _rewriteStagedReferences(idMap);

        for (final item in recovered.values) {
          final table = _tables[item.entityType];
          if (table == null) continue;
          final newId = idMap['${item.entityType}:${item.entityId}']!;
          final updated = await _db.customUpdate(
            'UPDATE $table SET id = ? WHERE id = ?',
            variables: [
              Variable.withString(newId),
              Variable.withString(item.entityId),
            ],
          );
          if (updated == 0) {
            // The local row is already gone; there is nothing to recover.
            await _db.customStatement(
              'UPDATE snapshot_item SET disposition = ?, reason = ?, '
              'updated_at = ? WHERE snapshot_id = ? AND change_id = ?',
              [
                'superseded',
                'local_row_missing',
                now,
                item.snapshotId,
                item.changeId,
              ],
            );
            continue;
          }
          recoveredCount++;
          await _db.customStatement(
            'UPDATE sync_row_versions SET entity_id = ? '
            'WHERE entity_type = ? AND entity_id = ?',
            [newId, item.entityType, item.entityId],
          );
          await _db.customStatement(
            'UPDATE sync_field_versions SET entity_id = ? '
            'WHERE entity_type = ? AND entity_id = ?',
            [newId, item.entityType, item.entityId],
          );

          final decoded = jsonDecode(item.payloadJson);
          if (decoded is! Map<String, dynamic>) continue;
          decoded['entityId'] = newId;
          final payload = decoded['payload'];
          if (payload is Map<String, dynamic>) {
            payload['id'] = newId;
            for (final field
                in _references[item.entityType] ?? const <String>[]) {
              final old = payload[field];
              final target = _referenceTargets[field];
              if (old is! String || target == null) continue;
              final replacement = idMap['$target:$old'];
              if (replacement != null) {
                payload[field] = replacement;
              } else if (detach[item.changeId]?.contains(field) ?? false) {
                payload[field] = null;
              }
            }
          }
          final newChangeId =
              'recovered:${item.snapshotId}:${item.entityType}:$newId';
          decoded['changeId'] = newChangeId;
          await _db.customStatement(
            'DELETE FROM snapshot_item WHERE snapshot_id = ? AND change_id = ?',
            [item.snapshotId, item.changeId],
          );
          await _db.customStatement(
            'INSERT INTO snapshot_item '
            '(snapshot_id, change_id, ordinal, payload_json, disposition, '
            'reason, updated_at, entity_type, entity_id, reviewed_revision, '
            'reviewed_digest, upload_change_id) '
            "VALUES (?, ?, (SELECT COALESCE(MAX(ordinal), 0) + 1 FROM "
            'snapshot_item WHERE snapshot_id = ?), ?, ?, NULL, ?, ?, ?, ?, ?, ?)',
            [
              item.snapshotId,
              newChangeId,
              item.snapshotId,
              jsonEncode(decoded),
              'approved_upload',
              now,
              item.entityType,
              newId,
              item.reviewedRevision ?? _payloadRevision(item),
              item.reviewedDigest,
              newChangeId,
            ],
          );
          await _db.customStatement(
            'INSERT OR IGNORE INTO snapshot_recovery_map '
            '(snapshot_id, entity_type, original_id, recovered_id, created_at) '
            'VALUES (?, ?, ?, ?, ?)',
            [item.snapshotId, item.entityType, item.entityId, newId, now],
          );
        }
        final violations = await _db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        if (violations.isNotEmpty) {
          throw StateError(
            'The recovery choice would leave an invalid reference. Choose a '
            'surviving owner for the affected row.',
          );
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
    });
    final remaining = await reviewCount();
    return (recovered: recoveredCount, kept: kept.length, remaining: remaining);
  }

  int? _payloadRevision(SnapshotReviewItem item) {
    try {
      final decoded = jsonDecode(item.payloadJson);
      if (decoded is! Map) return null;
      final payload = decoded['payload'];
      if (payload is! Map) return null;
      final key = SyncChangeApplier.versionKeyFor(item.entityType);
      final value = key == null ? null : payload[key];
      return value is int ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// References that can be cleared when a recovered row loses its parent but
  /// still makes sense on its own. Every other reference is NOT NULL, so a
  /// recovered child of a kept parent must keep the deletion instead.
  static const _detachableReferences = <String, Set<String>>{
    'todo': {'parent_id', 'project_id'},
    'daily_plan_item': {'todo_item_id', 'project_task_id'},
    'task_schedule_block': {'todo_item_id', 'project_task_id'},
    'attachment': {'todo_id', 'event_id'},
  };

  static const _referenceTargets = <String, String>{
    'parent_id': 'todo',
    'project_id': 'project',
    'habit_id': 'habit',
    'todo_id': 'todo',
    'plan_id': 'daily_plan',
    'todo_item_id': 'todo',
    'project_task_id': 'project_task',
    'predecessor_task_id': 'project_task',
    'successor_task_id': 'project_task',
    'event_id': 'event',
  };

  bool _detachable(String entityType, String field) =>
      _detachableReferences[entityType]?.contains(field) ?? false;

  List<({String field, String key})> _referencesOf(SnapshotReviewItem item) {
    return _referencesOfPayload(item.entityType, item.payloadJson);
  }

  List<({String field, String key})> _referencesOfPayload(
    String entityType,
    String payloadJson,
  ) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return const [];
      final payload = decoded['payload'];
      if (payload is! Map) return const [];
      final refs = _references[entityType] ?? const [];
      return [
        for (final field in refs)
          if (payload[field] is String && _referenceTargets[field] != null)
            (
              field: field,
              key: '${_referenceTargets[field]}:${payload[field]}',
            ),
      ];
    } catch (_) {
      return const [];
    }
  }

  List<String> _referencesToRaw(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map) return const [];
      final type = decoded['entityType'];
      if (type is! String) return const [];
      return [
        for (final ref in _referencesOfPayload(type, payloadJson)) ref.key,
      ];
    } catch (_) {
      return const [];
    }
  }
}
