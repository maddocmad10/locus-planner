import '../../../core/db/app_database.dart';
import '../../../core/utils/recurrence.dart';

/// One occurrence of an event on a particular day.
///
/// [event] is the stored row (editing it changes the whole series), while
/// [start] is the occurrence's start time, which differs from the stored start
/// for every repeat after the first one.
class AgendaEntry {
  const AgendaEntry({
    required this.event,
    required this.start,
    required this.isRecurring,
  });

  final Event event;
  final DateTime start;

  /// True when [event] repeats, even if [start] is its first occurrence.
  final bool isRecurring;
}

/// The events that happen on [day], with repeats expanded into their
/// occurrences and sorted by start time.
///
/// A one-off event is shown on the day of its stored start time. A recurring
/// event is shown on every occurrence, which is why the phone's Today list
/// cannot simply filter on `event.startTime`. Unknown recurrence rules are
/// treated as one-off, matching [Recurrence.expand], so a newer desktop cannot
/// make an older phone hide an event.
List<AgendaEntry> agendaForDay(Iterable<Event> events, DateTime day) {
  final from = DateTime(day.year, day.month, day.day);
  final to = from.add(const Duration(days: 1));
  final entries = <AgendaEntry>[];

  for (final event in events) {
    final recurring = Recurrence.isRecurring(event.recurrenceRule);
    if (recurring) {
      for (final occurrence in Recurrence.expand(event, from, to)) {
        entries.add(
          AgendaEntry(
            event: event,
            start: occurrence.startTime,
            isRecurring: true,
          ),
        );
      }
      continue;
    }

    final start = event.startTime;
    if (!start.isBefore(from) && start.isBefore(to)) {
      entries.add(AgendaEntry(event: event, start: start, isRecurring: false));
    }
  }

  entries.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.event.id.compareTo(b.event.id);
  });
  return entries;
}
