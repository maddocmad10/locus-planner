import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

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
    final run = _drain();
    _inFlight = run;
    return run;
  }

  Future<List<PlatformReminderState>> takeMissed() async {
    final missed = await _store.missedBefore(AppClock.now());
    if (missed.isNotEmpty) {
      await _store.markDelivered(missed.map((row) => row.id));
    }
    return missed;
  }

  /// Reschedules one reminder from a toast Snooze action. The row keeps its
  /// identity and records the reminder it was snoozed from, so a later refresh
  /// or restart cannot forget or duplicate it.
  Future<void> snooze(String id, int minutes) async {
    final rows = await _store.all();
    PlatformReminderState? target;
    for (final row in rows) {
      if (row.id == id) target = row;
    }
    if (target == null) return;
    final kind = ReminderKind.values.firstWhere(
      (value) => value.name == target!.kind,
      orElse: () => ReminderKind.task,
    );
    final fireAt = AppClock.now().add(Duration(minutes: minutes));
    final title = kind == ReminderKind.task
        ? 'Task reminder'
        : 'Event reminder';
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
    );
    if (!scheduled) {
      await _recordSchedulingHealth(degraded: true);
      _armFallback(kind, target.entityId, target.id, title, fireAt);
    }
  }

  Future<void> _drain() async {
    try {
      do {
        _again = false;
        await _apply();
      } while (_again);
    } finally {
      _inFlight = null;
    }
  }

  Future<void> _apply() async {
    final eventsEnabled =
        await _db.getSetting(AppDatabase.eventRemindersSettingKey) != 'false';
    final tasksEnabled =
        await _db.getSetting(AppDatabase.taskRemindersSettingKey) != 'false';
    final now = AppClock.now();
    if (!eventsEnabled && !tasksEnabled) {
      await _toast.cancelAllExcept(const {});
      await _store.removeExcept(const {});
      NotificationService.setOsOwned(ids: const {}, entityKeys: const {});
      _notification
        ?..cancelAllEventReminders()
        ..cancelAllTaskReminders();
      await _recordSchedulingHealth(degraded: false);
      await _updateBadge(now);
      return;
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

    final desired = <String, PlannedReminder>{};
    for (final reminder in plan) {
      desired[stableReminderId(reminder)] = reminder;
    }

    // Snoozes are additive to the plan and keep their original identity.
    // Their stored row already carries the instant chosen by the user.
    final snoozes = await _store.activeSnoozes();
    for (final snooze in snoozes) {
      if (!snooze.fireAt.isAfter(now)) continue;
      final kind = ReminderKind.values.firstWhere(
        (value) => value.name == snooze.kind,
        orElse: () => ReminderKind.task,
      );
      desired.putIfAbsent(
        snooze.id,
        () => PlannedReminder(
          kind: kind,
          entityId: snooze.entityId,
          id: snooze.id,
          fireAt: snooze.fireAt,
          title: kind == ReminderKind.task ? 'Task reminder' : 'Event reminder',
          body: '',
        ),
      );
    }

    // Collect due, undelivered rows before pruning so a reminder that came due
    // while Locus was closed reaches the missed-reminder inbox.
    final due = await _store.undeliveredBefore(now);
    final keepIds = <String>{...desired.keys, for (final row in due) row.id};

    final items = <Map<String, Object>>[];
    final stored = <PlannedReminder>[];
    for (final entry in desired.entries) {
      final reminder = entry.value;
      stored.add(
        PlannedReminder(
          kind: reminder.kind,
          entityId: reminder.entityId,
          id: entry.key,
          fireAt: reminder.fireAt,
          title: reminder.title,
          body: reminder.body,
        ),
      );
      items.add({
        'id': entry.key,
        'fireAtEpochMs': reminder.fireAt.millisecondsSinceEpoch,
        'title': hideTitles ? 'Locus reminder' : reminder.title,
        'body': hideTitles ? '' : reminder.body,
        'launchUri': _launchUriFor(reminder.kind, reminder.entityId),
      });
    }

    await _toast.cancelAllExcept(keepIds);
    final accepted = await _toast.schedule(items);

    // Native failure is partial: enumerate what Windows actually kept, and
    // fall back in-process only for the missing reminders.
    var enumerated = false;
    final confirmed = <String>{};
    try {
      confirmed.addAll(await _toast.listScheduled());
      enumerated = true;
    } catch (_) {
      // Older runners without enumeration: trust the batch result.
    }
    final confirmedDesired = <String>{
      if (!enumerated && accepted) ...desired.keys,
      if (enumerated)
        for (final id in desired.keys)
          if (confirmed.contains(id)) id,
    };
    final missing = desired.keys.where((id) => !confirmedDesired.contains(id));
    final entityIds = <String, List<String>>{};
    for (final entry in desired.entries) {
      final reminder = entry.value;
      final entityKey = NotificationService.reminderSuppressionKey(
        reminder.kind.name,
        reminder.entityId,
      );
      entityIds.putIfAbsent(entityKey, () => []).add(entry.key);
    }
    final completelyConfirmed = <String>{
      for (final entry in entityIds.entries)
        if (entry.value.every(confirmedDesired.contains)) entry.key,
    };
    NotificationService.setOsOwned(
      ids: confirmedDesired,
      entityKeys: completelyConfirmed,
    );
    for (final id in missing) {
      final reminder = desired[id];
      if (reminder == null) continue;
      _armFallback(
        reminder.kind,
        reminder.entityId,
        id,
        hideTitles ? 'Locus reminder' : reminder.title,
        reminder.fireAt,
      );
    }
    for (final id in confirmedDesired) {
      final reminder = desired[id];
      if (reminder == null) continue;
      _notification?.cancelReminderId(id);
    }
    for (final key in completelyConfirmed) {
      final separator = key.indexOf(':');
      if (separator < 0) continue;
      final kind = key.substring(0, separator);
      final entityId = key.substring(separator + 1);
      if (kind == ReminderKind.task.name) {
        _notification?.cancelTaskReminder(entityId);
      } else {
        _notification?.cancelEventReminder(entityId);
      }
    }

    await _store.replaceAll(stored);
    await _store.removeExcept(keepIds);
    await _recordSchedulingHealth(
      degraded: !accepted || (enumerated && missing.isNotEmpty),
    );
    await _updateBadge(now);
  }

  void _armFallback(
    ReminderKind kind,
    String entityId,
    String reminderId,
    String title,
    DateTime fireAt,
  ) {
    final notification = _notification;
    if (notification == null) return;
    if (kind == ReminderKind.task) {
      unawaited(
        notification.scheduleTaskReminder(
          taskId: entityId,
          reminderId: reminderId,
          title: title,
          scheduledTime: fireAt,
        ),
      );
    } else {
      unawaited(
        notification.scheduleEventReminder(
          eventId: entityId,
          reminderId: reminderId,
          title: title,
          scheduledTime: fireAt,
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

/// Stable OS-visible id: base32(SHA256(kind|entity|fireAt))[0..16].
String stableReminderId(PlannedReminder reminder) {
  final digest = sha256
      .convert(
        utf8.encode(
          '${reminder.kind.name}|${reminder.entityId}|'
          '${reminder.fireAt.millisecondsSinceEpoch}',
        ),
      )
      .bytes;
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final out = StringBuffer();
  for (final byte in digest) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
      if (out.length >= 16) return out.toString();
    }
  }
  return out.toString().padRight(16, 'A').substring(0, 16);
}
