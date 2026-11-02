import '../../../core/db/app_database.dart';
import '../../../core/models/reminder_kind.dart';
import '../../../core/utils/recurrence.dart';

/// A neutral reminder source the planner can schedule. [at] is already the
/// moment the notification should fire.
class PlannedSource {
  const PlannedSource({
    required this.kind,
    required this.id,
    required this.title,
    required this.at,
    required this.body,
  });

  final ReminderKind kind;
  final String id;
  final String title;
  final DateTime at;
  final String body;
}

/// One notification the phone should show at [fireAt].
class PlannedReminder {
  const PlannedReminder({
    required this.kind,
    required this.entityId,
    required this.id,
    required this.fireAt,
    required this.title,
    required this.body,
  });

  /// Unique per kind and occurrence, so a task and an event with the same id
  /// can never collide.
  final String id;
  final ReminderKind kind;
  final String entityId;
  final DateTime fireAt;
  final String title;
  final String body;

  String get eventId => entityId;

  /// The form sent to the Android side.
  Map<String, Object> toMap() => {
    'id': id,
    'kind': kind.name,
    'at': fireAt.millisecondsSinceEpoch,
    'title': title,
    'body': body,
  };
}

/// Works out which reminders Android has to be told about.
///
/// The phone cannot compute a recurring event's next occurrence while the app
/// is closed, so the app hands Android a rolling window of upcoming reminders
/// instead. Event occurrences and task reminders are reduced to neutral
/// [PlannedSource]s first, then planned together.
class ReminderPlanner {
  const ReminderPlanner._();

  static const horizon = Duration(days: 30);
  static const maxPerEvent = 60;
  static const maxTotal = 300;

  static List<PlannedReminder> plan(
    Iterable<PlannedSource> sources, {
    required DateTime now,
    int totalLimit = maxTotal,
  }) {
    final planned = <PlannedReminder>[
      for (final source in sources)
        if (source.at.isAfter(now))
          PlannedReminder(
            kind: source.kind,
            entityId: source.id,
            id:
                '${source.kind.name}:${source.id}'
                '@${source.at.millisecondsSinceEpoch}',
            fireAt: source.at,
            title: source.title,
            body: source.body,
          ),
    ];
    planned.sort((a, b) {
      final byTime = a.fireAt.compareTo(b.fireAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return planned.length > totalLimit
        ? planned.sublist(0, totalLimit)
        : planned;
  }

  /// Event occurrences whose reminder falls inside [window].
  static List<PlannedSource> sourcesForEvents(
    Iterable<Event> events, {
    required DateTime now,
    Duration window = horizon,
    int perEventLimit = maxPerEvent,
  }) {
    final until = now.add(window);
    final sources = <PlannedSource>[];
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
          recurrenceEnd: event.recurrenceEnd,
          recurrenceExceptions: Recurrence.exceptionDayKeys(
            event.recurrenceExceptions,
          ),
        );
        if (start == null) break;
        final fireAt = start.subtract(lead);
        if (fireAt.isAfter(until)) break;
        sources.add(
          PlannedSource(
            kind: ReminderKind.event,
            id: event.id,
            title: event.title,
            at: fireAt,
            body: bodyFor(event.reminderMinutes),
          ),
        );
        cursor = fireAt;
      }
    }
    return sources;
  }

  /// One source per open task whose reminder is in the future.
  static List<PlannedSource> sourcesForTasks(
    Iterable<TodoItem> tasks, {
    required DateTime now,
  }) {
    return [
      for (final task in tasks)
        if (!task.completed &&
            task.reminderAt != null &&
            task.reminderAt!.isAfter(now))
          PlannedSource(
            kind: ReminderKind.task,
            id: task.id,
            title: task.title,
            at: task.reminderAt!,
            body: 'Task reminder',
          ),
    ];
  }

  /// The text under an event title.
  static String bodyFor(int reminderMinutes) {
    if (reminderMinutes <= 0) return 'Starting now';
    if (reminderMinutes >= 60 && reminderMinutes % 60 == 0) {
      return 'Starts in ${reminderMinutes ~/ 60} h';
    }
    return 'Starts in $reminderMinutes min';
  }
}
