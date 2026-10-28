import '../../../core/db/app_database.dart';
import '../../../core/utils/recurrence.dart';

/// One notification the phone should show at [fireAt].
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.eventId,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  /// Unique per event occurrence, so two reminders of one series differ.
  final String id;
  final String eventId;
  final DateTime fireAt;
  final String title;
  final String body;

  /// The form sent to the Android side.
  Map<String, Object> toMap() => {
    'id': id,
    'at': fireAt.millisecondsSinceEpoch,
    'title': title,
    'body': body,
  };
}

/// Works out which reminders Android has to be told about.
///
/// The phone cannot compute a recurring event's next occurrence while the app
/// is closed, so the app hands Android a rolling window of upcoming reminders
/// instead: everything due within [horizon], at most [maxPerEvent] for one
/// event and [maxTotal] overall (earliest first). The window is rebuilt every
/// time events change and every time the app is opened, so it keeps moving
/// forward for as long as the app is used at least once a month.
///
/// It reuses [Recurrence.nextRemindableStart], so the phone and the desktop
/// agree on which occurrence is next and on what counts as already passed.
class ReminderPlanner {
  const ReminderPlanner._();

  static const horizon = Duration(days: 30);
  static const maxPerEvent = 60;
  static const maxTotal = 300;

  static List<PlannedReminder> plan(
    Iterable<Event> events, {
    required DateTime now,
    Duration window = horizon,
    int perEventLimit = maxPerEvent,
    int totalLimit = maxTotal,
  }) {
    final until = now.add(window);
    final planned = <PlannedReminder>[];
    for (final event in events) {
      if (!event.hasReminder || event.reminderMinutes < 0) continue;
      final lead = Duration(minutes: event.reminderMinutes);
      var cursor = now;
      for (var count = 0; count < perEventLimit; count++) {
        final start = Recurrence.nextRemindableStart(
          start: event.startTime,
          rule: event.recurrenceRule,
          reminderMinutes: event.reminderMinutes,
          now: cursor,
        );
        if (start == null) break;
        final fireAt = start.subtract(lead);
        if (fireAt.isAfter(until)) break;
        planned.add(
          PlannedReminder(
            id: '${event.id}@${start.millisecondsSinceEpoch}',
            eventId: event.id,
            fireAt: fireAt,
            title: event.title,
            body: bodyFor(event.reminderMinutes),
          ),
        );
        cursor = fireAt;
      }
    }
    planned.sort((a, b) {
      final byTime = a.fireAt.compareTo(b.fireAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return planned.length > totalLimit
        ? planned.sublist(0, totalLimit)
        : planned;
  }

  /// The text under the event title.
  static String bodyFor(int reminderMinutes) {
    if (reminderMinutes <= 0) return 'Starting now';
    if (reminderMinutes >= 60 && reminderMinutes % 60 == 0) {
      return 'Starts in ${reminderMinutes ~/ 60} h';
    }
    return 'Starts in $reminderMinutes min';
  }
}
