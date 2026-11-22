import 'dart:async';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../models/reminder_kind.dart';
import '../services/notification_service.dart';
import '../utils/app_clock.dart';
import 'platform_reminder_store.dart';
import 'reminder_planner.dart';
import 'windows_toast_platform.dart';

/// Plans and reconciles OS-scheduled Windows reminders.
class WindowsReminderService {
  WindowsReminderService(
    this._db, {
    WindowsToastPlatform toastPlatform = const WindowsToastPlatform(),
    PlatformReminderStore? store,
    NotificationService? notificationService,
  }) : _toast = toastPlatform,
       _store = store ?? PlatformReminderStore(_db),
       _notification = notificationService;

  static const maxScheduled = 1000;

  final AppDatabase _db;
  final WindowsToastPlatform _toast;
  final PlatformReminderStore _store;
  final NotificationService? _notification;
  StreamSubscription<List<Event>>? _eventSubscription;
  StreamSubscription<List<TodoItem>>? _taskSubscription;
  Timer? _midnightTimer;
  Future<void>? _inFlight;
  bool _again = false;
  Future<void> _queue = Future<void>.value();

  /// OS-confirmed occurrence ids from the most recent pass.
  Set<String> _confirmedIds = const <String>{};

  Set<String> get confirmedIds => Set<String>.unmodifiable(_confirmedIds);

