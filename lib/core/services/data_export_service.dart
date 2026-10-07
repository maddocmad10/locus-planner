import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';
import '../utils/recurrence.dart';
import '../utils/day_math.dart';

/// What a restore had to change to make an older or hand-edited backup fit the
/// current rules. A clean report means the file was restored exactly as written.
class RestoreReport {
  const RestoreReport({this.adjustedValues = 0, this.skippedRows = 0});

  /// Values moved into their valid range (a mood of 9 becomes 5, say).
  final int adjustedValues;

  /// Rows left out: duplicates, or rows whose parent isn't in the backup.
  final int skippedRows;

  bool get isClean => adjustedValues == 0 && skippedRows == 0;

  String get summary {
    final parts = <String>[
      if (adjustedValues > 0)
        '$adjustedValues value${adjustedValues == 1 ? '' : 's'} adjusted',
      if (skippedRows > 0)
        '$skippedRows row${skippedRows == 1 ? '' : 's'} skipped',
    ];
    return parts.join(', ');
  }
}

class DataExportService {
  final AppDatabase db;

  DataExportService(this.db);

  // ==================== EXPORT FULL DATA AS JSON ====================

  /// Serialises the whole database to the backup JSON document.
  ///
  /// Dates are written by Drift's default serializer (milliseconds since the
  /// epoch). [restoreFromJson] accepts that as well as ISO-8601 strings.
  Future<String> buildBackupJson() async {
    final events = await db.watchAllEvents().first;
    final projects = await db.watchProjects().first;
    final tasks = await db.select(db.tasks).get();
    final diaryEntries = await db.watchDiaryEntries().first;
    final habits = await db.watchHabits().first;
    final habitLogs = await db.select(db.habitLogs).get();
    final focusSessions = await db.watchFocusSessions().first;
    final todoItems = await db.watchAllTodoItems().first;
    final progressLogs = await db.select(db.progressLogs).get();
    final settings = await db.select(db.appSettings).get();
    final exportedSettings = settings
        .where((s) => !AppDatabase.isTransientSetting(s.key))
        .toList();

    final data = {
      'exported_at': DateTime.now().toIso8601String(),
      'version': '1.2',
      'events': events.map((e) => e.toJson()).toList(),
      'projects': projects.map((p) => p.toJson()).toList(),
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'diary_entries': diaryEntries.map((d) => d.toJson()).toList(),
      'habits': habits.map((h) => h.toJson()).toList(),
      'habit_logs': habitLogs.map((h) => h.toJson()).toList(),
      'focus_sessions': focusSessions.map((f) => f.toJson()).toList(),
      'todo_items': todoItems.map((t) => t.toJson()).toList(),
      'progress_logs': progressLogs.map((p) => p.toJson()).toList(),
      'app_settings': exportedSettings.map((s) => s.toJson()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<bool> exportFullDataAsJson() async {
    try {
      final jsonString = await buildBackupJson();

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Locus Data',
        fileName:
            'locus_backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(jsonString);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Export error: $e');
      return false;
    }
  }

  // ==================== EXPORT EVENTS AS ICS ====================
  Future<bool> exportEventsAsIcs() async {
    try {
      final events = await db.watchAllEvents().first;

      final ics = buildIcsCalendar(events);

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Events to Outlook',
        fileName:
            'locus_events_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.ics',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(ics);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('ICS Export error: $e');
      return false;
    }
  }

  // ==================== IMPORT FULL DATA FROM JSON ====================

  /// The result of the most recent successful import, for showing in the UI.
  RestoreReport? lastRestoreReport;

  Future<bool> importFullDataFromJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Locus Backup File',
      );

      if (result == null || result.files.isEmpty) return false;

      final file = File(result.files.single.path!);
      final jsonString = await file.readAsString();

      // Keep a local recovery point before replacing user data. This makes an
      // accidental or corrupted import recoverable without requiring a second
      // manual export first.
      final recoveryPath = await createRecoveryBackup();
      if (recoveryPath == null) {
        throw StateError('Could not create a recovery backup before import.');
      }

      lastRestoreReport = await restoreFromJson(jsonString);
      return true;
    } catch (e) {
      debugPrint('Import error: $e');
      return false;
    }
  }

  /// Creates a durable recovery copy without opening a file picker.
  Future<String?> createRecoveryBackup() async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final backupDir = Directory(
        '${supportDir.path}${Platform.pathSeparator}backups',
      );
      await backupDir.create(recursive: true);
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final file = File(
        '${backupDir.path}${Platform.pathSeparator}manual_$stamp.json',
      );
      await file.writeAsString(await buildBackupJson());
      await _pruneBackups(backupDir);
      return file.path;
    } catch (e, st) {
      debugPrint('Recovery backup failed: $e\n$st');
      return null;
    }
  }

  Future<void> _pruneBackups(Directory backupDir) async {
    final backups = await backupDir
        .list()
        .where((entity) =>
            entity is File &&
            entity.path.endsWith('.json') &&
            (entity.path.contains('manual_') || entity.path.contains('pre_import_')))
        .cast<File>()
        .toList();
    backups.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final oldBackup in backups.skip(10)) {
      await oldBackup.delete();
    }
  }

  /// Replaces all data in the database with the contents of a backup.
  ///
  /// The whole file is parsed and validated *before* anything is deleted, and
  /// the delete + insert then run in one transaction, so a bad file leaves the
  /// existing data untouched. Throws [FormatException] for malformed backups.
  ///
  /// Backups from other versions are restored on a best-effort basis rather
  /// than rejected: out-of-range numbers are moved into range, duplicates and
  /// rows whose parent isn't in the backup are skipped, and focus sessions that
  /// point at a missing project keep the session but lose the link. The
  /// returned [RestoreReport] says how much was changed.
  ///
  /// Settings are only replaced when the backup contains an `app_settings`
  /// section, and never the transient ones (see [AppDatabase.isTransientSetting]).
  Future<RestoreReport> restoreFromJson(String jsonString) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('A backup file must contain a JSON object.');
    }
    final data = decoded;

    var adjusted = 0;
    var skipped = 0;

    /// Reads an integer and moves it into [min]..[max], counting the change.
    int bounded(
      Map<String, dynamic> row,
      String key,
      int min,
      int max, {
      int? fallback,
    }) {
      final raw = _int(row, key, fallback: fallback);
      final value = raw < min ? min : (raw > max ? max : raw);
      if (value != raw) adjusted++;
      return value;
    }

    final projectRows = _rows(data, 'projects');
    final habitRows = _rows(data, 'habits');
    final projectIds = projectRows.map((r) => _str(r, 'id')).toSet();
    final habitIds = habitRows.map((r) => _str(r, 'id')).toSet();

    final projects = [
      for (final p in projectRows)
        ProjectsCompanion(
          id: Value(_str(p, 'id')),
          name: Value(_str(p, 'name')),
          description: Value(_strOrNull(p, 'description')),
          createdAt: Value(_dt(p['createdAt'], 'createdAt')),
          targetDate: Value(_dtOrNull(p['targetDate'], 'targetDate')),
          targetProgress: Value(bounded(p, 'targetProgress', 0, 100, fallback: 100)),
        ),
    ];

    // An unrecognised recurrence rule (from a newer app version) is kept as
    // written; the calendar shows such events as single events.
    final events = [
      for (final e in _rows(data, 'events'))
        EventsCompanion(
          id: Value(_str(e, 'id')),
          title: Value(_str(e, 'title')),
          description: Value(_strOrNull(e, 'description')),
          startTime: Value(_dt(e['startTime'], 'startTime')),
          endTime: Value(_dtOrNull(e['endTime'], 'endTime')),
          category: Value(_strOrNull(e, 'category') ?? 'general'),
          hasReminder: Value(_bool(e, 'hasReminder', fallback: false)),
          reminderMinutes: Value(bounded(e, 'reminderMinutes', 0, 525600, fallback: 10)),
          recurrenceRule: Value(_strOrNull(e, 'recurrenceRule')),
        ),
    ];

    final habits = [
      for (final h in habitRows)
        HabitsCompanion(
          id: Value(_str(h, 'id')),
          name: Value(_str(h, 'name')),
          icon: Value(_strOrNull(h, 'icon') ?? '🔥'),
          createdAt: Value(_dt(h['createdAt'], 'createdAt')),
          targetPerWeek: Value(bounded(h, 'targetPerWeek', 1, 7, fallback: 5)),
        ),
    ];

    final diaryDates = <DateTime>{};
    final diaryEntries = <DiaryEntriesCompanion>[];
    for (final d in _rows(data, 'diary_entries')) {
      final date = DayMath.dateOnly(_dt(d['date'], 'date'));
      if (!diaryDates.add(date)) {
        skipped++;
        continue;
      }
      diaryEntries.add(
        DiaryEntriesCompanion(
          id: Value(_str(d, 'id')),
          date: Value(date),
          mood: Value(bounded(d, 'mood', 1, 5)),
          content: Value(_str(d, 'content')),
        ),
      );
    }

    final todoItems = [
      for (final t in _rows(data, 'todo_items'))
        TodoItemsCompanion(
          id: Value(_str(t, 'id')),
          title: Value(_str(t, 'title')),
          completed: Value(_bool(t, 'completed', fallback: false)),
          createdAt: Value(_dt(t['createdAt'], 'createdAt')),
          dueDate: Value(_dtOrNull(t['dueDate'], 'dueDate')),
        ),
    ];

    final focusSessions = <FocusSessionsCompanion>[];
    for (final f in _rows(data, 'focus_sessions')) {
      final projectId = _strOrNull(f, 'projectId');
      final linked = projectIds.contains(projectId);
      if (projectId != null && !linked) adjusted++;
      focusSessions.add(
        FocusSessionsCompanion(
          id: Value(_str(f, 'id')),
          projectId: Value(linked ? projectId : null),
          startTime: Value(_dt(f['startTime'], 'startTime')),
          durationMinutes: Value(bounded(f, 'durationMinutes', 1, 24 * 60)),
          note: Value(_strOrNull(f, 'note')),
        ),
      );
    }

    final tasks = <TasksCompanion>[];
    for (final t in _rows(data, 'tasks')) {
      if (!projectIds.contains(_str(t, 'projectId'))) {
        skipped++;
        continue;
      }
      tasks.add(
        TasksCompanion(
          id: Value(_str(t, 'id')),
          projectId: Value(_str(t, 'projectId')),
          title: Value(_str(t, 'title')),
          completed: Value(_bool(t, 'completed', fallback: false)),
          sortOrder: Value(_int(t, 'sortOrder', fallback: 0)),
        ),
      );
    }

    final progressLogs = <ProgressLogsCompanion>[];
    for (final p in _rows(data, 'progress_logs')) {
      if (!projectIds.contains(_str(p, 'projectId'))) {
        skipped++;
        continue;
      }
      progressLogs.add(
        ProgressLogsCompanion(
          id: Value(_str(p, 'id')),
          projectId: Value(_str(p, 'projectId')),
          value: Value(bounded(p, 'value', 0, 100)),
          note: Value(_strOrNull(p, 'note')),
          timestamp: Value(_dt(p['timestamp'], 'timestamp')),
        ),
      );
    }

    final habitLogs = <HabitLogsCompanion>[];
    final seenHabitDays = <String>{};
    for (final h in _rows(data, 'habit_logs')) {
      final habitId = _str(h, 'habitId');
      final date = DayMath.dateOnly(_dt(h['date'], 'date'));
      if (!habitIds.contains(habitId) ||
          !seenHabitDays.add('$habitId|${date.toIso8601String()}')) {
        skipped++;
        continue;
      }
      habitLogs.add(
        HabitLogsCompanion(
          id: Value(_str(h, 'id')),
          habitId: Value(habitId),
          date: Value(date),
          completed: Value(_bool(h, 'completed', fallback: true)),
        ),
      );
    }

    // Settings are replaced only when the backup carries them, so restoring an
    // older backup doesn't reset the theme and notification choices.
    final hasSettings = data.containsKey('app_settings');
    final settings = [
      for (final s in _rows(data, 'app_settings'))
        if (!AppDatabase.isTransientSetting(_str(s, 'key')))
          AppSettingsCompanion(
            key: Value(_str(s, 'key')),
            value: Value(_str(s, 'value')),
          ),
    ];

    // Everything parsed successfully; now replace the data atomically.
    await db.transaction(() async {
      // Children first, then parents.
      await db.delete(db.progressLogs).go();
      await db.delete(db.tasks).go();
      await db.delete(db.habitLogs).go();
      await db.delete(db.focusSessions).go();
      await db.delete(db.todoItems).go();
      await db.delete(db.diaryEntries).go();
      await db.delete(db.habits).go();
      await db.delete(db.events).go();
      await db.delete(db.projects).go();
      if (hasSettings) {
        // Transient rows (a focus session in progress, the auto-backup clock)
        // describe this machine right now and must survive the import.
        await (db.delete(db.appSettings)
              ..where((t) => t.key.isNotIn(AppDatabase.transientSettingKeys)))
            .go();
      }

      // Parents first, then children (foreign keys are enforced).
      await db.batch((b) {
        b.insertAll(db.projects, projects);
        b.insertAll(db.events, events);
        b.insertAll(db.habits, habits);
        b.insertAll(db.diaryEntries, diaryEntries);
        b.insertAll(db.todoItems, todoItems);
        b.insertAll(db.focusSessions, focusSessions);
        b.insertAll(db.tasks, tasks);
        b.insertAll(db.progressLogs, progressLogs);
        b.insertAll(db.habitLogs, habitLogs);
        if (hasSettings) {
          b.insertAll(db.appSettings, settings);
        }
      });
    });

    return RestoreReport(adjustedValues: adjusted, skippedRows: skipped);
  }

  // ---------- parsing helpers (throw FormatException with a useful message) ----------

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value == null) return const [];
    if (value is! List) throw FormatException('"$key" must be a list.');
    return value.map((row) {
      if (row is! Map<String, dynamic>) {
        throw FormatException(
          '"$key" contains an entry that is not an object.',
        );
      }
      return row;
    }).toList();
  }

  String _str(Map<String, dynamic> row, String key) {
    final v = row[key];
    if (v is! String) {
      throw FormatException('Missing or invalid "$key" in backup row.');
    }
    return v;
  }

  String? _strOrNull(Map<String, dynamic> row, String key) {
    final v = row[key];
    if (v == null) return null;
    if (v is! String) throw FormatException('Invalid "$key" in backup row.');
    return v;
  }

  int _int(Map<String, dynamic> row, String key, {int? fallback}) {
    final v = row[key];
    if (v == null && fallback != null) return fallback;
    if (v is! num) {
      throw FormatException('Missing or invalid "$key" in backup row.');
    }
    return v.toInt();
  }

  bool _bool(Map<String, dynamic> row, String key, {required bool fallback}) {
    final v = row[key];
    if (v == null) return fallback;
    if (v is! bool) throw FormatException('Invalid "$key" in backup row.');
    return v;
  }

  /// Accepts milliseconds since the epoch (what [buildBackupJson] writes) or
  /// an ISO-8601 string.
  DateTime _dt(Object? v, String key) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed;
    }
    throw FormatException('Missing or invalid date "$key" in backup row.');
  }

  DateTime? _dtOrNull(Object? v, String key) => v == null ? null : _dt(v, key);

  // ==================== ICS HELPERS ====================

  /// Builds an RFC 5545 calendar for [events] (CRLF line endings, escaped text,
  /// folded long lines, DTSTAMP on every event). Pure, so it can be unit tested.
  static String buildIcsCalendar(List<Event> events, {DateTime? now}) {
    final stamp = _formatDateTime(now ?? DateTime.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Locus Planner//EN',
      'CALSCALE:GREGORIAN',
    ];

    for (final event in events) {
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${event.id}@locusplanner')
        ..add('DTSTAMP:$stamp')
        ..add('DTSTART:${_formatEventDateTime(event.startTime, event.recurrenceRule)}');
      final end = event.endTime;
      if (end != null) {
        lines.add('DTEND:${_formatEventDateTime(end, event.recurrenceRule)}');
      }
      lines.add('SUMMARY:${_escapeIcsText(event.title)}');
      final rrule = Recurrence.toRRule(event.recurrenceRule);
      if (rrule != null) lines.add('RRULE:$rrule');
      if (event.recurrenceRule == Recurrence.monthly) {
        final rdates = _monthlyClampedRdates(event.startTime);
        if (rdates.isNotEmpty) {
          lines.add('RDATE:${rdates.join(',')}');
        }
      }
      if (event.recurrenceRule == Recurrence.yearly) {
        final rdates = _yearlyClampedRdates(event.startTime);
        if (rdates.isNotEmpty) {
          lines.add('RDATE:${rdates.join(',')}');
        }
      }
      final description = event.description;
      if (description != null && description.isNotEmpty) {
        lines.add('DESCRIPTION:${_escapeIcsText(description)}');
      }
      lines
        ..add('CATEGORIES:${_escapeIcsText(event.category.toUpperCase())}')
        ..add('END:VEVENT');
    }

    lines.add('END:VCALENDAR');
    return '${lines.map(_foldIcsLine).join('\r\n')}\r\n';
  }

  /// iCalendar's FREQ=MONTHLY;BYMONTHDAY rule skips February and 30-day
  /// months when the original series starts on the 29th, 30th or 31st.
  /// Locus intentionally clamps those occurrences, so add explicit RDATEs for
  /// the next 50 years while retaining the RRULE for the normal months.
  static List<String> _monthlyClampedRdates(DateTime start) {
    if (start.day <= 28) return const [];
    final dates = <String>[];
    for (var offset = 1; offset <= 50 * 12; offset++) {
      final totalMonths = start.year * 12 + start.month - 1 + offset;
      final year = totalMonths ~/ 12;
      final month = totalMonths % 12 + 1;
      final lastDay = DateTime(year, month + 1, 0).day;
      if (start.day > lastDay) {
        dates.add(
          DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(year, month, lastDay, start.hour, start.minute, start.second, start.millisecond, start.microsecond),
          ),
        );
      }
    }
    return dates;
  }

  /// A series that starts on Feb 29 moves to Feb 28 in non-leap years in the
  /// app, but an RRULE alone would skip those years in other calendars.
  static List<String> _yearlyClampedRdates(DateTime start) {
    if (start.month != 2 || start.day != 29) return const [];
    final dates = <String>[];
    for (var offset = 1; offset <= 50; offset++) {
      final year = start.year + offset;
      final isLeap = DateTime(year, 3, 0).day == 29;
      if (!isLeap) {
        dates.add(
          DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(year, 2, 28, start.hour, start.minute, start.second),
          ),
        );
      }
    }
    return dates;
  }

  /// Escapes backslashes, semicolons, commas and line breaks in TEXT values.
  static String _escapeIcsText(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll(';', '\\;')
      .replaceAll(',', '\\,')
      .replaceAll('\r\n', '\\n')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\n');

  /// Folds a content line so no physical line exceeds 75 octets; continuation
  /// lines start with a single space (which counts toward the limit).
  static String _foldIcsLine(String line) {
    const limit = 75;
    if (utf8.encode(line).length <= limit) return line;

    final out = StringBuffer();
    var octets = 0;
    for (final rune in line.runes) {
      final ch = String.fromCharCode(rune);
      final size = utf8.encode(ch).length;
      if (octets + size > limit) {
        out.write('\r\n ');
        octets = 1;
      }
      out.write(ch);
      octets += size;
    }
    return out.toString();
  }

  static String _formatDateTime(DateTime dt) {
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());
  }

  static String _formatEventDateTime(DateTime dt, String? recurrenceRule) {
    if (Recurrence.isRecurring(recurrenceRule)) {
      return DateFormat("yyyyMMdd'T'HHmmss").format(dt);
    }
    return _formatDateTime(dt);
  }
}
