import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

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
      'app_settings': settings.map((s) => s.toJson()).toList(),
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
      await _createAutomaticBackup();

      await restoreFromJson(jsonString);
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
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    backups.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final oldBackup in backups.skip(10)) {
      await oldBackup.delete();
    }
  }

  Future<void> _createAutomaticBackup() async {
    final supportDir = await getApplicationSupportDirectory();
    final backupDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}backups',
    );
    await backupDir.create(recursive: true);

    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final backupFile = File(
      '${backupDir.path}${Platform.pathSeparator}pre_import_$stamp.json',
    );
    await backupFile.writeAsString(await buildBackupJson());

    final backups = await backupDir
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    backups.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final oldBackup in backups.skip(5)) {
      await oldBackup.delete();
    }
  }

  /// Replaces all data in the database with the contents of a backup.
  ///
  /// The whole file is parsed and validated *before* anything is deleted, and
  /// the delete + insert then run in one transaction, so a bad file leaves the
  /// existing data untouched. Throws [FormatException] for malformed backups.
  ///
  /// Rows that point at a parent which isn't in the backup (left behind by
  /// older versions that never enforced foreign keys) are dropped; focus
  /// sessions pointing at a missing project keep the session but lose the link.
  Future<void> restoreFromJson(String jsonString) async {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('A backup file must contain a JSON object.');
    }
    final data = decoded;

    final projectRows = _rows(data, 'projects');
    final habitRows = _rows(data, 'habits');
    final projectIds = projectRows.map((r) => _str(r, 'id')).toSet();
    final habitIds = habitRows.map((r) => _str(r, 'id')).toSet();

    final projects = projectRows
        .map(
          (p) => ProjectsCompanion(
            id: Value(_str(p, 'id')),
            name: Value(_str(p, 'name')),
            description: Value(_strOrNull(p, 'description')),
            createdAt: Value(_dt(p['createdAt'], 'createdAt')),
            targetDate: Value(_dtOrNull(p['targetDate'], 'targetDate')),
            targetProgress: Value(_int(p, 'targetProgress', fallback: 100)),
          ),
        )
        .toList();

    final events = _rows(data, 'events')
        .map(
          (e) => EventsCompanion(
            id: Value(_str(e, 'id')),
            title: Value(_str(e, 'title')),
            description: Value(_strOrNull(e, 'description')),
            startTime: Value(_dt(e['startTime'], 'startTime')),
            endTime: Value(_dtOrNull(e['endTime'], 'endTime')),
            category: Value(_strOrNull(e, 'category') ?? 'general'),
            hasReminder: Value(_bool(e, 'hasReminder', fallback: false)),
            reminderMinutes: Value(_int(e, 'reminderMinutes', fallback: 10)),
            recurrenceRule: Value(_strOrNull(e, 'recurrenceRule')),
          ),
        )
        .toList();

    final habits = habitRows
        .map(
          (h) => HabitsCompanion(
            id: Value(_str(h, 'id')),
            name: Value(_str(h, 'name')),
            icon: Value(_strOrNull(h, 'icon') ?? '🔥'),
            createdAt: Value(_dt(h['createdAt'], 'createdAt')),
            targetPerWeek: Value(_int(h, 'targetPerWeek', fallback: 5)),
          ),
        )
        .toList();

    final diaryEntries = _rows(data, 'diary_entries')
        .map(
          (d) => DiaryEntriesCompanion(
            id: Value(_str(d, 'id')),
            date: Value(_dt(d['date'], 'date')),
            mood: Value(_int(d, 'mood')),
            content: Value(_str(d, 'content')),
          ),
        )
        .toList();

    final todoItems = _rows(data, 'todo_items')
        .map(
          (t) => TodoItemsCompanion(
            id: Value(_str(t, 'id')),
            title: Value(_str(t, 'title')),
            completed: Value(_bool(t, 'completed', fallback: false)),
            createdAt: Value(_dt(t['createdAt'], 'createdAt')),
            dueDate: Value(_dtOrNull(t['dueDate'], 'dueDate')),
          ),
        )
        .toList();

    final focusSessions = _rows(data, 'focus_sessions').map((f) {
      final projectId = _strOrNull(f, 'projectId');
      return FocusSessionsCompanion(
        id: Value(_str(f, 'id')),
        projectId: Value(projectIds.contains(projectId) ? projectId : null),
        startTime: Value(_dt(f['startTime'], 'startTime')),
        durationMinutes: Value(_int(f, 'durationMinutes')),
        note: Value(_strOrNull(f, 'note')),
      );
    }).toList();

    final tasks = _rows(data, 'tasks')
        .where((t) => projectIds.contains(_str(t, 'projectId')))
        .map(
          (t) => TasksCompanion(
            id: Value(_str(t, 'id')),
            projectId: Value(_str(t, 'projectId')),
            title: Value(_str(t, 'title')),
            completed: Value(_bool(t, 'completed', fallback: false)),
            sortOrder: Value(_int(t, 'sortOrder', fallback: 0)),
          ),
        )
        .toList();

    final progressLogs = _rows(data, 'progress_logs')
        .where((p) => projectIds.contains(_str(p, 'projectId')))
        .map(
          (p) => ProgressLogsCompanion(
            id: Value(_str(p, 'id')),
            projectId: Value(_str(p, 'projectId')),
            value: Value(_int(p, 'value')),
            note: Value(_strOrNull(p, 'note')),
            timestamp: Value(_dt(p['timestamp'], 'timestamp')),
          ),
        )
        .toList();

    final settings = _rows(data, 'app_settings')
        .map(
          (s) => AppSettingsCompanion(
            key: Value(_str(s, 'key')),
            value: Value(_str(s, 'value')),
          ),
        )
        .toList();

    final habitLogs = _rows(data, 'habit_logs')
        .where((h) => habitIds.contains(_str(h, 'habitId')))
        .map(
          (h) => HabitLogsCompanion(
            id: Value(_str(h, 'id')),
            habitId: Value(_str(h, 'habitId')),
            date: Value(_dt(h['date'], 'date')),
            completed: Value(_bool(h, 'completed', fallback: true)),
          ),
        )
        .toList();

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
      await db.delete(db.appSettings).go();

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
        b.insertAll(db.appSettings, settings);
      });
    });
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
    if (v is! String)
      throw FormatException('Missing or invalid "$key" in backup row.');
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
    if (v is! num)
      throw FormatException('Missing or invalid "$key" in backup row.');
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
        ..add('DTSTART:${_formatDateTime(event.startTime)}');
      final end = event.endTime;
      if (end != null) lines.add('DTEND:${_formatDateTime(end)}');
      lines.add('SUMMARY:${_escapeIcsText(event.title)}');
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
}
