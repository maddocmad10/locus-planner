import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

class SnapshotReviewItem {
  const SnapshotReviewItem({
    required this.snapshotId,
    required this.changeId,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.payloadJson,
  });

  final String snapshotId;
  final String changeId;
  final String entityType;
  final String entityId;
  final String reason;
  final String payloadJson;
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
  };

  final AppDatabase _db;

  Future<List<SnapshotReviewItem>> reviewItems() async {
    final rows = await _db
        .customSelect(
          'SELECT snapshot_id, change_id, entity_type, entity_id, reason, '
          "payload_json FROM snapshot_item WHERE disposition = 'review' "
          'ORDER BY ordinal',
        )
        .get();
    return [for (final row in rows) _reviewFromRow(row)];
  }

  SnapshotReviewItem _reviewFromRow(dynamic row) {
    var type = row.read<String>('entity_type');
    var id = row.read<String>('entity_id');
    final payloadJson = row.read<String>('payload_json');
    if (type.isEmpty || id.isEmpty) {
      try {
        final decoded = jsonDecode(payloadJson);
        if (decoded is Map) {
          if (type.isEmpty && decoded['entityType'] is String) {
            type = decoded['entityType'] as String;
          }
          if (id.isEmpty && decoded['entityId'] is String) {
            id = decoded['entityId'] as String;
          }
        }
      } catch (_) {
        // Leave empty; the UI will offer only Leave for an unreadable item.
      }
    }
    return SnapshotReviewItem(
      snapshotId: row.read<String>('snapshot_id'),
      changeId: row.read<String>('change_id'),
      entityType: type,
      entityId: id,
      reason: row.readNullable<String>('reason') ?? 'phone_only',
      payloadJson: payloadJson,
    );
  }

  Future<int> reviewCount() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM snapshot_item '
          "WHERE disposition = 'review'",
        )
        .getSingle();
    return row.read<int>('count');
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
        } else if (refs.any((ref) => keptKeys.contains(ref.key))) {
          status[item.changeId] = 'keep';
          changed = true;
        } else if (refs.any((ref) => recoveredKeys.contains(ref.key))) {
          status[item.changeId] = 'recover';
          changed = true;
        }
      }
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
    await _db.customStatement('PRAGMA defer_foreign_keys = ON');
    await _db.transaction(() async {
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
        // whole graph settle at commit.
        for (final entry in idMap.entries) {
          final parts = entry.key.split(':');
          final oldId = parts.sublist(1).join(':');
          final newId = entry.value;
          for (final ref in _references.entries) {
            final table = _tables[ref.key];
            if (table == null) continue;
            for (final column in ref.value) {
              await _db.customStatement(
                'UPDATE $table SET $column = ? WHERE $column = ?',
                [newId, oldId],
              );
            }
          }
        }

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
            'reason, updated_at, entity_type, entity_id) '
            "VALUES (?, ?, (SELECT COALESCE(MAX(ordinal), 0) + 1 FROM "
            'snapshot_item WHERE snapshot_id = ?), ?, ?, NULL, ?, ?, ?)',
            [
              item.snapshotId,
              newChangeId,
              item.snapshotId,
              jsonEncode(decoded),
              'pending',
              now,
              item.entityType,
              newId,
            ],
          );
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
    });
    final remaining = await reviewCount();
    return (recovered: recoveredCount, kept: kept.length, remaining: remaining);
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
    try {
      final decoded = jsonDecode(item.payloadJson);
      if (decoded is! Map) return const [];
      final payload = decoded['payload'];
      if (payload is! Map) return const [];
      final refs = _references[item.entityType] ?? const [];
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
}
