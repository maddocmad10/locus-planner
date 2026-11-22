import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/reminder_kind.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/reminders/platform_reminder_store.dart';
import '../../../core/reminders/reminder_identity.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/recurrence.dart';

/// What a missed reminder belongs to.
/// One occurrence whose reminder time passed while Locus was not able to show
/// it. For events [dueAt] is the occurrence start; for tasks it is
/// `reminder_at`.
class MissedReminder {
  const MissedReminder({
    required this.kind,
    required this.entityId,
    required this.title,
    required this.dueAt,
    required this.reminderAt,
    this.owner,
    this.degraded = false,
  });

  final ReminderKind kind;
  final String entityId;
  final String title;
  final DateTime dueAt;
  final DateTime reminderAt;

  /// Platform ownership recorded by the Windows scheduler (`os`, `app`,
  /// `unknown`). Null for reminders reconstructed from the calendar scan.
  final String? owner;

  /// True when the OS did not confirm the occurrence, so only an in-process
  /// fallback can show it.
  final bool degraded;

  String get eventId => entityId;

  DateTime get occurrenceStart => dueAt;

  bool get needsAppRunning => degraded || owner == 'app' || owner == 'unknown';

  /// Stable per kind, entity and occurrence.
  String get key => canonicalReminderKey(kind, entityId, dueAt);

  MissedReminder copyWithTitle(String value) => MissedReminder(
    kind: kind,
    entityId: entityId,
    title: value,
    dueAt: dueAt,
    reminderAt: reminderAt,
    owner: owner,
    degraded: degraded,
  );

  Map<String, Object> toJson() => {
    'kind': kind.name,
    'entityId': entityId,
    'title': title,
    'dueAt': dueAt.millisecondsSinceEpoch,
    'reminderAt': reminderAt.millisecondsSinceEpoch,
    'owner': ?owner,
    if (degraded) 'degraded': true,
  };

  factory MissedReminder.fromJson(Map<String, dynamic> json) {
    // Older inbox rows have no kind/entityId and are always events. They used
    // `occurrenceStart` for the due time.
    final kind = ReminderKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => ReminderKind.event,
    );
    final entityId = json['entityId'] ?? json['eventId'];
    final dueAt = json['dueAt'] ?? json['occurrenceStart'];
    return MissedReminder(
      kind: kind,
      entityId: entityId as String,
      title: json['title'] as String? ?? 'Reminder',
      dueAt: DateTime.fromMillisecondsSinceEpoch(dueAt as int),
      reminderAt: DateTime.fromMillisecondsSinceEpoch(
        json['reminderAt'] as int,
      ),
      owner: json['owner'] as String?,
      degraded: json['degraded'] == true,
    );
  }
}

/// A missed reminder the user has postponed. It survives a restart: before its
/// time it is re-armed, after its time it returns to the missed list.
class SnoozedReminder {
  const SnoozedReminder({required this.reminder, required this.snoozeUntil});

  final MissedReminder reminder;
  final DateTime snoozeUntil;

  String get key => reminder.key;

  SnoozedReminder copyWithTitle(String title) => SnoozedReminder(
    reminder: reminder.copyWithTitle(title),
    snoozeUntil: snoozeUntil,
  );

  Map<String, Object> toJson() => {
    ...reminder.toJson(),
    'snoozeUntil': snoozeUntil.millisecondsSinceEpoch,
  };

  factory SnoozedReminder.fromJson(Map<String, dynamic> json) =>
      SnoozedReminder(
        reminder: MissedReminder.fromJson(json),
        snoozeUntil: DateTime.fromMillisecondsSinceEpoch(
          json['snoozeUntil'] as int,
        ),
      );
}

/// Remembers reminders that were due while the desktop app was closed.
///
/// Windows reminders are in-memory timers inside [NotificationService], so a
/// fully quit Locus cannot show them. This service closes that gap without a
/// schema migration:
///
/// * A heartbeat records when the desktop last ran.
/// * On the next start, reminder times between that heartbeat and now are
///   collected from the events table, including repeats of recurring events.
/// * The inbox, acknowledgements and pending snoozes are persisted as JSON in
///   [AppDatabase.appSettings]. They are machine state and therefore excluded
///   from backups.
class ReminderInboxService {
  ReminderInboxService(
    this._db,
    this._notifications, {
    DateTime Function()? now,
  }) : _now = now ?? AppClock.now;

