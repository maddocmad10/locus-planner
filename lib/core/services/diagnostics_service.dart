import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import '../security/database_bootstrap.dart';
import '../security/database_security_options.dart';
import '../utils/app_clock.dart';
import 'reminder_diagnostics.dart';

/// Produces a ZIP that a user can inspect before sending to support.
///
/// The structured report contains only counts, versions, state codes and
/// scrubbed log lines. It never reads titles, notes, diary text, tags,
/// attachment display names or file names from the database.
class DiagnosticsService {
  DiagnosticsService(
    this._db, {
    this.appVersion,
    this.logDirectory,
    DateTime Function()? now,
    this.nativeReminderStats,
  }) : _now = now ?? AppClock.now;

  final AppDatabase _db;
  final Future<String> Function()? appVersion;
  final Directory? logDirectory;
  final DateTime Function() _now;
  final Future<List<Map<String, Object?>>> Function()? nativeReminderStats;

  static const reportVersion = 1;

  Future<Map<String, dynamic>> collect({int logLines = 500}) async {
    final version = await _version();
    final report = <String, dynamic>{
      'report_version': reportVersion,
      'generated_at': _now().toUtc().toIso8601String(),
      'app': {
        'name': 'Locus Planner',
        'version': version,
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'dart': Platform.version,
      },
      'database': {
        'schema_version': AppDatabase.currentSchemaVersion,
        'encryption_enabled': DatabaseSecurity.actualEncryptionEnabled,
        'cipher_profile': DatabaseSecurity.profile.profileId,
      },
      'counts': await _counts(),
      'sync': await _syncSummary(),
      'reminders': await _reminderSummary(),
      'attachments': await _attachmentSummary(),
      'reminder_diagnostics': ReminderDiagnostics.snapshot(),
      'native_reminder_diagnostics':
          await (nativeReminderStats?.call() ??
              Future<List<Map<String, Object?>>>.value(const [])),
      'error_log_lines': await _readLogTail(logLines),
    };
    return report;
  }

  Future<String> buildJson({int logLines = 500}) async {
    final report = await collect(logLines: logLines);
    return const JsonEncoder.withIndent('  ').convert(report);
  }

