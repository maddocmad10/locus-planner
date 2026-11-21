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
  }) : _toast = toastPlatform,
       _store = store ?? PlatformReminderStore(_db);

  static const maxScheduled = 1000;

  final AppDatabase _db;
  final WindowsToastPlatform _toast;
  final PlatformReminderStore _store;
  StreamSubscription<List<Event>>? _eventSubscription;
  StreamSubscription<List<TodoItem>>? _taskSubscription;
  Timer? _midnightTimer;
  Future<void>? _inFlight;
  bool _again = false;

  void start() {
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
    unawaited(refresh());
  }

  Future<void> stop() async {
    NotificationService.platformSchedulerActive = false;
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

  /// Reschedules one reminder from a toast Snooze action.
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
    final base = PlannedReminder(
      kind: kind,
      entityId: target.entityId,
      id: '',
      fireAt: fireAt,
      title: 'Snoozed reminder',
      body: '',
    );
    final newId = stableReminderId(base);
    final stored = PlannedReminder(
      kind: kind,
      entityId: target.entityId,
      id: newId,
      fireAt: fireAt,
      title: 'Snoozed reminder',
      body: '',
    );
    await _toast.schedule([
      {
        'id': newId,
        'fireAtEpochMs': fireAt.millisecondsSinceEpoch,
        'title': 'Snoozed reminder',
        'body': '',
        'launchUri': _launchUri(stored),
      },
    ]);
    await _store.replaceAll([stored]);
    await _store.markDelivered([id]);
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
    if (!eventsEnabled && !tasksEnabled) {
      await _toast.cancelAllExcept(const {});
      await _store.removeExcept(const {});
      return;
    }

    final now = AppClock.now();
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
    final ids = <String>{};
    final items = <Map<String, Object>>[];
    final stored = <PlannedReminder>[];
    for (final reminder in plan) {
      final id = stableReminderId(reminder);
      ids.add(id);
      stored.add(
        PlannedReminder(
          kind: reminder.kind,
          entityId: reminder.entityId,
          id: id,
          fireAt: reminder.fireAt,
          title: reminder.title,
          body: reminder.body,
        ),
      );
      items.add({
        'id': id,
        'fireAtEpochMs': reminder.fireAt.millisecondsSinceEpoch,
        'title': hideTitles ? 'Locus reminder' : reminder.title,
        'body': hideTitles ? '' : reminder.body,
        'launchUri': _launchUri(reminder),
      });
    }
    await _toast.cancelAllExcept(ids);
    await _toast.schedule(items);
    await _store.replaceAll(stored);
    await _store.removeExcept(ids);
    await _updateBadge(now);
  }

  Future<void> _updateBadge(DateTime now) async {
    final endOfDay = DateTime(now.year, now.month, now.day + 1);
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS count FROM todo_items '
          'WHERE completed = 0 AND due_date IS NOT NULL AND due_date < ?',
          variables: [Variable.withInt(endOfDay.millisecondsSinceEpoch)],
        )
        .get();
    final count = rows.isEmpty ? 0 : rows.first.read<int>('count');
    await _toast.setBadge(count);
  }

  String _launchUri(PlannedReminder reminder) => Uri(
    scheme: 'locus',
    host: 'open',
    queryParameters: {'kind': reminder.kind.name, 'id': reminder.entityId},
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