  Future<void> start() async {
    NotificationService.platformSchedulerActive = true;
    _eventSubscription ??= _db.watchAllEvents().listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {},
    );
    _taskSubscription ??= _db.watchAllTodoItems().listen(
      (_) => unawaited(refresh()),
      onError: (Object _) {},
    );
    _scheduleMidnight();
    await refresh();
  }

  /// The single startup gate. It drains every coalesced refresh, then returns
  /// the ids Windows confirmed so repositories can arm fallbacks only for the
  /// occurrences the OS does not own.
  Future<Set<String>> reconcileStartup() async {
    await start();
    return Set<String>.unmodifiable(_confirmedIds);
  }

  Future<void> stop() async {
    NotificationService.clearOsScheduledIds();
    _midnightTimer?.cancel();
    _midnightTimer = null;
    final events = _eventSubscription;
    final tasks = _taskSubscription;
    _eventSubscription = null;
    _taskSubscription = null;
    await events?.cancel();
    await tasks?.cancel();
  }

  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    final run = _serialized(_drain);
    _inFlight = run;
    return run;
  }

  /// Runs [action] after every earlier serialized scheduler operation. Snooze
  /// and refresh share this lock so a native schedule cannot interleave with a
  /// reconciliation pass.
  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Confirmed OS-owned reminders that fired are delivered; only occurrences
  /// the app had to show itself (or could not enumerate) reach the inbox.
  Future<List<PlatformReminderState>> takeMissed() async {
    final now = AppClock.now();
    await _store.markConfirmedFiredDelivered(now);
    final missed = await _store.missedBefore(now);
    if (missed.isNotEmpty) {
      await _store.markDelivered(missed.map((row) => row.id));
    }
    return missed;
  }

  /// Reschedules one reminder from a toast Snooze action. The row keeps its
  /// identity and records the reminder it was snoozed from, so a later refresh
  /// or restart cannot forget or duplicate it.
  Future<void> snooze(String id, int minutes) {
    return _serialized(() async {
      final rows = await _store.all();
      PlatformReminderState? target;
      for (final row in rows) {
        if (row.id == id) target = row;
      }
      if (target == null) return;
      final kind = target.reminderKind;
      if (!await _enabledFor(kind)) return;

      final occurrence = target.occurrence;
      final fireAt = AppClock.now().add(Duration(minutes: minutes));
      final hideTitles =
          await _db.getSetting(AppDatabase.hideNotificationTitlesSettingKey) ==
          '1';
      final title = hideTitles
          ? 'Locus reminder'
          : (kind == ReminderKind.task ? 'Task reminder' : 'Event reminder');

      // The old in-process fallback for this occurrence is superseded by the
      // snoozed instant regardless of whether Windows accepts it.
      _notification?.cancelReminderId(occurrence.key);

      final scheduled = await _toast.schedule([
        {
          'id': target.id,
          'fireAtEpochMs': fireAt.millisecondsSinceEpoch,
          'title': title,
          'body': '',
          'launchUri': _launchUriFor(kind, target.entityId),
        },
      ]);
      await _store.markSnoozed(
        id: target.id,
        fireAt: fireAt,
        snoozedFrom: target.snoozedFrom ?? target.id,
        owner: scheduled ? 'os' : 'app',
        degraded: !scheduled,
      );
      if (scheduled) {
        NotificationService.addOsOwnedId(target.id);
        _confirmedIds = {..._confirmedIds, target.id};
      } else {
        NotificationService.removeOsOwnedId(target.id);
        _confirmedIds = {..._confirmedIds}..remove(target.id);
        await _recordSchedulingHealth(degraded: true);
        _armFallback(
          PlannedReminder(
            kind: kind,
            entityId: target.entityId,
            id: occurrence.key,
            occurrenceStart: target.occurrenceStart,
            fireAt: fireAt,
            title: title,
            body: '',
          ),
          title: title,
        );
      }
    });
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        _confirmedIds = await _apply();
      } while (_again);
    } finally {
      _inFlight = null;
    }
  }

  Future<Set<String>> _apply() async {
    final eventsEnabled = await _enabledFor(ReminderKind.event);
    final tasksEnabled = await _enabledFor(ReminderKind.task);
    final now = AppClock.now();

    if (!eventsEnabled) _notification?.cancelAllEventReminders();
    if (!tasksEnabled) _notification?.cancelAllTaskReminders();

    if (!eventsEnabled && !tasksEnabled) {
      try {
        await _toast.cancelAllExcept(const {});
      } catch (_) {
        // Reconciliation must continue even when the native side is unhappy.
      }
      await _store.removeExcept(const {});
      NotificationService.setOsOwned(ids: const {}, entityKeys: const {});
      await _recordSchedulingHealth(degraded: false);
      await _updateBadge(now);
      return const {};
    }

    final sources = <PlannedSource>[
      if (eventsEnabled)
        ...ReminderPlanner.sourcesForEvents(
          await _db.select(_db.events).get(),
          now: now,
        ),
      if (tasksEnabled)
        ...ReminderPlanner.sourcesForTasks(
          await _db.select(_db.todoItems).get(),
          now: now,
        ),
    ];
    final plan = ReminderPlanner.plan(
      sources,
      now: now,
      totalLimit: maxScheduled,
    );
    final hideTitles =
        await _db.getSetting(AppDatabase.hideNotificationTitlesSettingKey) ==
        '1';

    // Map keyed by the OS-visible stable id.
    final desired = <String, PlannedReminder>{};
    for (final reminder in plan) {
      desired[reminder.stableId] = reminder;
    }

    // Snoozes are additive to the plan and keep their original identity.
    // Their stored row already carries the instant chosen by the user.
    final snoozes = await _store.activeSnoozes();
    final activeSnoozeIds = <String>{};
    for (final snooze in snoozes) {
      if (!snooze.fireAt.isAfter(now)) continue;
      final kind = snooze.reminderKind;
      if (kind == ReminderKind.event && !eventsEnabled) continue;
      if (kind == ReminderKind.task && !tasksEnabled) continue;
      final planned = PlannedReminder(
        kind: kind,
        entityId: snooze.entityId,
        id: snooze.key,
        occurrenceStart: snooze.occurrenceStart,
        fireAt: snooze.fireAt,
        title: kind == ReminderKind.task ? 'Task reminder' : 'Event reminder',
        body: '',
      );
      // A user snooze supersedes the planner's original instant for the same
      // occurrence, even while a refresh is already in flight.
      desired[planned.stableId] = planned;
      activeSnoozeIds.add(planned.stableId);
    }

    // Collect due, undelivered rows before pruning so a reminder that came due
    // while Locus was closed reaches the missed-reminder inbox.
    final due = await _store.undeliveredBefore(now);
    final keepIds = <String>{...desired.keys, for (final row in due) row.id};

    final items = <Map<String, Object>>[];
    for (final entry in desired.entries) {
      final reminder = entry.value;
      items.add({
        'id': entry.key,
        'fireAtEpochMs': reminder.fireAt.millisecondsSinceEpoch,
        'title': hideTitles ? 'Locus reminder' : reminder.title,
        'body': hideTitles ? '' : reminder.body,
        'launchUri': _launchUriFor(reminder.kind, reminder.entityId),
      });
    }

    var cancelFailed = false;
    try {
      await _toast.cancelAllExcept(keepIds);
    } catch (_) {
      // A failed prune must not abort scheduling the desired reminders.
      cancelFailed = true;
    }

    // A fallback that was due while the machine slept must not fire on wake;
    // the persisted row keeps the occurrence available to the inbox instead.
    _notification?.cancelPassedReminders(now);

    final accepted = await _toast.schedule(items);

    // Native failure is partial: enumerate what Windows actually kept. A
    // thrown/missing enumeration is unknown, not empty, so no fallback is armed
    // (that would risk a duplicate popup for an occurrence Windows owns).
    List<String>? listed;
    try {
      listed = await _toast.listScheduled();
    } catch (_) {
      listed = null;
    }
    final enumerated = listed != null;
    final confirmed = enumerated
        ? listed.toSet()
        : (accepted ? desired.keys.toSet() : <String>{});
    final confirmedDesired = <String>{
      for (final id in desired.keys)
        if (confirmed.contains(id)) id,
    };
    final unknown = <String>{if (!enumerated && !accepted) ...desired.keys};
    final missing = <String>{
      if (enumerated)
        for (final id in desired.keys)
          if (!confirmedDesired.contains(id)) id,
    };

    final entityIds = <String, List<String>>{};
    for (final entry in desired.entries) {
      final reminder = entry.value;
      entityIds
          .putIfAbsent(reminder.occurrence.entityKey, () => [])
          .add(entry.key);
    }
    final completelyConfirmed = <String>{
      for (final entry in entityIds.entries)
        if (entry.value.every(confirmedDesired.contains)) entry.key,
    };
    NotificationService.setOsOwned(
      ids: confirmedDesired,
      entityKeys: completelyConfirmed,
    );

    // Cancel the in-process copy for occurrences Windows owns. This also clears
    // entity-level and hashed keys from older builds.
    for (final id in confirmedDesired) {
      final reminder = desired[id];
      if (reminder == null) continue;
      // Keep the inbox snooze timer armed: it acknowledges delivery and clears
      // the persisted snooze. Its popup is suppressed while Windows owns it.
      if (activeSnoozeIds.contains(id)) continue;
      _notification?.cancelReminderId(reminder.id);
      _notification?.cancelReminderId(id);
    }
    // Arm a fallback only for occurrences Windows definitively did not keep.
    for (final id in missing) {
      final reminder = desired[id];
      if (reminder == null) continue;
      _armFallback(
        reminder,
        title: hideTitles ? 'Locus reminder' : reminder.title,
      );
    }

    final writes = <PlatformReminderWrite>[
      for (final entry in desired.entries)
        PlatformReminderWrite(
          id: entry.key,
          kind: entry.value.kind.name,
          entityId: entry.value.entityId,
          occurrenceStart: entry.value.occurrenceStart,
          fireAt: entry.value.fireAt,
          owner: confirmedDesired.contains(entry.key)
              ? 'os'
              : (unknown.contains(entry.key) ? 'unknown' : 'app'),
          degraded: missing.contains(entry.key) || unknown.contains(entry.key),
        ),
    ];
    await _store.replaceAll(writes);
    await _store.removeExcept(keepIds);
    await _recordSchedulingHealth(
      degraded:
          cancelFailed || (!enumerated && !accepted) || missing.isNotEmpty,
    );
    await _updateBadge(now);
    return confirmedDesired;
  }

  Future<bool> _enabledFor(ReminderKind kind) async {
    final key = kind == ReminderKind.task
        ? AppDatabase.taskRemindersSettingKey
        : AppDatabase.eventRemindersSettingKey;
    return await _db.getSetting(key) != 'false';
  }

  void _armFallback(PlannedReminder reminder, {required String title}) {
    final notification = _notification;
    if (notification == null) return;
    var skippedLate = false;
    Future<void> markDelivered() async {
      if (!skippedLate) await _store.markDelivered([reminder.stableId]);
    }

    if (reminder.kind == ReminderKind.task) {
      unawaited(
        notification.scheduleTaskReminder(
          taskId: reminder.entityId,
          reminderId: reminder.id,
          stableId: reminder.stableId,
          title: title,
          scheduledTime: reminder.fireAt,
          onSkippedLate: () async {
            skippedLate = true;
          },
          onTriggered: markDelivered,
        ),
      );
    } else {
      unawaited(
        notification.scheduleEventReminder(
          eventId: reminder.entityId,
          reminderId: reminder.id,
          stableId: reminder.stableId,
          title: title,
          scheduledTime: reminder.fireAt,
          onSkippedLate: () async {
            skippedLate = true;
          },
          onTriggered: markDelivered,
        ),
      );
    }
  }

  Future<void> _recordSchedulingHealth({required bool degraded}) async {
    final key = AppDatabase.reminderSchedulingDegradedSettingKey;
    final value = degraded ? '1' : '0';
    final current = await _db.getSetting(key);
    if (current != value) await _db.setSetting(key, value);
  }

  Future<void> _updateBadge(DateTime now) async {
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    final countExpression = _db.todoItems.id.count();
    final query = _db.selectOnly(_db.todoItems)
      ..addColumns([countExpression])
      ..where(
        _db.todoItems.completed.equals(false) &
            _db.todoItems.dueDate.isNotNull() &
            _db.todoItems.dueDate.isSmallerThanValue(endOfDay),
      );
    final row = await query.getSingle();
    final count = row.read(countExpression) ?? 0;
    await _toast.setBadge(count);
  }

  String _launchUriFor(ReminderKind kind, String entityId) => Uri(
    scheme: 'locus',
    host: 'open',
    queryParameters: {'kind': kind.name, 'id': entityId},
  ).toString();

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    final now = AppClock.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    _midnightTimer = Timer(tomorrow.difference(now), () {
      unawaited(refresh().whenComplete(_scheduleMidnight));
    });
  }
}

/// Stable OS-visible id: derived from the canonical occurrence key and
/// base32(SHA256(key))[0..16].
String stableReminderId(PlannedReminder reminder) => reminder.stableId;