  Future<Uint8List> buildZip({int logLines = 500}) async {
    final json = await buildJson(logLines: logLines);
    final log = await _readLogTail(logLines);
    final archive = Archive();
    _addText(archive, 'diagnostics.json', json);
    _addText(archive, 'error-log.txt', log);
    _addText(
      archive,
      'README.txt',
      'Locus diagnostics\n'
          '=================\n\n'
          'This ZIP was produced locally, without a network connection.\n'
          'It contains counts, versions, state codes, scrubbed log lines and a\n'
          'content-free reminder delivery buffer. It does not contain titles,\n'
          'notes, diary text, tags, attachment display names or file names.\n'
          'Review diagnostics.json before sharing it.\n',
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Opens a save dialog and writes the ZIP. Returns false when cancelled.
  Future<bool> saveZip({int logLines = 500}) async {
    final bytes = await buildZip(logLines: logLines);
    final date = _now().toUtc().toIso8601String().split('T').first;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Locus diagnostics',
      fileName: 'locus_diagnostics_$date.zip',
    );
    if (path == null) return false;
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  }

  Future<String> _version() async {
    if (appVersion != null) return appVersion!();
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  Future<Directory> _resolveLogDirectory() async {
    final configured = logDirectory;
    if (configured != null) return configured;
    final context = DatabaseRuntimeContext.current;
    if (context != null) return context.paths.dataDirectory;
    return getApplicationSupportDirectory();
  }

  Future<Map<String, int>> _counts() async {
    const tables = [
      'events',
      'todo_items',
      'diary_entries',
      'habits',
      'projects',
      'attachments',
      'sync_outbox',
    ];
    final result = <String, int>{};
    for (final table in tables) {
      final rows = await _db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .get();
      result[table] = rows.first.read<int>('c');
    }
    return result;
  }

  Future<Map<String, dynamic>> _syncSummary() async {
    final rawClients = await _db.getSetting(
      AppDatabase.syncServerPairedClientsSettingKey,
    );
    var paired = 0;
    if (rawClients != null) {
      try {
        final decoded = jsonDecode(rawClients);
        if (decoded is List) paired = decoded.length;
      } catch (_) {
        // A damaged list remains a count of zero; do not echo its contents.
      }
    }
    final epoch = await _db.getSetting(AppDatabase.syncEpochSettingKey);
    final deviceId = await _db.getSetting(AppDatabase.syncDeviceIdSettingKey);
    final head = await _db.outboxHead();
    final pruned = await _db.outboxPrunedThrough();
    return {
      'server_enabled':
          await _db.getSetting(AppDatabase.syncServerEnabledSettingKey) == '1',
      'paired_devices': paired,
      'epoch_fingerprint': _fingerprint(epoch),
      'device_fingerprint': _fingerprint(deviceId),
      'outbox_head': head,
      'outbox_pruned_through': pruned,
      'pending_outbox_rows':
          (await _db
                  .customSelect('SELECT COUNT(*) AS c FROM sync_outbox')
                  .get())
              .first
              .read<int>('c'),
    };
  }

  Future<Map<String, dynamic>> _reminderSummary() async {
    Future<int> listLength(String key) async {
      final raw = await _db.getSetting(key);
      if (raw == null || raw.isEmpty) return 0;
      try {
        final decoded = jsonDecode(raw);
        return decoded is List ? decoded.length : 0;
      } catch (_) {
        return 0;
      }
    }

    return {
      'event_reminders':
          await _db.getSetting(AppDatabase.eventRemindersSettingKey) != '0',
      'task_reminders':
          await _db.getSetting(AppDatabase.taskRemindersSettingKey) != '0',
      'focus_alerts':
          await _db.getSetting(AppDatabase.focusAlertsSettingKey) != '0',
      'pending_inbox_items': await listLength(
        AppDatabase.remindersPendingSettingKey,
      ),
      'snoozed_items': await listLength(AppDatabase.remindersSnoozedSettingKey),
    };
  }

  Future<Map<String, dynamic>> _attachmentSummary() async {
    final rows = await _db
        .customSelect(
          'SELECT state, COUNT(*) AS c, COALESCE(SUM(size_bytes), 0) AS bytes '
          'FROM attachment_blobs GROUP BY state',
        )
        .get();
    final byState = <String, int>{};
    var totalBytes = 0;
    for (final row in rows) {
      byState[row.read<String>('state')] = row.read<int>('c');
      totalBytes += row.read<int>('bytes');
    }
    return {
      'metadata_rows':
          (await _db
                  .customSelect('SELECT COUNT(*) AS c FROM attachments')
                  .get())
              .first
              .read<int>('c'),
      'blob_states': byState,
      'total_blob_bytes': totalBytes,
    };
  }

  Future<String> _readLogTail(int maxLines) async {
    final directory = await _resolveLogDirectory();
    final files = [
      File('${directory.path}${Platform.pathSeparator}locus_error.log.2'),
      File('${directory.path}${Platform.pathSeparator}locus_error.log.1'),
      File('${directory.path}${Platform.pathSeparator}locus_error.log'),
    ];
    final buffer = StringBuffer();
    for (final file in files) {
      if (!await file.exists()) continue;
      try {
        buffer.write(await file.readAsString());
      } catch (_) {
        // A rotating file that disappears mid-read is simply skipped.
      }
    }
    final lines = buffer.toString().split('\n');
    final tail = lines.length <= maxLines
        ? lines
        : lines.sublist(lines.length - maxLines);
    return _scrub(tail.join('\n'));
  }

  String _scrub(String text) {
    var scrubbed = text;
    // User profile directories on Windows and Unix.
    scrubbed = scrubbed.replaceAll(
      RegExp(r'[A-Za-z]:\\Users\\[^\\\r\n]+'),
      '<home>',
    );
    scrubbed = scrubbed.replaceAll(
      RegExp(r'/(?:home|Users)/[^/\s]+'),
      '<home>',
    );
    // Android app-private paths carry the package name, not the user's name,
    // but they still identify the install.
    scrubbed = scrubbed.replaceAll(
      RegExp(r'/data/user/0/[^/\s]+'),
      '<app-data>',
    );
    return scrubbed;
  }

  static String? _fingerprint(String? value) {
    if (value == null || value.isEmpty) return null;
    return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
  }

  static void _addText(Archive archive, String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
}
