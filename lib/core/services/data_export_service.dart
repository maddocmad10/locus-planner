import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart';
import '../db/app_database.dart';

class DataExportService {
  final AppDatabase db;

  DataExportService(this.db);

  // ==================== EXPORT FULL DATA AS JSON ====================
  Future<bool> exportFullDataAsJson() async {
    try {
      final events = await db.watchAllEvents().first;
      final projects = await db.watchProjects().first;
      final tasks = await db.select(db.tasks).get();
      final diaryEntries = await db.watchDiaryEntries().first;
      final habits = await db.watchHabits().first;
      final habitLogs = await db.select(db.habitLogs).get();
      final focusSessions = await db.watchFocusSessions().first;
      final todoItems = await db.watchAllTodoItems().first;
      final progressLogs = await db.select(db.progressLogs).get();

      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.1',
        'events': events.map((e) => e.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'diary_entries': diaryEntries.map((d) => d.toJson()).toList(),
        'habits': habits.map((h) => h.toJson()).toList(),
        'habit_logs': habitLogs.map((h) => h.toJson()).toList(),
        'focus_sessions': focusSessions.map((f) => f.toJson()).toList(),
        'todo_items': todoItems.map((t) => t.toJson()).toList(),
        'progress_logs': progressLogs.map((p) => p.toJson()).toList(),
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(data);

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Locus Data',
        fileName: 'locus_backup_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.json',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(jsonString);
        return true;
      }
      return false;
    } catch (e) {
      print('Export error: $e');
      return false;
    }
  }

