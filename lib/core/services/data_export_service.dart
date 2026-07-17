import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
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
      final focusSessions = await db.watchFocusSessions().first;
      final todoItems = await db.watchAllTodoItems().first;

      final data = {
        'exported_at': DateTime.now().toIso8601String(),
        'version': '1.0',
        'events': events.map((e) => e.toJson()).toList(),
        'projects': projects.map((p) => p.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'diary_entries': diaryEntries.map((d) => d.toJson()).toList(),
        'habits': habits.map((h) => h.toJson()).toList(),
        'focus_sessions': focusSessions.map((f) => f.toJson()).toList(),
        'todo_items': todoItems.map((t) => t.toJson()).toList(),
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

  // ==================== IMPORT DATA ====================
  Future<bool> importFullDataFromJson() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Select Locus Backup File to Import',
      );

      if (result == null || result.files.isEmpty) return false;

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final jsonString = await file.readAsString();

      // For now we just validate the file
      final data = jsonDecode(jsonString) as Map<String, dynamic>;
      print('Import file is valid. Contains keys: ${data.keys.toList()}');

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