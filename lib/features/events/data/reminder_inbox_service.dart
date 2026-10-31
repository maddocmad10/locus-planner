import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/recurrence.dart';

/// One occurrence whose reminder time passed while Locus was not able to show
/// it. [occurrenceStart] is the event's start, not the reminder time.
class MissedReminder {
  const MissedReminder({
    required this.eventId,
    required this.title,
    required this.occurrenceStart,
    required this.reminderAt,
  });

  final String eventId;
  final String title;
  final DateTime occurrenceStart;
  final DateTime reminderAt;

  /// Stable per event occurrence, matching the phone's reminder ids.
  String get key => '$eventId@${occurrenceStart.millisecondsSinceEpoch}';

  MissedReminder copyWithTitle(String value) => MissedReminder(
    eventId: eventId,
    title: value,
    occurrenceStart: occurrenceStart,
    reminderAt: reminderAt,
  );

  Map<String, Object> toJson() => {
    'eventId': eventId,
    'title': title,
    'occurrenceStart': occurrenceStart.millisecondsSinceEpoch,
    'reminderAt': reminderAt.millisecondsSinceEpoch,
  };

  factory MissedReminder.fromJson(Map<String, dynamic> json) => MissedReminder(
    eventId: json['eventId'] as String,
    title: json['title'] as String? ?? 'Event reminder',
    occurrenceStart: DateTime.fromMillisecondsSinceEpoch(
      json['occurrenceStart'] as int,
    ),
    reminderAt: DateTime.fromMillisecondsSinceEpoch(json['reminderAt'] as int),
  );
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
    final events = await _db.select(_db.events).get();
    final eventsById = {for (final event in events) event.id: event};

    final pending = <String, MissedReminder>{};
    if (remindersEnabled) {
      for (final item in await _readPending()) {
        final event = eventsById[item.eventId];
        if (event == null || !event.hasReminder) continue;
        if (item.reminderAt.isBefore(now.subtract(retention))) continue;
        pending[item.key] = item.copyWithTitle(event.title);
      }
    }

    final snoozed = <String, SnoozedReminder>{};
    for (final item in await _readSnoozed()) {
      final event = eventsById[item.reminder.eventId];
      if (event == null || !event.hasReminder) continue;
      if (item.reminder.reminderAt.isBefore(now.subtract(retention))) continue;
      final entry = item.copyWithTitle(event.title);
      if (entry.snoozeUntil.isAfter(now)) {
        snoozed[entry.key] = entry;
        pending.remove(entry.key);
        await _armSnooze(entry);
      } else if (remindersEnabled) {
        // The snooze expired while Locus was closed. It goes back to the
        // missed list and is no longer a pending snooze.
        pending.putIfAbsent(entry.key, () => entry.reminder);
      } else {
        // Keep the expired snooze until reminders are switched back on.
        snoozed[entry.key] = entry;
      }
    }

    if (remindersEnabled) {
      final lastRunning = _parseDate(
        await _db.getSetting(AppDatabase.remindersLastRunningSettingKey),
      );
      final from = _windowStart(lastRunning, now);
      if (from != null) {
        for (final item in computeMissedReminders(
          events,
          from: from,
          now: now,
        )) {
          pending.putIfAbsent(item.key, () => item);
        }
      }
    }

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
            eventId: event.id,
            title: event.title,
            occurrenceStart: occurrence.startTime,
            reminderAt: reminderAt,
          ),
        );
      }
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
  }) async {
    if (!_started || _disposed || !_notifications.eventRemindersEnabled) {
      return;
    }
    final now = _now();
    if (reminderAt.isAfter(now)) return;
    if (reminderAt.isBefore(now.subtract(retention))) return;

    final entry = MissedReminder(
      eventId: eventId,
      title: title,
      occurrenceStart: occurrenceStart,
      reminderAt: reminderAt,
    );
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
    await _persistPending();
    _publish();
  }

  /// Hides [reminder] and schedules it again after [duration]. The snooze is
  /// persisted, so quitting Locus during it does not lose the reminder.
  Future<void> snooze(MissedReminder reminder, Duration duration) async {
    final entry = SnoozedReminder(
      reminder: reminder,
      snoozeUntil: _now().add(duration),
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
    if (!_notifications.eventRemindersEnabled) return;
    final now = _now();
    var changed = false;
    for (final entry in _snoozed.values.toList()) {
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
    await _notifications.scheduleEventReminder(
      eventId: 'snooze:${entry.key}',
      title: entry.reminder.title,
      scheduledTime: entry.snoozeUntil,
      body: 'Snoozed reminder',
      onTriggered: () async {
        _snoozed.remove(entry.key);
        await _persistSnoozed();
      },
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
