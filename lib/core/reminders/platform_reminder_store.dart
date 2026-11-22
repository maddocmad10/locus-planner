import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../models/reminder_kind.dart';
import '../utils/app_clock.dart';
import 'reminder_identity.dart';

/// One row the scheduler wants persisted. [id] is the OS-visible stable id;
/// [occurrenceStart] is the event start or task reminder time.
class PlatformReminderWrite {
  const PlatformReminderWrite({
    required this.id,
    required this.kind,
    required this.entityId,
    required this.occurrenceStart,
    required this.fireAt,
    this.owner = 'app',
    this.degraded = false,
  });

  final String id;
  final String kind;
  final String entityId;
  final DateTime occurrenceStart;
  final DateTime fireAt;
  final String owner;
  final bool degraded;
}

class PlatformReminderState {
  const PlatformReminderState({
    required this.id,
    required this.kind,
    required this.entityId,
    required this.occurrenceStart,
    required this.fireAt,
    required this.scheduledAt,
    required this.deliveredAt,
    required this.snoozedFrom,
    this.owner = 'unknown',
    this.degraded = false,
  });

  /// OS-visible stable id (16 characters).
  final String id;
  final String kind;
  final String entityId;
  final DateTime occurrenceStart;
  final DateTime fireAt;
  final DateTime scheduledAt;
  final DateTime? deliveredAt;
  final String? snoozedFrom;

  /// `os` when Windows confirmed the toast, `app` for an in-process fallback,
  /// and `unknown` when the native batch result could not be enumerated.
  final String owner;

  /// True when the OS did not confirm this occurrence, so it needs Locus to be
  /// running to be shown.
  final bool degraded;

  ReminderKind get reminderKind => ReminderKind.values.firstWhere(
    (value) => value.name == kind,
    orElse: () => ReminderKind.task,
  );

  ReminderOccurrence get occurrence => ReminderOccurrence(
    kind: reminderKind,
    entityId: entityId,
    occurrenceStart: occurrenceStart,
  );

  String get key => occurrence.key;

  /// Fallback/unknown ownership means the popup only exists while the app runs.
  bool get needsAppRunning => degraded || owner == 'app' || owner == 'unknown';
}

/// Device-local state for reminders owned by the operating system.
class PlatformReminderStore {
  PlatformReminderStore(this._db);

  final AppDatabase _db;

  Future<void> replaceAll(Iterable<PlatformReminderWrite> reminders) async {
    final scheduledAt = AppClock.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      for (final reminder in reminders) {
        await _db.customStatement(
          'INSERT INTO platform_reminder_state '
          '(id, kind, entity_id, occurrence_start_ms, fire_at, scheduled_at, '
          'delivered_at, snoozed_from, owner, degraded) '
          'VALUES (?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?) '
          'ON CONFLICT(id) DO UPDATE SET '
          'kind = excluded.kind, entity_id = excluded.entity_id, '
          'occurrence_start_ms = excluded.occurrence_start_ms, '
          'fire_at = excluded.fire_at, scheduled_at = excluded.scheduled_at, '
          'delivered_at = NULL, owner = excluded.owner, '
          'degraded = excluded.degraded',
          [
            reminder.id,
            reminder.kind,
            reminder.entityId,
            reminder.occurrenceStart.millisecondsSinceEpoch,
            reminder.fireAt.millisecondsSinceEpoch,
            scheduledAt,
            reminder.owner,
            reminder.degraded ? 1 : 0,
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

  /// Due records that have not been delivered yet. They must be kept when the
  /// scheduler prunes obsolete rows, otherwise a reminder that came due while
  /// Locus was closed would disappear before the missed-reminder inbox sees it.
  Future<List<PlatformReminderState>> undeliveredBefore(DateTime now) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM platform_reminder_state '
          'WHERE delivered_at IS NULL AND fire_at <= ? ORDER BY fire_at',
          variables: [Variable.withInt(now.millisecondsSinceEpoch)],
        )
        .get();
    return [for (final row in rows) _fromRow(row)];
  }

  /// Windows confirmed these occurrences at scheduling time, so a fired toast
  /// was delivered even if the app was not running to acknowledge it. Marking
  /// them delivered before building the missed list prevents duplicates.
  Future<void> markConfirmedFiredDelivered(DateTime now) async {
    await _db.customStatement(
      'UPDATE platform_reminder_state SET delivered_at = ? '
      "WHERE delivered_at IS NULL AND owner = 'os' AND fire_at <= ?",
      [now.millisecondsSinceEpoch, now.millisecondsSinceEpoch],
    );
  }

  /// Snoozes survive a refresh: the row keeps its identity and stores the
  /// reminder it was snoozed from. [fireAt] is the new absolute instant.
  Future<void> markSnoozed({
    required String id,
    required DateTime fireAt,
    required String snoozedFrom,
    String? owner,
    bool? degraded,
  }) async {
    await _db.customStatement(
      'UPDATE platform_reminder_state SET fire_at = ?, delivered_at = NULL, '
      'snoozed_from = ?, owner = COALESCE(?, owner), '
      'degraded = COALESCE(?, degraded) WHERE id = ?',
      [
        fireAt.millisecondsSinceEpoch,
        snoozedFrom,
        owner,
        degraded == null ? null : (degraded ? 1 : 0),
        id,
      ],
    );
  }

  /// Ids already delivered, used to retire inbox snoozes that Windows showed
  /// while Locus was closed.
  Future<Set<String>> deliveredIds() async {
    final rows = await _db
        .customSelect(
          'SELECT id FROM platform_reminder_state '
          'WHERE delivered_at IS NOT NULL',
        )
        .get();
    return {for (final row in rows) row.read<String>('id')};
  }

  Future<List<PlatformReminderState>> activeSnoozes() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM platform_reminder_state '
          'WHERE snoozed_from IS NOT NULL AND delivered_at IS NULL '
          'ORDER BY fire_at',
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

  static PlatformReminderState _fromRow(dynamic row) {
    final fireAt = DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('fire_at'),
    );
    final occurrenceStartMs = row.readNullable<int>('occurrence_start_ms');
    return PlatformReminderState(
      id: row.read<String>('id'),
      kind: row.read<String>('kind'),
      entityId: row.read<String>('entity_id'),
      occurrenceStart: occurrenceStartMs == null
          ? fireAt
          : DateTime.fromMillisecondsSinceEpoch(occurrenceStartMs),
      fireAt: fireAt,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        row.read<int>('scheduled_at'),
      ),
      deliveredAt: row.readNullable<int>('delivered_at') == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.read<int>('delivered_at')),
      snoozedFrom: row.readNullable<String>('snoozed_from'),
      owner: row.readNullable<String>('owner') ?? 'unknown',
      degraded: (row.readNullable<int>('degraded') ?? 0) != 0,
    );
  }
}
