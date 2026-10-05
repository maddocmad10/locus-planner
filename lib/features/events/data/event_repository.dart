import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  return EventRepository(ref.watch(databaseProvider));
});

class EventRepository {
  EventRepository(this._db);
  final AppDatabase _db;

  Stream<List<Event>> watchAll() => _db.watchAllEvents();
  Stream<List<Event>> watchForDay(DateTime day) => _db.watchEventsForDay(day);

  Future<void> create({
    required String title,
    String? description,
    required DateTime startTime,
    DateTime? endTime,
    String category = 'general',
    bool hasReminder = false,
    int reminderMinutes = 10,
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
        ));
    if (hasReminder) {
      await NotificationService.instance.scheduleEventReminder(
        title: title,
        scheduledTime: startTime.subtract(Duration(minutes: reminderMinutes)),
        body: 'Starts in $reminderMinutes min',
      );
    }
  }

  Future<void> update(Event event) async {
    await _db.update(_db.events).replace(event);
    if (event.hasReminder) {
      await NotificationService.instance.scheduleEventReminder(
        title: event.title,
        scheduledTime: event.startTime.subtract(Duration(minutes: event.reminderMinutes)),
        body: 'Starts in ${event.reminderMinutes} min',
      );
    }
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.events)..where((t) => t.id.equals(id))).go();
  }

  String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}