  // ==================== EXPORT EVENTS AS ICS ====================
  Future<bool> exportEventsAsIcs() async {
    try {
      final events = await db.watchAllEvents().first;

      final buffer = StringBuffer();
      buffer.writeln('BEGIN:VCALENDAR');
      buffer.writeln('VERSION:2.0');
      buffer.writeln('PRODID:-//Locus Planner//EN');
      buffer.writeln('CALSCALE:GREGORIAN');

      for (final event in events) {
        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('UID:${event.id}@locusplanner');
        buffer.writeln('DTSTART:${_formatDateTime(event.startTime)}');
        if (event.endTime != null) {
          buffer.writeln('DTEND:${_formatDateTime(event.endTime!)}');
        }
        buffer.writeln('SUMMARY:${event.title}');
        if (event.description != null && event.description!.isNotEmpty) {
          buffer.writeln('DESCRIPTION:${event.description}');
        }
        buffer.writeln('CATEGORIES:${event.category.toUpperCase()}');
        buffer.writeln('END:VEVENT');
      }

      buffer.writeln('END:VCALENDAR');

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Events to Outlook',
        fileName: 'locus_events_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.ics',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(buffer.toString());
        return true;
      }
      return false;
    } catch (e) {
      print('ICS Export error: $e');
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
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      // Use a transaction so everything succeeds or fails together
      await db.transaction(() async {
        // 1. Clear existing data (in reverse dependency order)
        await db.delete(db.progressLogs).go();
        await db.delete(db.tasks).go();
        await db.delete(db.habitLogs).go();
        await db.delete(db.focusSessions).go();
        await db.delete(db.todoItems).go();
        await db.delete(db.diaryEntries).go();
        await db.delete(db.habits).go();
        await db.delete(db.events).go();
        await db.delete(db.projects).go();

        // 2. Insert Projects first (other tables depend on them)
        final projects = data['projects'] as List<dynamic>? ?? [];
        for (final p in projects) {
          await db.into(db.projects).insert(ProjectsCompanion(
            id: Value(p['id'] as String),
            name: Value(p['name'] as String),
            description: Value(p['description'] as String?),
            createdAt: Value(DateTime.parse(p['createdAt'] as String)),
            targetDate: p['targetDate'] != null
                ? Value(DateTime.parse(p['targetDate'] as String))
                : const Value.absent(),
            targetProgress: Value(p['targetProgress'] as int? ?? 100),
          ));
        }

        // 3. Events
        final events = data['events'] as List<dynamic>? ?? [];
        for (final e in events) {
          await db.into(db.events).insert(EventsCompanion(
            id: Value(e['id'] as String),
            title: Value(e['title'] as String),
            description: Value(e['description'] as String?),
            startTime: Value(DateTime.parse(e['startTime'] as String)),
            endTime: e['endTime'] != null
                ? Value(DateTime.parse(e['endTime'] as String))
                : const Value.absent(),
            category: Value(e['category'] as String? ?? 'general'),
            hasReminder: Value(e['hasReminder'] as bool? ?? false),
            reminderMinutes: Value(e['reminderMinutes'] as int? ?? 10),
            recurrenceRule: Value(e['recurrenceRule'] as String?),
          ));
        }

        // 4. Habits
        final habits = data['habits'] as List<dynamic>? ?? [];
        for (final h in habits) {
          await db.into(db.habits).insert(HabitsCompanion(
            id: Value(h['id'] as String),
            name: Value(h['name'] as String),
            icon: Value(h['icon'] as String? ?? '🔥'),
            createdAt: Value(DateTime.parse(h['createdAt'] as String)),
            targetPerWeek: Value(h['targetPerWeek'] as int? ?? 5),
          ));
        }

        // 5. Diary Entries
        final diaryEntries = data['diary_entries'] as List<dynamic>? ?? [];
        for (final d in diaryEntries) {
          await db.into(db.diaryEntries).insert(DiaryEntriesCompanion(
            id: Value(d['id'] as String),
            date: Value(DateTime.parse(d['date'] as String)),
            mood: Value(d['mood'] as int),
            content: Value(d['content'] as String),
          ));
        }

        // 6. Todo Items
        final todoItems = data['todo_items'] as List<dynamic>? ?? [];
        for (final t in todoItems) {
          await db.into(db.todoItems).insert(TodoItemsCompanion(
            id: Value(t['id'] as String),
            title: Value(t['title'] as String),
            completed: Value(t['completed'] as bool? ?? false),
            createdAt: Value(DateTime.parse(t['createdAt'] as String)),
            dueDate: t['dueDate'] != null
                ? Value(DateTime.parse(t['dueDate'] as String))
                : const Value.absent(),
          ));
        }

        // 7. Focus Sessions
        final focusSessions = data['focus_sessions'] as List<dynamic>? ?? [];
        for (final f in focusSessions) {
          await db.into(db.focusSessions).insert(FocusSessionsCompanion(
            id: Value(f['id'] as String),
            projectId: Value(f['projectId'] as String?),
            startTime: Value(DateTime.parse(f['startTime'] as String)),
            durationMinutes: Value(f['durationMinutes'] as int),
            note: Value(f['note'] as String?),
          ));
        }

        // 8. Tasks
        final tasks = data['tasks'] as List<dynamic>? ?? [];
        for (final t in tasks) {
          await db.into(db.tasks).insert(TasksCompanion(
            id: Value(t['id'] as String),
            projectId: Value(t['projectId'] as String),
            title: Value(t['title'] as String),
            completed: Value(t['completed'] as bool? ?? false),
            sortOrder: Value(t['sortOrder'] as int? ?? 0),
          ));
        }

        // 9. Progress Logs
        final progressLogs = data['progress_logs'] as List<dynamic>? ?? [];
        for (final p in progressLogs) {
          await db.into(db.progressLogs).insert(ProgressLogsCompanion(
            id: Value(p['id'] as String),
            projectId: Value(p['projectId'] as String),
            value: Value(p['value'] as int),
            note: Value(p['note'] as String?),
            timestamp: Value(DateTime.parse(p['timestamp'] as String)),
          ));
        }

        // 10. Habit Logs
        final habitLogs = data['habit_logs'] as List<dynamic>? ?? [];
        for (final h in habitLogs) {
          await db.into(db.habitLogs).insert(HabitLogsCompanion(
            id: Value(h['id'] as String),
            habitId: Value(h['habitId'] as String),
            date: Value(DateTime.parse(h['date'] as String)),
            completed: Value(h['completed'] as bool? ?? true),
          ));
        }
      });

      return true;
    } catch (e) {
      print('Import error: $e');
      return false;
    }
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());
  }
}