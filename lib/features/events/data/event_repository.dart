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
    NotificationService.instance.cancelAllEventReminders();
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

    await NotificationService.instance.scheduleEventReminder(
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
    await _db.update(_db.events).replace(event);
    NotificationService.instance.cancelEventReminder(event.id);
    await _scheduleReminder(event);
  }

  Future<void> delete(String id) async {
    NotificationService.instance.cancelEventReminder(id);
    await (_db.delete(_db.events)..where((t) => t.id.equals(id))).go();
  }

  String _newId() => _uuid.v4();
}
