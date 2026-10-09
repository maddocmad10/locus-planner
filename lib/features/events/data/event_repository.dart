import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/recurrence.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(
    ref.watch(databaseProvider),
    ref.watch(notificationServiceProvider),
    ref.watch(undoServiceProvider),
  );
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
  EventRepository(this._db, this._notifications, this._undo);
  final AppDatabase _db;
  final NotificationService _notifications;
  final UndoService _undo;
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
  /// The raw `watchEventsForDay` query only matches the stored start, so a
  /// weekly event created last week would be missing from Today.
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
  /// Recurring events are scheduled for their next occurrence.
  Future<void> restoreFutureReminders() async {
    final events = await _db.watchAllEvents().first;
    for (final event in events) {
      await _scheduleReminder(event);
    }
  }

  /// Cancels in-memory timers and arms the next future reminder for every event.
  /// Used after import, when previously scheduled timers no longer match the data.
  Future<void> restoreAllReminders() async {
    _notifications.cancelAllEventReminders();
    await restoreFutureReminders();
  }

  Future<void> scheduleReminder(Event event) => _scheduleReminder(event);

  Future<void> _scheduleReminder(Event event) async {
    if (!event.hasReminder) return;
    final now = DateTime.now();
    final nextStart = Recurrence.nextRemindableStart(
      start: event.startTime,
      rule: event.recurrenceRule,
      reminderMinutes: event.reminderMinutes,
      now: now,
    );
    if (nextStart == null) return;
    final reminderAt = nextStart.subtract(
      Duration(minutes: event.reminderMinutes),
    );

    await _notifications.scheduleEventReminder(
      eventId: event.id,
      title: event.title,
      scheduledTime: reminderAt,
      body: 'Starts in ${event.reminderMinutes} min',
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

  Future<void> create({
    required String title,
    String? description,
    required DateTime startTime,
    DateTime? endTime,
    String category = 'general',
    bool hasReminder = false,
    int reminderMinutes = 10,
    String? recurrenceRule,
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
            startTime: Value(startTime),
            endTime: Value(endTime),
            category: Value(category),
            hasReminder: Value(hasReminder),
            reminderMinutes: Value(reminderMinutes),
            recurrenceRule: Value(recurrenceRule),
          ),
        );
    if (hasReminder) {
      final event = await (_db.select(
        _db.events,
      )..where((t) => t.id.equals(id))).getSingle();
      await _scheduleReminder(event);
    }
  }

  Future<void> update(Event event) async {
    _validateEvent(event.reminderMinutes, event.recurrenceRule);
    await _db.update(_db.events).replace(event);
    _notifications.cancelEventReminder(event.id);
    await _scheduleReminder(event);
  }

  Future<void> delete(String id) async {
    _notifications.cancelEventReminder(id);
    await (_db.delete(_db.events)..where((t) => t.id.equals(id))).go();
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
