import '../utils/app_clock.dart';

/// A rolling, content-free reminder delivery log.
///
/// It records counts, outcomes and lateness only: never a title, note, event
/// name or attachment name. The native Android side has its own alarm service;
/// this buffer covers reminders scheduled and fired by the Dart side.
class ReminderDiagnostics {
  ReminderDiagnostics._();

  static const maxEntries = 200;
  static final _entries = <Map<String, Object?>>[];

  static void scheduled({required String kind}) =>
      _record(kind: kind, outcome: 'scheduled');

  static void fired({required String kind, required int minutesLate}) =>
      _record(kind: kind, outcome: 'fired', minutesLate: minutesLate);

  static void skippedLate({required String kind, required int minutesLate}) =>
      _record(kind: kind, outcome: 'skipped_late', minutesLate: minutesLate);

  static void _record({
    required String kind,
    required String outcome,
    int? minutesLate,
  }) {
    _entries.add({
      'at': AppClock.now().toUtc().toIso8601String(),
      'kind': kind,
      'outcome': outcome,
      'minutesLate': minutesLate,
      'alarmType': 'dart-timer',
    });
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// A copy safe to put in diagnostics. Newest entries are last.
  static List<Map<String, Object?>> snapshot() => [
    for (final entry in _entries) Map<String, Object?>.from(entry),
  ];

  static void clear() => _entries.clear();
}
