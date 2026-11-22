import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/reminder_kind.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/reminders/reminder_identity.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/recurrence.dart';
import '../../../core/utils/recurrence_spec.dart';
import '../../../core/utils/app_clock.dart';
import 'reminder_inbox_service.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    ref.watch(databaseProvider),
    ref.watch(notificationServiceProvider),
    ref.watch(undoServiceProvider),
    ref.watch(reminderInboxServiceProvider),
  );
});

/// Every stored event. The calendar expands recurrence itself so one stream
/// can drive month, week, day and agenda views.
final allEventsProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(eventRepositoryProvider).watchAll();
});

final selectedDayEventsProvider = StreamProvider.autoDispose
    .family<List<EventOccurrence>, DateTime>((ref, day) {
      return ref.watch(eventRepositoryProvider).watchForDay(day);
    });

final eventMarkersProvider = StreamProvider.autoDispose
    .family<Map<DateTime, List<Event>>, DateTime>((ref, focusedDay) {
      return ref
          .watch(eventRepositoryProvider)
          .watchAll()
          .map((events) => EventRepository.buildMarkers(events, focusedDay));
    });

/// A series row as it occurs on one calendar day.
///
/// [event] is the stored row. Edit and delete that, not a shifted copy.
/// [start] and [end] are the occurrence times used for display.
class EventOccurrence {
  const EventOccurrence({required this.event, required this.start, this.end});

  final Event event;
  final DateTime start;
  final DateTime? end;
}

class EventRepository {
  EventRepository(this._db, this._notifications, this._undo, [this._inbox]);
  final AppDatabase _db;
  final NotificationService _notifications;
  final UndoService _undo;
  final ReminderInboxService? _inbox;
  final _uuid = const Uuid();

  Stream<List<Event>> watchAll() => _db.watchAllEvents();
  static Map<DateTime, List<Event>> buildMarkers(
    Iterable<Event> events,
    DateTime focusedDay,
  ) {
    final from = DateTime(focusedDay.year, focusedDay.month - 1, 1);
    final to = DateTime(focusedDay.year, focusedDay.month + 2, 0, 23, 59, 59);
    final eventsMap = <DateTime, List<Event>>{};
    for (final event in events) {
      for (final occurrence in Recurrence.expand(event, from, to)) {
        final day = DayMath.dateOnly(occurrence.startTime);
        (eventsMap[day] ??= <Event>[]).add(occurrence);
      }
    }
    return eventsMap;
  }

  /// Events that occur on [day], including later occurrences of a series.
  ///
  /// A stored-start-only query would miss a weekly event created last week,
  /// so this expands every series over [day] instead.
  Stream<List<EventOccurrence>> watchForDay(DateTime day) {
    return _db.watchAllEvents().map((events) => occurrencesOn(events, day));
  }

