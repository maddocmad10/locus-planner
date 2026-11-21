import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import 'reminder_planner.dart';

class PlatformReminderState {
  const PlatformReminderState({
    required this.id,
    required this.kind,
    required this.entityId,
    required this.fireAt,
    required this.scheduledAt,
    required this.deliveredAt,
    required this.snoozedFrom,
  });

  final String id;
  final String kind;
  final String entityId;
  final DateTime fireAt;
  final DateTime scheduledAt;
  final DateTime? deliveredAt;
  final String? snoozedFrom;
}

/// Device-local state for reminders owned by the operating system.
class PlatformReminderStore {
  PlatformReminderStore(this._db);

  final AppDatabase _db;

  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    await _db.transaction(() async {
      for (final reminder in reminders) {
        await _db.customStatement(
          'INSERT INTO platform_reminder_state '
          '(id, kind, entity_id, fire_at, scheduled_at, delivered_at, snoozed_from) '
          'VALUES (?, ?, ?, ?, ?, NULL, NULL) '
          'ON CONFLICT(id) DO UPDATE SET '
          'kind = excluded.kind, entity_id = excluded.entity_id, '
          'fire_at = excluded.fire_at, scheduled_at = excluded.scheduled_at, '
          'delivered_at = NULL',
          [
            reminder.id,
            reminder.kind.name,
            reminder.entityId,
            reminder.fireAt.millisecondsSinceEpoch,
            AppClock.now().millisecondsSinceEpoch,
          ],
        );
      }
    });
  }

  Future<void> removeExcept(Set<String> keepIds) async {
    if (keepIds.isEmpty) {
      await _db.customStatement('DELETE FROM platform_reminder_state');
      return;
    }
    final placeholders = List.filled(keepIds.length, '?').join(', ');
    await _db.customStatement(
      'DELETE FROM platform_reminder_state WHERE id NOT IN ($placeholders)',
      keepIds.toList(growable: false),
    );
  }

  Future<List<PlatformReminderState>> all() async {
    final rows = await _db
        .customSelect('SELECT * FROM platform_reminder_state ORDER BY fire_at')
        .get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<List<PlatformReminderState>> missedBefore(DateTime now) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM platform_reminder_state '
          'WHERE delivered_at IS NULL AND fire_at < ? ORDER BY fire_at',
          variables: [Variable.withInt(now.millisecondsSinceEpoch)],
        )
        .get();
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> markDelivered(Iterable<String> ids) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    for (final id in ids) {
      await _db.customStatement(
        'UPDATE platform_reminder_state SET delivered_at = ? WHERE id = ?',
        [now, id],
      );
    }
  }

  static PlatformReminderState _fromRow(dynamic row) => PlatformReminderState(
    id: row.read<String>('id'),
    kind: row.read<String>('kind'),
    entityId: row.read<String>('entity_id'),
    fireAt: DateTime.fromMillisecondsSinceEpoch(row.read<int>('fire_at')),
    scheduledAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('scheduled_at'),
    ),
    deliveredAt: row.readNullable<int>('delivered_at') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.read<int>('delivered_at')),
    snoozedFrom: row.readNullable<String>('snoozed_from'),
  );
}