  /// How far back a missed reminder is allowed to reach. Opening Locus after
  /// a long absence must not bury the user under weeks of old reminders.
  static const retention = Duration(days: 7);

  /// Keeps the persisted inbox small.
  static const maxPending = 50;

  static const heartbeatInterval = Duration(minutes: 1);

  final AppDatabase _db;
  final NotificationService _notifications;
  final DateTime Function() _now;
  final StreamController<List<MissedReminder>> _changes =
      StreamController<List<MissedReminder>>.broadcast();
  final List<MissedReminder> _pending = [];
  final Map<String, SnoozedReminder> _snoozed = {};
  Future<void>? _startFuture;
  Timer? _heartbeat;
  bool _started = false;
  bool _disposed = false;

  Stream<List<MissedReminder>> get changes => _changes.stream;

  List<MissedReminder> get current =>
      List<MissedReminder>.unmodifiable(_pending);

  /// Detects missed reminders once per app launch. Safe to call repeatedly;
  /// every caller shares the same first run.
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    // The dashboard can ask for missed reminders before the optional startup
    // sequence reaches NotificationService. Share its initialization so the
    // native notifier is never set up twice.
    await _notifications.init();
    final now = _now();
    final remindersEnabled = _notifications.eventRemindersEnabled;
    final taskRemindersEnabled = _notifications.taskRemindersEnabled;
    final events = await _db.select(_db.events).get();
    final eventsById = {for (final event in events) event.id: event};
    final tasks = await _db.select(_db.todoItems).get();
    final tasksById = {for (final task in tasks) task.id: task};

    final pending = <String, MissedReminder>{};
    if (remindersEnabled || taskRemindersEnabled) {
      for (final item in await _readPending()) {
        if (item.kind == ReminderKind.event) {
          final event = eventsById[item.entityId];
          if (!remindersEnabled || event == null || !event.hasReminder) {
            continue;
          }
          if (item.reminderAt.isBefore(now.subtract(retention))) continue;
          pending[item.key] = item.copyWithTitle(event.title);
        } else {
          final task = tasksById[item.entityId];
          if (!taskRemindersEnabled ||
              task == null ||
              task.completed ||
              task.reminderAt == null ||
              task.reminderAt!.millisecondsSinceEpoch !=
                  item.dueAt.millisecondsSinceEpoch) {
            continue;
          }
          if (item.reminderAt.isBefore(now.subtract(retention))) continue;
          pending[item.key] = item.copyWithTitle(task.title);
        }
      }
    }

    final deliveredPlatformIds = await PlatformReminderStore(
      _db,
    ).deliveredIds();
    final snoozed = <String, SnoozedReminder>{};
    for (final item in await _readSnoozed()) {
      final reminder = item.reminder;
      final occurrence = ReminderOccurrence(
        kind: reminder.kind,
        entityId: reminder.entityId,
        occurrenceStart: reminder.occurrenceStart,
      );
      // Windows already showed this snooze while Locus was closed. Retire the
      // inbox copy instead of returning it to the missed list.
      if (deliveredPlatformIds.contains(occurrence.stableId)) continue;
      final enabled = reminder.kind == ReminderKind.event
          ? remindersEnabled
          : taskRemindersEnabled;
      if (!enabled) {
        snoozed[item.key] = item;
        continue;
      }
      String title;
      if (reminder.kind == ReminderKind.event) {
        final event = eventsById[reminder.entityId];
        if (event == null || !event.hasReminder) continue;
        title = event.title;
      } else {
        final task = tasksById[reminder.entityId];
        if (task == null || task.completed || task.reminderAt == null) {
          continue;
        }
        title = task.title;
      }
      if (reminder.reminderAt.isBefore(now.subtract(retention))) continue;
      final entry = item.copyWithTitle(title);
      if (entry.snoozeUntil.isAfter(now)) {
        snoozed[entry.key] = entry;
        pending.remove(entry.key);
        await _armSnooze(entry);
      } else if (enabled) {
        // The snooze expired while Locus was closed. It goes back to the
        // missed list and is no longer a pending snooze.
        pending.putIfAbsent(entry.key, () => entry.reminder);
      } else {
        snoozed[entry.key] = entry;
      }
    }