  static List<EventOccurrence> occurrencesOn(
    Iterable<Event> events,
    DateTime day,
  ) {
    final start = DayMath.dateOnly(day);
    final end = DayMath.addDays(start, 1);
    final items = <EventOccurrence>[
      for (final event in events)
        for (final occurrence in Recurrence.expand(event, start, end))
          EventOccurrence(
            event: event,
            start: occurrence.startTime,
            end: occurrence.endTime,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    return items;
  }

  /// Rebuilds in-memory reminders after an application restart.
  /// Recurring events are scheduled for their next occurrence. Occurrences
  /// Windows already confirmed are skipped, so one occurrence has one owner.
  Future<void> restoreFutureReminders({
    Set<String> osConfirmedIds = const {},
  }) async {
    final events = await _db.watchAllEvents().first;
    for (final event in events) {
      await _scheduleReminder(event, osConfirmedIds: osConfirmedIds);
    }
  }

  /// Cancels in-memory timers and arms the next future reminder for every event.
  /// Used after import, when previously scheduled timers no longer match the data.
  Future<void> restoreAllReminders({
    Set<String> osConfirmedIds = const {},
  }) async {
    _notifications.cancelAllEventReminders();
    await restoreFutureReminders(osConfirmedIds: osConfirmedIds);
  }

  Future<void> scheduleReminder(
    Event event, {
    Set<String> osConfirmedIds = const {},
  }) => _scheduleReminder(event, osConfirmedIds: osConfirmedIds);

  /// Re-arms or cancels reminders for events that were written outside this
  /// repository, such as rows applied by a sync from the phone. The stored row
  /// is the source of truth: a deleted event has its timer cancelled, and a
  /// changed one is re-scheduled from its new time.
  Future<void> rescheduleReminders(
    Iterable<String> eventIds, {
    Set<String> osConfirmedIds = const {},
  }) async {
    for (final id in eventIds.toSet()) {
      _notifications.cancelOccurrence(ReminderKind.event, id);
      final event = await (_db.select(
        _db.events,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (event != null) {
        await _scheduleReminder(event, osConfirmedIds: osConfirmedIds);
      }
    }
  }

  /// The next occurrence start whose reminder is still in the future.
  DateTime? _nextReminderStart(Event event, DateTime now) {
    final spec = RecurrenceSpec.tryParse(event.recurrenceSpec);
    if (spec?.isMonthlyWeekday == true) {
      final exceptions = Recurrence.exceptionDayKeys(
        event.recurrenceExceptions,
      );
      for (final occurrence in spec!.expandEvent(
        event,
        now,
        now.add(const Duration(days: 400)),
      )) {
        final reminderAt = occurrence.startTime.subtract(
          Duration(minutes: event.reminderMinutes),
        );
        if (reminderAt.isAfter(now) &&
            !exceptions.contains(
              '${occurrence.startTime.year}-'
              '${occurrence.startTime.month.toString().padLeft(2, '0')}-'
              '${occurrence.startTime.day.toString().padLeft(2, '0')}',
            )) {
          return occurrence.startTime;
        }
      }
      return null;
    }
    return Recurrence.nextRemindableStart(
      start: event.startTime,
      rule: event.recurrenceRule,
      reminderMinutes: event.reminderMinutes,
      now: now,
      recurrenceEnd: event.recurrenceEnd,
      recurrenceExceptions: Recurrence.exceptionDayKeys(
        event.recurrenceExceptions,
      ),
    );
  }

  Future<void> _scheduleReminder(
    Event event, {
    Set<String> osConfirmedIds = const {},
  }) async {
    if (!event.hasReminder) {
      _notifications.cancelOccurrence(ReminderKind.event, event.id);
      return;
    }
    final now = AppClock.now();
    final nextStart = _nextReminderStart(event, now);
    if (nextStart == null) {
      _notifications.cancelOccurrence(ReminderKind.event, event.id);
      return;
    }
    final reminderAt = nextStart.subtract(
      Duration(minutes: event.reminderMinutes),
    );
    final occurrence = ReminderOccurrence(
      kind: ReminderKind.event,
      entityId: event.id,
      occurrenceStart: nextStart,
    );
    final stableId = occurrence.stableId;
    if (osConfirmedIds.contains(stableId) ||
        NotificationService.isOsOwnedId(stableId)) {
      // Windows owns this occurrence; an in-process timer would duplicate it.
      _notifications.cancelReminderId(occurrence.key);
      _notifications.cancelReminderId(stableId);
      return;
    }

    await _notifications.scheduleEventReminder(
      eventId: event.id,
      reminderId: occurrence.key,
      stableId: stableId,
      title: event.title,
      scheduledTime: reminderAt,
      body: 'Starts in ${event.reminderMinutes} min',
      onSkippedLate: _inbox == null
          ? null
          : () => _inbox.rememberMissed(
              eventId: event.id,
              title: event.title,
              occurrenceStart: nextStart,
              reminderAt: reminderAt,
              owner: 'app',
              degraded: true,
            ),
      onTriggered: () async {
        final latest = await (_db.select(
          _db.events,
        )..where((t) => t.id.equals(event.id))).getSingleOrNull();
        if (latest != null && latest.hasReminder) {
          await _scheduleReminder(latest);
        }
      },
    );
  }

  Future<String> create({
    required String title,
    String? description,
    String descriptionFormat = 'plain',
    required DateTime startTime,
    DateTime? endTime,
    String category = 'general',
    bool hasReminder = false,
    int reminderMinutes = 10,
    String? recurrenceRule,
    String? recurrenceSpec,
    bool allDay = false,
    DateTime? recurrenceEnd,
    String recurrenceExceptions = '[]',
  }) async {
    _validateEvent(reminderMinutes, recurrenceRule);
    final id = _newId();
    await _db
        .into(_db.events)
        .insert(
          EventsCompanion(
            id: Value(id),
            title: Value(title),
            description: Value(description),
            descriptionFormat: Value(
              descriptionFormat == 'md1' ? 'md1' : 'plain',
            ),
            startTime: Value(startTime),
            endTime: Value(endTime),
            category: Value(category),
            hasReminder: Value(hasReminder),
            reminderMinutes: Value(reminderMinutes),
            recurrenceRule: Value(recurrenceRule),
            recurrenceSpec: Value(recurrenceSpec),
            allDay: Value(allDay),
            recurrenceEnd: Value(recurrenceEnd),
            recurrenceExceptions: Value(recurrenceExceptions),
          ),
        );
    if (hasReminder) {
      final event = await (_db.select(
        _db.events,
      )..where((t) => t.id.equals(id))).getSingle();
      await _scheduleReminder(event);
    }
    return id;
  }

  Future<void> update(Event event) async {
    _validateEvent(event.reminderMinutes, event.recurrenceRule);
    final existing = await (_db.select(
      _db.events,
    )..where((t) => t.id.equals(event.id))).getSingleOrNull();
    await _db.update(_db.events).replace(event);
    // Keep OS ownership for an unchanged occurrence: a refresh re-titles the
    // existing toast instead of briefly owning it twice.
    _cancelReminderFor(existing, forgetOsOwned: false);
    await _scheduleReminder(event);
  }

  Future<void> delete(String id) async {
    final existing = await (_db.select(
      _db.events,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    _cancelReminderFor(existing);
    await (_db.delete(_db.events)..where((t) => t.id.equals(id))).go();
  }

  /// Cancels the legacy entity key, the canonical occurrence key and the
  /// hashed OS fallback for the event's next occurrence.
  void _cancelReminderFor(Event? event, {bool forgetOsOwned = true}) {
    if (event == null) return;
    final nextStart = event.hasReminder
        ? _nextReminderStart(event, AppClock.now())
        : null;
    if (nextStart == null) {
      _notifications.cancelOccurrence(
        ReminderKind.event,
        event.id,
        forgetOsOwned: forgetOsOwned,
      );
      return;
    }
    final occurrence = ReminderOccurrence(
      kind: ReminderKind.event,
      entityId: event.id,
      occurrenceStart: nextStart,
    );
    _notifications.cancelOccurrence(
      ReminderKind.event,
      event.id,
      keys: [occurrence.key],
      stableIds: [occurrence.stableId],
      forgetOsOwned: forgetOsOwned,
    );
  }

  Future<void> deleteWithUndo(String id) async {
    final event = await (_db.select(
      _db.events,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (event == null) return;

    await delete(id);
    _undo.offer(
      label: 'event',
      restore: () async {
        await _db.into(_db.events).insert(event);
        await _scheduleReminder(event);
      },
    );
  }

  void _validateEvent(int reminderMinutes, String? recurrenceRule) {
    if (reminderMinutes < 0) {
      throw ArgumentError.value(
        reminderMinutes,
        'reminderMinutes',
        'must be >= 0',
      );
    }
    if (!Recurrence.isValidRule(recurrenceRule)) {
      throw ArgumentError.value(
        recurrenceRule,
        'recurrenceRule',
        'unsupported recurrence rule',
      );
    }
  }

  String _newId() => _uuid.v4();
}
