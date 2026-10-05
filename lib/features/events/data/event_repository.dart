import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils/recurrence.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(databaseProvider));
});

class EventRepository {
  EventRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Event>> watchAll() => _db.watchAllEvents();
  Stream<List<Event>> watchForDay(DateTime day) => _db.watchEventsForDay(day);


  /// Rebuilds in-memory reminders after an application restart. The
  /// notification service intentionally keeps timers in memory, so persisted
  /// events are the source of truth.
  Future<void> restoreFutureReminders() async {
    final events = await _db.watchAllEvents().first;
    final now = DateTime.now();
    for (final event in events) {
      if (!event.hasReminder) continue;
      final nextStart = Recurrence.next(event.startTime, event.recurrenceRule, from: now) ??
          (event.startTime.isAfter(now) ? event.startTime : null);
      if (nextStart == null) continue;
      final reminderAt =
          nextStart.subtract(Duration(minutes: event.reminderMinutes));
      if (reminderAt.isBefore(now)) continue;
      await NotificationService.instance.scheduleEventReminder(
        eventId: event.id,
        title: event.title,
        scheduledTime: reminderAt,
        body: 'Starts in ${event.reminderMinutes} min',
      );
    }
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
    final id = _newId();
    await _db.into(_db.events).insert(EventsCompanion(
          id: Value(id),
          title: Value(title),
          description: Value(description),
          startTime: Value(startTime),
          endTime: Value(endTime),
          category: Value(category),
          hasReminder: Value(hasReminder),
          reminderMinutes: Value(reminderMinutes),
          recurrenceRule: Value(recurrenceRule),
        ));
    if (hasReminder) {
      await NotificationService.instance.scheduleEventReminder(
        eventId: id,
        title: title,
        scheduledTime: startTime.subtract(Duration(minutes: reminderMinutes)),
        body: 'Starts in $reminderMinutes min',
      );
    }
  }

  Future<void> update(Event event) async {
    await _db.update(_db.events).replace(event);
    NotificationService.instance.cancelEventReminder(event.id);
    if (event.hasReminder) {
      await NotificationService.instance.scheduleEventReminder(
        eventId: event.id,
        title: event.title,
        scheduledTime: event.startTime.subtract(Duration(minutes: event.reminderMinutes)),
        body: 'Starts in ${event.reminderMinutes} min',
      );
    }
  }

  Future<void> delete(String id) async {
    NotificationService.instance.cancelEventReminder(id);
    await (_db.delete(_db.events)..where((t) => t.id.equals(id))).go();
  }

  String _newId() => _uuid.v4();
}