    if (remindersEnabled || taskRemindersEnabled) {
      final lastRunning = _parseDate(
        await _db.getSetting(AppDatabase.remindersLastRunningSettingKey),
      );
      final from = _windowStart(lastRunning, now);
      if (from != null) {
        if (remindersEnabled) {
          for (final item in computeMissedReminders(
            events,
            from: from,
            now: now,
          )) {
            pending.putIfAbsent(item.key, () => item);
          }
        }
        if (taskRemindersEnabled) {
          for (final item in computeMissedTaskReminders(
            tasks,
            from: from,
            now: now,
          )) {
            pending.putIfAbsent(item.key, () => item);
          }
        }
      }
    }

    // Toast Snooze writes to the device-local platform store. Merge it here so
    // the two snooze namespaces cannot disagree after a restart.
    await _mergePlatformSnoozes(
      now,
      eventsById: eventsById,
      tasksById: tasksById,
      pending: pending,
      snoozed: snoozed,
    );

    final trimmed = _trim(pending.values);
    _pending
      ..clear()
      ..addAll(trimmed);
    _snoozed
      ..clear()
      ..addAll(snoozed);
    _started = true;
    await _persistPending();
    await _persistSnoozed();
    await _db.setSetting(
      AppDatabase.remindersLastRunningSettingKey,
      now.toIso8601String(),
    );
    _publish();
    _heartbeat ??= Timer.periodic(
      heartbeatInterval,
      (_) => unawaited(_touch()),
    );
  }

  /// Merges a snooze created by the Windows toast action into the inbox.
  /// Called at startup and after the `locus://snooze` activation so the
  /// platform store and the persisted inbox cannot diverge.
  Future<void> reconcilePlatformSnoozes() async {
    if (!_started || _disposed) return;
    final now = _now();
    final events = await _db.select(_db.events).get();
    final tasks = await _db.select(_db.todoItems).get();
    final pending = <String, MissedReminder>{
      for (final item in _pending) item.key: item,
    };
    final snoozed = <String, SnoozedReminder>{..._snoozed};
    await _mergePlatformSnoozes(
      now,
      eventsById: {for (final event in events) event.id: event},
      tasksById: {for (final task in tasks) task.id: task},
      pending: pending,
      snoozed: snoozed,
    );
    final trimmed = _trim(pending.values);
    _pending
      ..clear()
      ..addAll(trimmed);
    _snoozed
      ..clear()
      ..addAll(snoozed);
    await _persistPending();
    await _persistSnoozed();
    _publish();
  }

  Future<void> _mergePlatformSnoozes(
    DateTime now, {
    required Map<String, Event> eventsById,
    required Map<String, TodoItem> tasksById,
    required Map<String, MissedReminder> pending,
    required Map<String, SnoozedReminder> snoozed,
  }) async {
    final store = PlatformReminderStore(_db);
    final states = await store.activeSnoozes();
    for (final state in states) {
      final kind = state.reminderKind;
      final enabled = kind == ReminderKind.event
          ? _notifications.eventRemindersEnabled
          : _notifications.taskRemindersEnabled;
      if (!enabled) continue;

      final entityId = state.entityId;
      final DateTime dueAt;
      final DateTime reminderAt;
      final String title;
      if (kind == ReminderKind.event) {
        final event = eventsById[entityId];
        if (event == null || !event.hasReminder) continue;
        dueAt = state.occurrenceStart;
        reminderAt = dueAt.subtract(Duration(minutes: event.reminderMinutes));
        title = event.title;
      } else {
        final task = tasksById[entityId];
        if (task == null || task.completed) continue;
        dueAt = task.reminderAt ?? state.occurrenceStart;
        reminderAt = dueAt;
        title = task.title;
      }

      final entry = SnoozedReminder(
        reminder: MissedReminder(
          kind: kind,
          entityId: entityId,
          title: title,
          dueAt: dueAt,
          reminderAt: reminderAt,
          owner: state.owner,
          degraded: state.degraded,
        ),
        snoozeUntil: state.fireAt,
      );
      final existing = snoozed[entry.key];
      if (existing != null &&
          !entry.snoozeUntil.isAfter(existing.snoozeUntil)) {
        continue;
      }
      if (entry.snoozeUntil.isAfter(now)) {
        snoozed[entry.key] = entry;
        pending.remove(entry.key);
        await _armSnooze(entry);
      } else {
        // The snooze expired while Locus was closed. An OS-owned toast was
        // delivered by Windows; an in-process one never ran, so it belongs in
        // the missed list.
        await store.markDelivered([state.id]);
        snoozed.remove(entry.key);
        if (state.owner != 'os') {
          pending.putIfAbsent(entry.key, () => entry.reminder);
        }
      }
    }
  }

  /// Pure occurrence calculation, kept separate so the window rules are easy
  /// to test without a database.
  static List<MissedReminder> computeMissedReminders(
    Iterable<Event> events, {
    required DateTime from,
    required DateTime now,
  }) {
    if (!from.isBefore(now)) return const [];
    final withReminders = events
        .where((event) => event.hasReminder && event.reminderMinutes >= 0)
        .toList();
    if (withReminders.isEmpty) return const [];

    // A reminder fires before its event, so an occurrence starting after now
    // can still have a reminder inside the window.
    final maxLeadMinutes = withReminders.fold<int>(
      0,
      (longest, event) =>
          event.reminderMinutes > longest ? event.reminderMinutes : longest,
    );
    final to = now.add(Duration(minutes: maxLeadMinutes));

    final result = <MissedReminder>[];
    for (final event in withReminders) {
      final lead = Duration(minutes: event.reminderMinutes);
      for (final occurrence in Recurrence.expand(event, from, to)) {
        final reminderAt = occurrence.startTime.subtract(lead);
        if (!reminderAt.isAfter(from) || reminderAt.isAfter(now)) continue;
        result.add(
          MissedReminder(
            kind: ReminderKind.event,
            entityId: event.id,
            title: event.title,
            dueAt: occurrence.startTime,
            reminderAt: reminderAt,
          ),
        );
      }
    }
    return _sortReminders(result);
  }

  /// Tasks whose `reminder_at` fell inside [from]..[now].
  static List<MissedReminder> computeMissedTaskReminders(
    Iterable<TodoItem> tasks, {
    required DateTime from,
    required DateTime now,
  }) {
    if (!from.isBefore(now)) return const [];
    final result = <MissedReminder>[];
    for (final task in tasks) {
      final reminderAt = task.reminderAt;
      if (task.completed || reminderAt == null) continue;
      if (reminderAt.isBefore(from) || reminderAt.isAfter(now)) continue;
      result.add(
        MissedReminder(
          kind: ReminderKind.task,
          entityId: task.id,
          title: task.title,
          dueAt: reminderAt,
          reminderAt: reminderAt,
        ),
      );
    }
    return _sortReminders(result);
  }

  /// Adds a reminder that became too late while the app was running, for
  /// example because the laptop was asleep. The notification layer calls this
  /// instead of silently dropping it.
  Future<void> rememberMissed({
    required String eventId,
    required String title,
    required DateTime occurrenceStart,
    required DateTime reminderAt,
    String? owner,
    bool degraded = false,
  }) async {
    final entry = MissedReminder(
      kind: ReminderKind.event,
      entityId: eventId,
      title: title,
      dueAt: occurrenceStart,
      reminderAt: reminderAt,
      owner: owner,
      degraded: degraded,
    );
    await _remember(entry, enabled: _notifications.eventRemindersEnabled);
  }

  /// Adds a late task reminder to the inbox. Called by the notification layer
  /// when a task reminder fires after its 15-minute popup window.
  Future<void> rememberMissedTask({
    required String taskId,
    required String title,
    required DateTime reminderAt,
    String? owner,
    bool degraded = false,
  }) async {
    final entry = MissedReminder(
      kind: ReminderKind.task,
      entityId: taskId,
      title: title,
      dueAt: reminderAt,
      reminderAt: reminderAt,
      owner: owner,
      degraded: degraded,
    );
    await _remember(entry, enabled: _notifications.taskRemindersEnabled);
  }

  Future<void> _remember(MissedReminder entry, {required bool enabled}) async {
    if (!_started || _disposed || !enabled) return;
    final now = _now();
    if (entry.reminderAt.isAfter(now)) return;
    if (entry.reminderAt.isBefore(now.subtract(retention))) return;

    final existing = _pending.indexWhere((item) => item.key == entry.key);
    if (existing >= 0) {
      _pending[existing] = entry;
    } else {
      _pending.add(entry);
    }
    final trimmed = _trim(_pending);
    _pending
      ..clear()
      ..addAll(trimmed);
    await _persistPending();
    _publish();
  }

  Future<void> dismiss(MissedReminder reminder) async {
    _pending.removeWhere((item) => item.key == reminder.key);
    final occurrence = ReminderOccurrence(
      kind: reminder.kind,
      entityId: reminder.entityId,
      occurrenceStart: reminder.occurrenceStart,
    );
    await PlatformReminderStore(_db).markDelivered([occurrence.stableId]);
    await _persistPending();
    _publish();
  }

  /// Hides [reminder] and schedules it again after [duration]. The snooze is
  /// persisted in both stores, so quitting Locus during it does not lose the
  /// reminder and the Windows scheduler cannot re-schedule the old instant.
  Future<void> snooze(MissedReminder reminder, Duration duration) async {
    final entry = SnoozedReminder(
      reminder: reminder,
      snoozeUntil: _now().add(duration),
    );
    final occurrence = ReminderOccurrence(
      kind: reminder.kind,
      entityId: reminder.entityId,
      occurrenceStart: reminder.occurrenceStart,
    );
    final store = PlatformReminderStore(_db);
    await store.replaceAll([
      PlatformReminderWrite(
        id: occurrence.stableId,
        kind: reminder.kind.name,
        entityId: reminder.entityId,
        occurrenceStart: reminder.occurrenceStart,
        fireAt: entry.snoozeUntil,
        owner: 'app',
        degraded: true,
      ),
    ]);
    await store.markSnoozed(
      id: occurrence.stableId,
      fireAt: entry.snoozeUntil,
      snoozedFrom: occurrence.stableId,
      owner: 'app',
      degraded: true,
    );
    _snoozed[entry.key] = entry;
    _pending.removeWhere((item) => item.key == reminder.key);
    await _persistSnoozed();
    await _persistPending();
    _publish();
    await _armSnooze(entry);
  }

  /// Re-arms persisted snoozes after event reminders are switched back on.
  /// Snoozes that expired while reminders were off return to the missed list.
  Future<void> rearmSnoozes() async {
    final now = _now();
    var changed = false;
    for (final entry in _snoozed.values.toList()) {
      final enabled = entry.reminder.kind == ReminderKind.event
          ? _notifications.eventRemindersEnabled
          : _notifications.taskRemindersEnabled;
      if (!enabled) continue;
      if (entry.snoozeUntil.isAfter(now)) {
        await _armSnooze(entry);
      } else {
        _snoozed.remove(entry.key);
        if (!_pending.any((item) => item.key == entry.key)) {
          _pending.add(entry.reminder);
        }
        changed = true;
      }
    }
    if (!changed) return;
    final trimmed = _trim(_pending);
    _pending
      ..clear()
      ..addAll(trimmed);
    await _persistPending();
    await _persistSnoozed();
    _publish();
  }

  /// Records the end of this session so the next launch only counts the time
  /// the app was actually closed.
  Future<void> markStopped() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    if (_disposed) return;
    try {
      await _db.setSetting(
        AppDatabase.remindersLastRunningSettingKey,
        _now().toIso8601String(),
      );
    } catch (_) {
      // Shutdown must finish even if the database is already closing.
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _heartbeat?.cancel();
    _heartbeat = null;
    unawaited(_changes.close());
  }

  Future<void> _armSnooze(SnoozedReminder entry) async {
    final reminder = entry.reminder;
    final occurrence = ReminderOccurrence(
      kind: reminder.kind,
      entityId: reminder.entityId,
      occurrenceStart: reminder.occurrenceStart,
    );
    var skippedLate = false;
    Future<void> finish() async {
      _snoozed.remove(entry.key);
      if (skippedLate) {
        // A snooze that passed while the machine slept belongs in the missed
        // list, not silently lost or shown as if it fired on time.
        if (!_pending.any((item) => item.key == entry.key)) {
          _pending.add(entry.reminder);
        }
        final trimmed = _trim(_pending);
        _pending
          ..clear()
          ..addAll(trimmed);
        await _persistPending();
      } else {
        await PlatformReminderStore(_db).markDelivered([occurrence.stableId]);
      }
      await _persistSnoozed();
      _publish();
    }

    Future<void> skipped() async {
      skippedLate = true;
    }

    if (reminder.kind == ReminderKind.task) {
      await _notifications.scheduleTaskReminder(
        taskId: reminder.entityId,
        reminderId: occurrence.key,
        stableId: occurrence.stableId,
        title: reminder.title,
        scheduledTime: entry.snoozeUntil,
        body: 'Snoozed task reminder',
        onSkippedLate: skipped,
        onTriggered: finish,
      );
      return;
    }
    await _notifications.scheduleEventReminder(
      eventId: reminder.entityId,
      reminderId: occurrence.key,
      stableId: occurrence.stableId,
      title: reminder.title,
      scheduledTime: entry.snoozeUntil,
      body: 'Snoozed reminder',
      onSkippedLate: skipped,
      onTriggered: finish,
    );
  }

  Future<void> _touch() async {
    if (_disposed) return;
    try {
      await _db.setSetting(
        AppDatabase.remindersLastRunningSettingKey,
        _now().toIso8601String(),
      );
    } catch (_) {
      // A heartbeat is a best-effort safety net, never a startup blocker.
    }
  }

  DateTime? _windowStart(DateTime? lastRunning, DateTime now) {
    if (lastRunning == null) return null;
    if (!lastRunning.isBefore(now)) return null;
    final earliest = now.subtract(retention);
    return lastRunning.isBefore(earliest) ? earliest : lastRunning;
  }

  static List<MissedReminder> _sortReminders(
    Iterable<MissedReminder> reminders,
  ) {
    final sorted = reminders.toList()
      ..sort((a, b) {
        final byTime = b.reminderAt.compareTo(a.reminderAt);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return sorted;
  }

  static List<MissedReminder> _trim(Iterable<MissedReminder> reminders) {
    final sorted = _sortReminders(reminders);
    return sorted.length <= maxPending ? sorted : sorted.sublist(0, maxPending);
  }

  void _publish() {
    if (_disposed || _changes.isClosed) return;
    _changes.add(List<MissedReminder>.unmodifiable(_pending));
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  Future<List<MissedReminder>> _readPending() async {
    final raw = await _db.getSetting(AppDatabase.remindersPendingSettingKey);
    if (raw == null || raw.isEmpty) return const [];
    final result = <MissedReminder>[];
    for (final item in _decodeList(raw)) {
      try {
        result.add(MissedReminder.fromJson(item));
      } catch (_) {
        // One corrupt row must not discard the rest of the inbox.
      }
    }
    return result;
  }

  Future<List<SnoozedReminder>> _readSnoozed() async {
    final raw = await _db.getSetting(AppDatabase.remindersSnoozedSettingKey);
    if (raw == null || raw.isEmpty) return const [];
    final result = <SnoozedReminder>[];
    for (final item in _decodeList(raw)) {
      try {
        result.add(SnoozedReminder.fromJson(item));
      } catch (_) {
        // See _readPending.
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _decodeList(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return [
        for (final item in value)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> _persistPending() => _db.setSetting(
    AppDatabase.remindersPendingSettingKey,
    jsonEncode([for (final item in _pending) item.toJson()]),
  );

  Future<void> _persistSnoozed() => _db.setSetting(
    AppDatabase.remindersSnoozedSettingKey,
    jsonEncode([for (final item in _snoozed.values) item.toJson()]),
  );
}

final reminderInboxServiceProvider = Provider<ReminderInboxService>((ref) {
  final service = ReminderInboxService(
    ref.watch(databaseProvider),
    ref.watch(notificationServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final missedRemindersProvider = StreamProvider<List<MissedReminder>>((
  ref,
) async* {
  final service = ref.watch(reminderInboxServiceProvider);
  await service.start();
  yield service.current;
  yield* service.changes;
});
