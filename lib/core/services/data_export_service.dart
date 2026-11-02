import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import 'backup_encryption_service.dart';
import 'crypto/encrypted_envelope.dart';
import 'crypto/key_derivation.dart';
import 'error_log_service.dart';
import 'ics_import.dart';
import 'undo_service.dart';
import '../utils/recurrence.dart';
import '../utils/day_math.dart';
import '../utils/app_clock.dart';

/// Asks the user for a backup passphrase. Return null to cancel.
typedef PasswordPrompt = Future<String?> Function(String message);

/// What a restore had to change to make an older or hand-edited backup fit the
/// current rules. A clean report means the file was restored exactly as written.
class RestoreReport {
  const RestoreReport({this.adjustedValues = 0, this.skippedRows = 0});

  /// Values moved into their valid range (a mood of 9 becomes 5, say).
  final int adjustedValues;

  /// Rows left out: duplicates, and rows whose parent is in neither the
  /// backup nor the existing data.
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

class BackupImportPlan {
  const BackupImportPlan({
    required this.data,
    required this.sections,
    required this.counts,
    required this.mergedSections,
    required this.formatVersion,
  });

  final Map<String, dynamic> data;
  final Set<String> sections;
  final Map<String, int> counts;
  final Set<String> mergedSections;
  final int? formatVersion;

  static const allSections = <String>{
    'events',
    'projects',
    'tasks',
    'diary_entries',
    'habits',
    'habit_logs',
    'focus_sessions',
    'todo_items',
    'todo_completions',
    'daily_plans',
    'daily_plan_items',
    'progress_logs',
    'app_settings',
  };

  /// The user's data: every section except settings. "Replace everything"
  /// empties these when the file lacks them; settings (theme, notification
  /// choices) describe the app, not the user's records, and are only replaced
  /// when the file actually contains them.
  static const dataSections = <String>{
    'events',
    'projects',
    'tasks',
    'diary_entries',
    'habits',
    'habit_logs',
    'focus_sessions',
    'todo_items',
    'todo_completions',
    'daily_plans',
    'daily_plan_items',
    'progress_logs',
  };

  factory BackupImportPlan.parse(
    String jsonString, {
    bool replaceEverything = false,
  }) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('A backup file must contain a JSON object.');
    }
    final rawVersion = decoded['format_version'];
    if (rawVersion != null && rawVersion is! num) {
      throw const FormatException('Backup format_version must be a number.');
    }
    final version = rawVersion is num ? rawVersion.toInt() : null;
    if (version != null && version > 2) {
      throw FormatException(
        'Backup format version $version is newer than this app supports.',
      );
    }
    if (version != null && version < 1) {
      throw FormatException('Invalid backup format version $version.');
    }

    final invalidSections = decoded.keys
        .where(allSections.contains)
        .where((key) => decoded[key] is! List)
        .toList();
    if (invalidSections.isNotEmpty) {
      throw FormatException(
        'Backup sections must be arrays: ${invalidSections.join(', ')}',
      );
    }
    final originalSections = decoded.keys
        .where(allSections.contains)
        .where((key) => decoded[key] is List)
        .toSet();
    if (originalSections.isEmpty) {
      throw const FormatException(
        'Backup contains no recognized data sections.',
      );
    }
    if (replaceEverything && version != null && version >= 2) {
      throw const FormatException(
        'Replace everything is only available for older backup formats.',
      );
    }
    final effectiveData = replaceEverything
        ? <String, dynamic>{
            ...decoded,
            for (final section in dataSections)
              section: decoded[section] ?? <dynamic>[],
          }
        : decoded;
    final sections = replaceEverything
        ? {...originalSections, ...dataSections}
        : originalSections;
    final counts = <String, int>{
      for (final key in sections) key: (effectiveData[key] as List).length,
    };
    final hasAllProjectChildren = sections.containsAll({
      'tasks',
      'progress_logs',
      'focus_sessions',
    });
    final mergedSections = <String>{
      if (sections.contains('projects') && !hasAllProjectChildren) 'projects',
      if (sections.contains('habits') && !sections.contains('habit_logs'))
        'habits',
    };
    return BackupImportPlan(
      data: effectiveData,
      sections: sections,
      counts: counts,
      mergedSections: mergedSections,
      formatVersion: version,
    );
  }

  /// Older/unversioned backups may be explicitly promoted to a full restore.
  bool get canReplaceEverything => (formatVersion ?? 1) < 2;

  Set<String> get untouchedSections => allSections.difference(sections);

  bool get replacesProjects =>
      sections.contains('projects') && !mergedSections.contains('projects');

  bool get replacesHabits =>
      sections.contains('habits') && !mergedSections.contains('habits');
}

class IcsImportReport {
  const IcsImportReport({
    required this.imported,
    this.updated = 0,
    this.skipped = 0,
    this.simplifiedSeries = const [],
    this.simplifiedSkipped = 0,
    this.overridesSkipped = 0,
    this.overridesImported = 0,
    this.exdatesIgnored = 0,
    this.allDayImported = 0,
    this.timezoneFallbacks = 0,
  });

  /// New events written.
  final int imported;

  /// Existing events whose id matched and were updated.
  final int updated;

  /// VEVENT blocks that had no usable summary or start time.
  final int skipped;

  /// Titles of recurring series that could not be represented exactly.
  final List<String> simplifiedSeries;

  /// Simplified series left out because the user chose that option.
  final int simplifiedSkipped;

  /// Modified occurrences left out because their master was skipped.
  final int overridesSkipped;

  /// Modified occurrences imported as separate one-off events.
  final int overridesImported;

  final int exdatesIgnored;
  final int allDayImported;
  final int timezoneFallbacks;

  int get total => imported + updated;
}

/// A parsed calendar waiting for the user's confirmation.
class IcsPreview {
  const IcsPreview({required this.source, required this.parsed});

  final String source;
  final IcsParseResult parsed;

  int get eventCount => parsed.events.length;
  int get allDayCount => parsed.events.where((event) => event.isAllDay).length;
  int get overrideCount =>
      parsed.events.where((event) => event.recurrenceId != null).length;
  int get exdateCount =>
      parsed.events.fold(0, (sum, event) => sum + event.exdates.length);
  List<String> get simplifiedSeries => parsed.simplifiedSeries;
  int get timezoneFallbacks => parsed.timezoneFallbacks;
}

class BackupSummary {
  const BackupSummary({
    required this.sections,
    required this.counts,
    required this.mergedSections,
    required this.untouchedSections,
    required this.formatVersion,
    required this.canReplaceEverything,
  });

  final Set<String> sections;
  final Map<String, int> counts;
  final Set<String> mergedSections;
  final Set<String> untouchedSections;
  final int? formatVersion;
  final bool canReplaceEverything;

  bool get isPartial =>
      untouchedSections.difference({'app_settings'}).isNotEmpty;

  String importMode(String section) =>
      mergedSections.contains(section) ? 'Merged' : 'Replaced';

  String readableName(String section) => section
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

class DataExportService {
  /// Maximum JSON backup size accepted through the import flow. Keeping this
  /// bounded prevents an unexpectedly large file from being read into memory.
  static const maxImportFileBytes = 25 * 1024 * 1024;

  /// Used when package info is unavailable (tests, or a failed plugin lookup).
  /// Kept in sync with `version:` in pubspec.yaml.
  static const fallbackAppVersion = '1.3.0+2';

  final AppDatabase db;
  final Directory? backupDirectory;
  final Future<String> Function()? appVersionProvider;
  final UndoService? undo;
  final BackupEncryptionService? backupEncryption;
  final DeriveKey derive;
  String? _pendingImportJson;

  DataExportService(
    this.db, {
    this.backupDirectory,
    this.appVersionProvider,
    this.undo,
    this.backupEncryption,
    this.derive = KeyDerivation.derive,
  });

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
    final todoCompletions = await db.select(db.todoCompletions).get();
    final dailyPlans = await db.select(db.dailyPlans).get();
    final dailyPlanItems = await db.select(db.dailyPlanItems).get();
    final progressLogs = await db.select(db.progressLogs).get();
    final settings = await db.select(db.appSettings).get();
    final exportedSettings = settings
        .where((s) => !AppDatabase.isTransientSetting(s.key))
        .toList();

    final data = {
      'exported_at': AppClock.now().toIso8601String(),
      'format_version': 2,
      'version': await _appVersion(),
      'events': _sortedRows(events.map((e) => e.toJson())),
      'projects': _sortedRows(projects.map((p) => p.toJson())),
      'tasks': _sortedRows(tasks.map((t) => t.toJson())),
      'diary_entries': _sortedRows(diaryEntries.map((d) => d.toJson())),
      'habits': _sortedRows(habits.map((h) => h.toJson())),
      'habit_logs': _sortedRows(habitLogs.map((h) => h.toJson())),
      'focus_sessions': _sortedRows(focusSessions.map((f) => f.toJson())),
      'todo_items': _sortedRows(todoItems.map((t) => t.toJson())),
      'todo_completions': _sortedRows(todoCompletions.map((c) => c.toJson())),
      'daily_plans': _sortedRows(dailyPlans.map((p) => p.toJson())),
      'daily_plan_items': _sortedRows(dailyPlanItems.map((i) => i.toJson())),
      'progress_logs': _sortedRows(progressLogs.map((p) => p.toJson())),
      'app_settings': _sortedRows(
        exportedSettings.map((s) => s.toJson()),
        key: 'key',
      ),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  List<Map<String, dynamic>> _sortedRows(
    Iterable<Map<String, dynamic>> rows, {
    String key = 'id',
  }) {
    final result = rows.toList(growable: true);
    result.sort(
      (a, b) => (a[key] as String? ?? '').compareTo(b[key] as String? ?? ''),
    );
    return result;
  }

  Future<bool> exportFullDataAsJson() async {
    try {
      final jsonString = await buildBackupJson();

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Locus Data',
        fileName:
            'locus_backup_${DateFormat('yyyy-MM-dd').format(AppClock.now())}.json',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(jsonString);
        return true;
      }
      return false;
    } catch (e, st) {
      await ErrorLogService.log(e, st);
      rethrow;
    }
  }

  /// Encrypts a full JSON backup into the shared `.locusbackup` envelope.
  Future<bool> exportFullDataAsEncryptedJson(String passphrase) async {
    try {
      final jsonString = await buildBackupJson();
      final document = await EncryptedEnvelope.seal(
        jsonString,
        passphrase,
        payloadType: EncryptedEnvelope.payloadFullBackup,
        derive: derive,
      );
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Encrypted Locus Backup',
        fileName:
            'locus_backup_${DateFormat('yyyy-MM-dd').format(AppClock.now())}'
            '.locusbackup',
      );
      if (outputFile == null) return false;
      await File(outputFile).writeAsString(document);
      return true;
    } catch (e, st) {
      await ErrorLogService.log(e, st);
      rethrow;
    }
  }

  /// The content and extension for an automatic or recovery backup.
  ///
  /// When a passphrase is configured, encryption is mandatory: a failed
  /// credential-store read throws instead of falling back to plain JSON.
  Future<({String content, String extension})> buildAutomaticBackup() async {
    final plain = await buildBackupJson();
    String? passphrase;
    final encryption = backupEncryption;
    if (encryption != null) {
      passphrase = await encryption.read();
    }
    if (passphrase == null) return (content: plain, extension: '.json');
    return (
      content: await EncryptedEnvelope.seal(
        plain,
        passphrase,
        payloadType: EncryptedEnvelope.payloadFullBackup,
        derive: derive,
      ),
      extension: '.locusbackup',
    );
  }

  /// Removes only the old unencrypted automatic, manual and pre-import JSON
  /// files. Encrypted files are never touched.
  Future<int> deleteUnencryptedBackups() async {
    final dir = await backupDirectoryFor();
    if (!await dir.exists()) return 0;
    var deleted = 0;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      final isCandidate =
          name.endsWith('.json') &&
          (name.startsWith('auto_') ||
              name.startsWith('manual_') ||
              name.startsWith('pre_import_'));
      if (!isCandidate) continue;
      await entity.delete();
      deleted++;
    }
    return deleted;
  }

  /// Reads a backup file, decrypting it when it carries an encrypted envelope.
  /// The prompt is called up to five times; null cancels.
  Future<String> readBackupFile(File file, {PasswordPrompt? prompt}) async {
    final raw = await readImportFile(file);
    if (!EncryptedEnvelope.looksEncrypted(raw)) return raw;
    if (prompt == null) {
      throw const FormatException(
        'That backup is encrypted. A passphrase is required.',
      );
    }
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      final passphrase = await prompt(
        attempt == 0
            ? 'Enter the passphrase for this encrypted backup.'
            : 'Incorrect passphrase. Try again.',
      );
      if (passphrase == null) {
        throw const FormatException('A passphrase is required to open it.');
      }
      try {
        final opened = await EncryptedEnvelope.open(
          raw,
          passphrase,
          derive: derive,
        );
        if (opened.payloadType != EncryptedEnvelope.payloadFullBackup) {
          throw const FormatException(
            'That is an encrypted diary backup, not a full backup.',
          );
        }
        return opened.plaintext;
      } on BackupDecryptionException catch (error) {
        lastError = error;
      }
    }
    throw FormatException(
      lastError is FormatException
          ? lastError.message
          : 'The passphrase is wrong, or the backup is damaged.',
    );
  }

  Future<Directory> backupDirectoryFor() async {
    final configured = backupDirectory;
    if (configured != null) return configured;
    return Directory(
      '${(await getApplicationSupportDirectory()).path}'
      '${Platform.pathSeparator}backups',
    );
  }

  // ==================== EXPORT EVENTS AS ICS ====================
  Future<bool> exportEventsAsIcs() async {
    try {
      final events = await db.watchAllEvents().first;

      final ics = buildIcsCalendar(events);

      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Events to Outlook',
        fileName:
            'locus_events_${DateFormat('yyyy-MM-dd').format(AppClock.now())}.ics',
      );

      if (outputFile != null) {
        await File(outputFile).writeAsString(ics);
        return true;
      }
      return false;
    } catch (e, st) {
      await ErrorLogService.log(e, st);
      rethrow;
    }
  }

  // ==================== IMPORT EVENTS FROM ICS ====================

  /// Calendar files are usually much smaller than JSON backups. A separate
  /// bound still prevents a mistaken pick of a huge file from being read.
  static const maxIcsImportFileBytes = 10 * 1024 * 1024;

  /// Opens a file picker and parses the chosen calendar without writing.
  /// Returns null when the user cancelled.
  Future<IcsPreview?> previewEventsFromIcs() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      dialogTitle: 'Import Events from ICS',
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    final content = await readIcsFile(File(path));
    return previewIcs(content);
  }

  /// Parses a calendar without touching the database.
  Future<IcsPreview> previewIcs(String source) async =>
      IcsPreview(source: source, parsed: IcsParser.parse(source));

  /// Backwards-compatible one-step import used by older callers and tests. The
  /// UI should use [previewIcs] and [importIcs] so the user can confirm.
  Future<IcsImportReport?> importEventsFromIcs() async {
    final preview = await previewEventsFromIcs();
    if (preview == null) return null;
    return importIcs(preview, keepSimplified: true);
  }

  /// Pure import entry point used by the picker and regression tests.
  ///
  /// Events are upserted with an id derived from the iCalendar UID, so picking
  /// the same file twice updates its events instead of duplicating them.
  Future<IcsImportReport> importEventsFromIcsText(String source) async {
    final preview = await previewIcs(source);
    return importIcs(preview, keepSimplified: true);
  }

  /// Writes a previewed calendar. [keepSimplified] false omits series whose
  /// replay rule Locus cannot represent exactly.
  Future<IcsImportReport> importIcs(
    IcsPreview preview, {
    required bool keepSimplified,
  }) async {
    final parsed = preview.parsed;
    final companions = <EventsCompanion>[];
    final importedIds = <String>{};
    var simplifiedSkipped = 0;
    var overridesSkipped = 0;
    var overridesImported = 0;
    var allDayImported = 0;

    final groups = <String, List<IcsEvent>>{};
    for (final event in parsed.events) {
      final uid = event.uid?.trim();
      final key = uid != null && uid.isNotEmpty
          ? 'uid:$uid'
          : 'event:${event.summary}|${event.start.toIso8601String()}|'
                '${event.end?.toIso8601String()}|${event.recurrenceRule}';
      groups.putIfAbsent(key, () => []).add(event);
    }

    for (final group in groups.values) {
      IcsEvent? master;
      final overrides = <IcsEvent>[];
      for (final event in group) {
        if (event.recurrenceId == null) {
          master ??= event;
        } else {
          overrides.add(event);
        }
      }

      if (master == null) {
        // An orphaned override has no series to modify; keep it as a one-off.
        for (final override in overrides) {
          companions.add(_companion(override));
          overridesImported++;
          allDayImported += override.isAllDay ? 1 : 0;
        }
        continue;
      }

      if (master.seriesSimplified && !keepSimplified) {
        simplifiedSkipped++;
        overridesSkipped += overrides.length;
        continue;
      }

      final exceptions = <String>{
        for (final day in master.exdates) _dayKey(day),
        for (final override in overrides)
          if (override.recurrenceId != null) _dayKey(override.recurrenceId!),
      };
      companions.add(_companion(master, recurrenceExceptions: exceptions));
      allDayImported += master.isAllDay ? 1 : 0;

      for (final override in overrides) {
        companions.add(_companion(override, oneOff: true));
        overridesImported++;
        allDayImported += override.isAllDay ? 1 : 0;
      }
    }

    for (final companion in companions) {
      importedIds.add(companion.id.value);
    }
    final existing = <Event>[];
    final ids = importedIds.toList();
    for (var start = 0; start < ids.length; start += 500) {
      final end = (start + 500).clamp(0, ids.length);
      final chunk = ids.sublist(start, end);
      existing.addAll(
        await (db.select(db.events)..where((t) => t.id.isIn(chunk))).get(),
      );
    }
    final captured = {for (final event in existing) event.id: event};
    final updated = existing.length;

    await db.transaction(() async {
      await db.batch((batch) {
        batch.insertAllOnConflictUpdate(db.events, companions);
      });
    });

    final undo = this.undo;
    if (undo != null && companions.isNotEmpty) {
      undo.offer(
        label: 'ICS import',
        restore: () async {
          await db.transaction(() async {
            for (final id in importedIds) {
              await (db.delete(db.events)..where((t) => t.id.equals(id))).go();
            }
            for (final event in captured.values) {
              await db.into(db.events).insert(event);
            }
          });
        },
      );
    }

    return IcsImportReport(
      imported: companions.length - updated,
      updated: updated,
      skipped: parsed.skipped,
      simplifiedSeries: parsed.simplifiedSeries,
      simplifiedSkipped: simplifiedSkipped,
      overridesSkipped: overridesSkipped,
      overridesImported: overridesImported,
      exdatesIgnored: parsed.exdatesIgnored,
      allDayImported: allDayImported,
      timezoneFallbacks: parsed.timezoneFallbacks,
    );
  }

  EventsCompanion _companion(
    IcsEvent event, {
    bool oneOff = false,
    Set<String> recurrenceExceptions = const {},
  }) => EventsCompanion(
    id: Value(_icsEventId(event)),
    title: Value(event.summary),
    description: Value(event.description),
    startTime: Value(event.start),
    endTime: Value(event.end),
    category: Value(event.category),
    hasReminder: Value(!event.isAllDay && event.reminderMinutes != null),
    reminderMinutes: Value(event.reminderMinutes ?? 10),
    recurrenceRule: Value(oneOff ? null : event.recurrenceRule),
    allDay: Value(event.isAllDay),
    recurrenceEnd: Value(oneOff ? null : event.recurrenceEnd),
    recurrenceExceptions: Value(
      oneOff || recurrenceExceptions.isEmpty
          ? '[]'
          : jsonEncode(recurrenceExceptions.toList()..sort()),
    ),
  );

  static String _dayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<String> readIcsFile(File file) async {
    final length = await file.length();
    if (length > maxIcsImportFileBytes) {
      throw FormatException(
        'Calendar file is too large. Maximum size is '
        '${maxIcsImportFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return file.readAsString();
  }

  static String _icsEventId(IcsEvent event) {
    final uid = event.uid?.trim();
    if (uid != null && uid.isNotEmpty) {
      final own = RegExp(r'^(.+)@locusplanner$').firstMatch(uid);
      if (own != null) return own.group(1)!;
      if (event.recurrenceId != null) {
        final overrideKey =
            event.recurrenceIdRaw ?? event.recurrenceId!.toIso8601String();
        return const Uuid().v5(
          Namespace.url.value,
          'locus-ics:uid:$uid|recurrence-id:$overrideKey',
        );
      }
      return const Uuid().v5(Namespace.url.value, 'locus-ics:uid:$uid');
    }
    final seed =
        'event:${event.summary}|${event.start.toIso8601String()}|'
        '${event.end?.toIso8601String()}|${event.recurrenceRule}';
    return const Uuid().v5(Namespace.url.value, 'locus-ics:$seed');
  }

  // ==================== IMPORT FULL DATA FROM JSON ====================

  /// Reads the selected backup and returns a summary for confirmation.
  /// The JSON is cached so the subsequent import does not ask the user to
  /// select the same file twice.
  Future<BackupSummary?> inspectSelectedBackup({PasswordPrompt? prompt}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'locusbackup'],
      dialogTitle: 'Select Locus Backup File',
    );
    if (result == null || result.files.isEmpty) return null;

    final jsonString = await readBackupFile(
      File(result.files.single.path!),
      prompt: prompt,
    );
    final plan = BackupImportPlan.parse(jsonString);
    _pendingImportJson = jsonString;
    return BackupSummary(
      sections: plan.sections,
      counts: plan.counts,
      mergedSections: plan.mergedSections,
      untouchedSections: plan.untouchedSections,
      formatVersion: plan.formatVersion,
      canReplaceEverything: plan.canReplaceEverything,
    );
  }

  /// The result of the most recent successful import, for showing in the UI.
  RestoreReport? lastRestoreReport;

  /// Discards a previewed import and releases cached backup JSON.
  void discardPendingImport() {
    _pendingImportJson = null;
  }

  Future<bool> importFullDataFromJson({
    bool replaceEverything = false,
    PasswordPrompt? prompt,
  }) async {
    try {
      String jsonString;
      if (_pendingImportJson != null) {
        jsonString = _pendingImportJson!;
        _pendingImportJson = null;
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json', 'locusbackup'],
          dialogTitle: 'Select Locus Backup File',
        );
        if (result == null || result.files.isEmpty) return false;
        jsonString = await readBackupFile(
          File(result.files.single.path!),
          prompt: prompt,
        );
      }

      // Keep a local recovery point before replacing user data. This makes an
      // accidental or corrupted import recoverable without requiring a second
      // manual export first. A failure here includes the underlying error so
      // the import dialog can show why the recovery point was not written.
      await createRecoveryBackup();

      lastRestoreReport = await restoreFromJson(
        jsonString,
        replaceEverything: replaceEverything,
      );
      return true;
    } catch (e, st) {
      await ErrorLogService.log(e, st);
      rethrow;
    }
  }

  /// Reads an import file after applying the safety size limit.
  ///
  /// This is separate from the file-picker flow so the boundary can be
  /// regression-tested without depending on platform picker behavior.
  Future<String> readImportFile(File file) async {
    final length = await file.length();
    if (length > maxImportFileBytes) {
      throw FormatException(
        'Backup file is too large. Maximum size is '
        '${maxImportFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return file.readAsString();
  }

  /// Creates a durable recovery copy without opening a file picker.
  ///
  /// Throws [StateError] with the underlying cause when the copy cannot be
  /// written. Callers must not treat that as a silent skip.
  Future<String> createRecoveryBackup() async {
    try {
      final backupDir = await backupDirectoryFor();
      await backupDir.create(recursive: true);
      final stamp = AppClock.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backup = await buildAutomaticBackup();
      final file = File(
        '${backupDir.path}${Platform.pathSeparator}manual_$stamp'
        '${backup.extension}',
      );
      await file.writeAsString(backup.content);
      await _pruneBackups(backupDir);
      return file.path;
    } catch (e, st) {
      Error.throwWithStackTrace(
        StateError('Could not create a recovery backup: $e'),
        st,
      );
    }
  }

  Future<String> _appVersion() async {
    final injected = appVersionProvider;
    if (injected != null) return injected();
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) return fallbackAppVersion;
      final build = info.buildNumber.trim();
      return build.isEmpty ? version : '$version+$build';
    } catch (_) {
      return fallbackAppVersion;
    }
  }

  Future<void> _pruneBackups(Directory backupDir) async {
    final backups = await backupDir
        .list()
        .where(
          (entity) =>
              entity is File &&
              (entity.path.endsWith('.json') ||
                  entity.path.endsWith('.locusbackup')) &&
              (entity.path.contains('manual_') ||
                  entity.path.contains('pre_import_')),
        )
        .cast<File>()
        .toList();
    final modified = <File, DateTime>{};
    for (final backup in backups) {
      modified[backup] = (await backup.stat()).modified;
    }
    backups.sort((a, b) => modified[b]!.compareTo(modified[a]!));
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
  /// A partial backup replaces only the sections it contains, and the sections
  /// it omits are preserved *completely*. To keep that promise, a parent
  /// section is hard-replaced — rows absent from the file are deleted — only
  /// when every child section its foreign-key cascades would touch is itself
  /// present in the file. A projects-only import therefore never deletes a
  /// project: the rows in the file are inserted or updated, and unmentioned
  /// projects survive with their tasks, progress logs and focus-session links
  /// intact. Deleting projects through an import requires a backup that also
  /// carries `tasks`, `progress_logs` and `focus_sessions` (a full export
  /// always does).
  ///
  /// Child rows in the file may reference parents from the file itself *or*
  /// from the existing data, so a tasks-only backup restores its tasks against
  /// the projects already in the database instead of silently dropping them.
  ///
  /// Backups from other versions are restored on a best-effort basis rather
  /// than rejected: out-of-range numbers are moved into range, duplicates and
  /// rows whose parent is in neither the backup nor the database are skipped,
  /// and focus sessions that point at a missing project keep the session but
  /// lose the link. The returned [RestoreReport] says how much was changed.
  ///
  /// Settings are only replaced when the backup contains an `app_settings`
  /// section, and never the transient ones (see [AppDatabase.isTransientSetting]).
  Future<RestoreReport> restoreFromJson(
    String jsonString, {
    bool replaceEverything = false,
  }) async {
    final plan = BackupImportPlan.parse(
      jsonString,
      replaceEverything: replaceEverything,
    );
    final data = plan.data;

    var adjusted = 0;
    var skipped = 0;

    List<Map<String, dynamic>> uniqueRows(String key) {
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final row in _rows(data, key)) {
        final id = _id(row);
        if (!seen.add(id)) {
          skipped++;
          continue;
        }
        unique.add(row);
      }
      return unique;
    }

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

    final projectRows = uniqueRows('projects');
    final habitRows = uniqueRows('habits');
    final fileProjectIds = projectRows.map((r) => _str(r, 'id')).toSet();
    final fileHabitIds = habitRows.map((r) => _str(r, 'id')).toSet();

    final projects = [
      for (final p in projectRows)
        ProjectsCompanion(
          id: Value(_str(p, 'id')),
          name: Value(_str(p, 'name')),
          description: Value(_strOrNull(p, 'description')),
          createdAt: Value(_dt(p['createdAt'], 'createdAt')),
          targetDate: Value(_dtOrNull(p['targetDate'], 'targetDate')),
          targetProgress: Value(
            bounded(p, 'targetProgress', 0, 100, fallback: 100),
          ),
        ),
    ];

    // An unrecognised recurrence rule (from a newer app version) is kept as
    // written; the calendar shows such events as single events.
    final events = [
      for (final e in uniqueRows('events'))
        EventsCompanion(
          id: Value(_str(e, 'id')),
          title: Value(_str(e, 'title')),
          description: Value(_strOrNull(e, 'description')),
          startTime: Value(_dt(e['startTime'], 'startTime')),
          endTime: Value(_dtOrNull(e['endTime'], 'endTime')),
          category: Value(_strOrNull(e, 'category') ?? 'general'),
          hasReminder: Value(_bool(e, 'hasReminder', fallback: false)),
          reminderMinutes: Value(
            bounded(e, 'reminderMinutes', 0, 525600, fallback: 10),
          ),
          recurrenceRule: Value(_strOrNull(e, 'recurrenceRule')),
          allDay: Value(_bool(e, 'allDay', fallback: false)),
          recurrenceEnd: Value(_dtOrNull(e['recurrenceEnd'], 'recurrenceEnd')),
          recurrenceExceptions: Value(
            _stringListJson(e['recurrenceExceptions'], 'recurrenceExceptions'),
          ),
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
    for (final d in uniqueRows('diary_entries')) {
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

    final todoRows = uniqueRows('todo_items');
    final fileTodoIds = todoRows.map((t) => _str(t, 'id')).toSet();
    final planRows = uniqueRows('daily_plans');
    final filePlanIds = planRows.map((p) => _str(p, 'id')).toSet();

    // A section that is absent from a partial backup is intentionally left
    // untouched. Only sections explicitly present in the backup are replaced.
    final hasProjects = data.containsKey('projects');
    final hasEvents = data.containsKey('events');
    final hasHabits = data.containsKey('habits');
    final hasDiaryEntries = data.containsKey('diary_entries');
    final hasTodoItems = data.containsKey('todo_items');
    final hasTodoCompletions = data.containsKey('todo_completions');
    final hasFocusSessions = data.containsKey('focus_sessions');
    final hasTasks = data.containsKey('tasks');
    final hasProgressLogs = data.containsKey('progress_logs');
    final hasHabitLogs = data.containsKey('habit_logs');
    final hasDailyPlans = data.containsKey('daily_plans');
    final hasDailyPlanItems = data.containsKey('daily_plan_items');
    final hasSettings = data.containsKey('app_settings');

    // A parent table may only be hard-replaced (rows absent from the file
    // deleted) when every child section its foreign-key cascades would touch
    // is itself being replaced. Otherwise the replace would destroy rows in
    // a section the confirm dialog promised to preserve: a projects-only
    // import would delete the tasks of every project the file fails to
    // mention. When any child section is absent, the parent section is
    // merged instead — the rows in the file are inserted or updated,
    // unmentioned parents survive, and the preserved child rows keep
    // pointing at them.
    final replaceProjects = plan.replacesProjects;
    final replaceHabits = plan.replacesHabits;
    // A plan may only be hard-replaced when its item section is also in the
    // backup; otherwise deleting the plan would cascade into items the confirm
    // dialog promised to preserve. A plans-only import is merged instead.
    final replaceDailyPlans = hasDailyPlans && hasDailyPlanItems;

    // Child rows in the file may point at parents from the file itself or at
    // parents already in the database that a merged parent section leaves in
    // place — a tasks-only backup restores its tasks against the existing
    // projects. The ids are read before the transaction; if a parent vanishes
    // in that window, the foreign key rolls the whole import back, so
    // nothing is lost either way.
    final existingProjectIds = replaceProjects
        ? const <String>{}
        : (await db.select(db.projects).get()).map((p) => p.id).toSet();
    final existingHabitIds = replaceHabits
        ? const <String>{}
        : (await db.select(db.habits).get()).map((h) => h.id).toSet();
    final taskRows = uniqueRows('tasks');
    final fileTaskIds = taskRows.map((t) => _str(t, 'id')).toSet();
    final existingTaskIds = hasTasks
        ? const <String>{}
        : (await db.select(db.tasks).get()).map((t) => t.id).toSet();
    final existingTodoIds = hasTodoItems
        ? const <String>{}
        : (await db.select(db.todoItems).get()).map((t) => t.id).toSet();
    final existingPlans = replaceDailyPlans
        ? const <DailyPlan>[]
        : await db.select(db.dailyPlans).get();
    final existingPlanIds = existingPlans.map((p) => p.id).toSet();
    final existingPlanIdsByDay = {
      for (final plan in existingPlans) plan.dayKey: plan.id,
    };
    final linkableProjectIds = fileProjectIds.union(existingProjectIds);
    final linkableHabitIds = fileHabitIds.union(existingHabitIds);
    final linkableTaskIds = fileTaskIds.union(existingTaskIds);
    final linkableTodoIds = fileTodoIds.union(existingTodoIds);
    final linkablePlanIds = filePlanIds.union(existingPlanIds);

    // Resolve parent links before building the companions: a parent missing
    // from the file becomes a root, and a cycle is broken at the row that
    // closes it. Both are reported as adjusted values.
    final todoParentById = <String, String?>{};
    for (final t in todoRows) {
      final id = _str(t, 'id');
      final rawParent = _strOrNull(t, 'parentId');
      final parent =
          rawParent != null &&
              rawParent != id &&
              fileTodoIds.contains(rawParent)
          ? rawParent
          : null;
      if (rawParent != null && parent == null) adjusted++;
      todoParentById[id] = parent;
    }
    for (final id in todoParentById.keys.toList()) {
      final seen = <String>{};
      var cursor = todoParentById[id];
      while (cursor != null) {
        if (!seen.add(cursor)) {
          todoParentById[id] = null;
          adjusted++;
          break;
        }
        cursor = todoParentById[cursor];
      }
    }

    final todoDepth = <String, int>{};
    int depthOf(String id) {
      final cached = todoDepth[id];
      if (cached != null) return cached;
      final parent = todoParentById[id];
      final depth = parent == null ? 0 : depthOf(parent) + 1;
      todoDepth[id] = depth;
      return depth;
    }

    // A self-referencing foreign key requires parents to be inserted first,
    // so rows are ordered by their depth in the restored tree.
    final orderedTodoRows = [
      ...todoRows,
    ]..sort((a, b) => depthOf(_str(a, 'id')).compareTo(depthOf(_str(b, 'id'))));

    final todoItems = <TodoItemsCompanion>[];
    for (final t in orderedTodoRows) {
      final id = _str(t, 'id');
      final projectId = _strOrNull(t, 'projectId');
      final linked = linkableProjectIds.contains(projectId);
      if (projectId != null && !linked) adjusted++;
      todoItems.add(
        TodoItemsCompanion(
          id: Value(id),
          title: Value(_str(t, 'title')),
          notes: Value(_strOrNull(t, 'notes')),
          completed: Value(_bool(t, 'completed', fallback: false)),
          createdAt: Value(_dt(t['createdAt'], 'createdAt')),
          startDate: Value(_dtOrNull(t['startDate'], 'startDate')),
          dueDate: Value(_dtOrNull(t['dueDate'], 'dueDate')),
          priority: Value(bounded(t, 'priority', 0, 3, fallback: 0)),
          tags: Value(_tagJson(t['tags'])),
          recurrenceRule: Value(_strOrNull(t, 'recurrenceRule')),
          parentId: Value(todoParentById[id]),
          projectId: Value(linked ? projectId : null),
          reminderAt: Value(_dtOrNull(t['reminderAt'], 'reminderAt')),
        ),
      );
    }

    final todoCompletions = <TodoCompletionsCompanion>[];
    for (final c in uniqueRows('todo_completions')) {
      final todoId = _str(c, 'todoId');
      if (!linkableTodoIds.contains(todoId)) {
        skipped++;
        continue;
      }
      todoCompletions.add(
        TodoCompletionsCompanion(
          id: Value(_str(c, 'id')),
          todoId: Value(todoId),
          occurrenceDue: Value(_dtOrNull(c['occurrenceDue'], 'occurrenceDue')),
          completedAt: Value(_dt(c['completedAt'], 'completedAt')),
        ),
      );
    }

    final focusSessions = <FocusSessionsCompanion>[];
    for (final f in uniqueRows('focus_sessions')) {
      final projectId = _strOrNull(f, 'projectId');
      final linked = linkableProjectIds.contains(projectId);
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
    for (final t in taskRows) {
      if (!linkableProjectIds.contains(_str(t, 'projectId'))) {
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
    for (final p in uniqueRows('progress_logs')) {
      if (!linkableProjectIds.contains(_str(p, 'projectId'))) {
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
    for (final h in uniqueRows('habit_logs')) {
      final habitId = _str(h, 'habitId');
      final date = DayMath.dateOnly(_dt(h['date'], 'date'));
      if (!linkableHabitIds.contains(habitId) ||
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

    // Daily plans are additive planning records. A plan whose day already
    // exists under a different id is skipped when the plan section is merged,
    // because the one-plan-per-day index would reject it.
    final dailyPlans = <DailyPlansCompanion>[];
    final seenDayKeys = <String>{};
    for (final p in planRows) {
      final id = _str(p, 'id');
      final dayKey = _str(p, 'dayKey');
      if (!_isDayKey(dayKey)) {
        skipped++;
        continue;
      }
      final existingId = existingPlanIdsByDay[dayKey];
      if ((existingId != null && existingId != id) ||
          !seenDayKeys.add(dayKey)) {
        skipped++;
        continue;
      }
      final intention = _strOrNull(p, 'intention');
      dailyPlans.add(
        DailyPlansCompanion(
          id: Value(id),
          dayKey: Value(dayKey),
          intention: Value(
            intention == null || intention.trim().isEmpty ? null : intention,
          ),
          createdAt: Value(_dt(p['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(p['updatedAt'], 'updatedAt')),
        ),
      );
    }

    final dailyPlanItems = <DailyPlanItemsCompanion>[];
    final seenPlanTasks = <String>{};
    for (final i in uniqueRows('daily_plan_items')) {
      final planId = _str(i, 'planId');
      final todoId = _strOrNull(i, 'todoItemId');
      final taskId = _strOrNull(i, 'projectTaskId');
      if (!linkablePlanIds.contains(planId) ||
          (todoId != null) == (taskId != null)) {
        skipped++;
        continue;
      }
      final taskKey = todoId != null ? 'todo:$todoId' : 'task:$taskId';
      if (!seenPlanTasks.add('$planId|$taskKey') ||
          (todoId != null && !linkableTodoIds.contains(todoId)) ||
          (taskId != null && !linkableTaskIds.contains(taskId))) {
        skipped++;
        continue;
      }
      var minutes = i['plannedMinutes'] == null
          ? null
          : _int(i, 'plannedMinutes');
      if (minutes != null && minutes <= 0) {
        minutes = null;
        adjusted++;
      }
      dailyPlanItems.add(
        DailyPlanItemsCompanion(
          id: Value(_str(i, 'id')),
          planId: Value(planId),
          todoItemId: Value(todoId),
          projectTaskId: Value(taskId),
          sortOrder: Value(_int(i, 'sortOrder', fallback: 0)),
          plannedMinutes: Value(minutes),
          createdAt: Value(_dt(i['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(i['updatedAt'], 'updatedAt')),
        ),
      );
    }

    // Settings are replaced only when the backup carries them, so restoring an
    // older backup doesn't reset the theme and notification choices.
    final seenSettingKeys = <String>{};
    final settings = <AppSettingsCompanion>[];
    for (final s in _rows(data, 'app_settings')) {
      final key = _str(s, 'key');
      if (AppDatabase.isTransientSetting(key) || !seenSettingKeys.add(key)) {
        if (!AppDatabase.isTransientSetting(key)) skipped++;
        continue;
      }
      settings.add(
        AppSettingsCompanion(key: Value(key), value: Value(_str(s, 'value'))),
      );
    }

    // Everything parsed successfully; now replace the selected sections atomically.
    await db.transaction(() async {
      // Children first, then parents. Delete only the sections supplied by
      // the backup, and delete a parent table only when all of its child
      // sections are being replaced too (see [replaceProjects]); otherwise
      // its rows are merged in the batch below, and the child rows of an
      // unmentioned parent keep their parent instead of being cascaded away.
      if (hasProgressLogs) await db.delete(db.progressLogs).go();
      if (hasDailyPlanItems) await db.delete(db.dailyPlanItems).go();
      if (replaceDailyPlans) await db.delete(db.dailyPlans).go();
      if (hasTasks) await db.delete(db.tasks).go();
      if (hasHabitLogs) await db.delete(db.habitLogs).go();
      if (hasFocusSessions) await db.delete(db.focusSessions).go();
      if (hasTodoCompletions) await db.delete(db.todoCompletions).go();
      if (hasTodoItems) await db.delete(db.todoItems).go();
      if (hasDiaryEntries) await db.delete(db.diaryEntries).go();
      if (replaceHabits) await db.delete(db.habits).go();
      if (hasEvents) await db.delete(db.events).go();
      if (replaceProjects) await db.delete(db.projects).go();
      if (hasSettings) {
        // Transient rows (a focus session in progress, the auto-backup clock)
        // describe this machine right now and must survive the import.
        await (db.delete(
          db.appSettings,
        )..where((t) => t.key.isNotIn(AppDatabase.transientSettingKeys))).go();
      }

      // Parents first, then children (foreign keys are enforced). A parent
      // section that is not fully replaced is upserted, so a row in the file
      // updates its same-id counterpart while unmentioned rows survive.
      await db.batch((b) {
        if (hasProjects) {
          if (replaceProjects) {
            b.insertAll(db.projects, projects);
          } else {
            b.insertAllOnConflictUpdate(db.projects, projects);
          }
        }
        if (hasEvents) b.insertAll(db.events, events);
        if (hasHabits) {
          if (replaceHabits) {
            b.insertAll(db.habits, habits);
          } else {
            b.insertAllOnConflictUpdate(db.habits, habits);
          }
        }
        if (hasDiaryEntries) b.insertAll(db.diaryEntries, diaryEntries);
        if (hasTodoItems) b.insertAll(db.todoItems, todoItems);
        if (hasTodoCompletions) {
          b.insertAll(db.todoCompletions, todoCompletions);
        }
        if (hasFocusSessions) {
          b.insertAll(db.focusSessions, focusSessions);
        }
        if (hasTasks) b.insertAll(db.tasks, tasks);
        if (hasDailyPlans) {
          if (replaceDailyPlans) {
            b.insertAll(db.dailyPlans, dailyPlans);
          } else {
            b.insertAllOnConflictUpdate(db.dailyPlans, dailyPlans);
          }
        }
        if (hasDailyPlanItems) {
          b.insertAll(db.dailyPlanItems, dailyPlanItems);
        }
        if (hasProgressLogs) b.insertAll(db.progressLogs, progressLogs);
        if (hasHabitLogs) b.insertAll(db.habitLogs, habitLogs);
        if (hasSettings) {
          b.insertAll(db.appSettings, settings);
        }
      });
    });

    return RestoreReport(adjustedValues: adjusted, skippedRows: skipped);
  }

  /// A strict `YYYY-MM-DD` check. `DateTime.tryParse` alone would accept
  /// `2026-02-30` and silently normalise it into March.
  static bool _isDayKey(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return false;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }

  // ---------- parsing helpers (throw FormatException with a useful message) ----------

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return const [];
    final value = data[key];
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

  String _id(Map<String, dynamic> row) {
    final id = _str(row, 'id');
    if (id.trim().isEmpty) {
      throw const FormatException('Backup row contains an empty id.');
    }
    return id;
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

  /// Accepts the JSON array written by exports, a hand-written list, or the
  /// older comma-separated form, and always returns canonical JSON.
  String _tagJson(Object? value) {
    final tags = <String>[];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) tags.addAll(decoded.whereType<String>());
        } catch (_) {
          // A corrupt tag value must not discard the rest of the backup.
        }
      } else if (trimmed.isNotEmpty) {
        tags.addAll(trimmed.split(','));
      }
    } else if (value is List) {
      tags.addAll(value.whereType<String>());
    } else if (value != null) {
      throw const FormatException('Invalid "tags" in backup row.');
    }

    final seen = <String>{};
    final normalized = <String>[];
    for (final tag in tags) {
      final trimmed = tag.trim();
      if (trimmed.isEmpty || !seen.add(trimmed.toLowerCase())) continue;
      normalized.add(trimmed);
    }
    return jsonEncode(normalized);
  }

  /// Normalises a JSON array of ISO dates into today's canonical form. Invalid
  /// entries are dropped: a bad exception date must not discard the series.
  String _stringListJson(Object? value, String key) {
    final raw = <String>[];
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return '[]';
      if (trimmed.startsWith('[')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) raw.addAll(decoded.whereType<String>());
        } on FormatException {
          throw FormatException('Invalid "$key" in backup row.');
        }
      } else {
        raw.addAll(trimmed.split(','));
      }
    } else if (value is List) {
      raw.addAll(value.whereType<String>());
    } else if (value != null) {
      throw FormatException('Invalid "$key" in backup row.');
    }

    final days = <String>{};
    for (final entry in raw) {
      final parsed = DateTime.tryParse(entry.trim());
      if (parsed == null) continue;
      final year = parsed.year.toString().padLeft(4, '0');
      final month = parsed.month.toString().padLeft(2, '0');
      final day = parsed.day.toString().padLeft(2, '0');
      days.add('$year-$month-$day');
    }
    return jsonEncode(days.toList());
  }

  // ==================== ICS HELPERS ====================

  /// Builds an RFC 5545 calendar for [events] (CRLF line endings, escaped text,
  /// folded long lines, DTSTAMP on every event). Pure, so it can be unit tested.
  static DateTime _icsStart(Event event) {
    // RFC 5545 treats DTSTART as the first instance. Locus weekday series
    // intentionally move weekend starts to the following Monday. Export the
    // first actual Locus occurrence so external calendars agree.
    if (event.recurrenceRule == Recurrence.weekdays &&
        event.startTime.weekday >= DateTime.saturday) {
      return Recurrence.next(
            event.startTime,
            event.recurrenceRule,
            from: event.startTime.subtract(const Duration(seconds: 1)),
          ) ??
          event.startTime;
    }
    return event.startTime;
  }

  static String buildIcsCalendar(List<Event> events, {DateTime? now}) {
    final stamp = _formatDateTime(now ?? AppClock.now());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Locus Planner//EN',
      'CALSCALE:GREGORIAN',
    ];

    for (final event in events) {
      final start = _icsStart(event);
      lines
        ..add('BEGIN:VEVENT')
        ..add('UID:${event.id}@locusplanner')
        ..add('DTSTAMP:$stamp')
        ..add(
          'DTSTART${event.allDay ? ';VALUE=DATE' : ''}:'
          '${_formatEventDateTime(start, event.recurrenceRule, allDay: event.allDay)}',
        );
      final end = event.endTime;
      if (end != null) {
        final startShift = start.difference(event.startTime);
        lines.add(
          'DTEND${event.allDay ? ';VALUE=DATE' : ''}:'
          '${_formatEventDateTime(end.add(startShift), event.recurrenceRule, allDay: event.allDay)}',
        );
      }
      lines.add('SUMMARY:${_escapeIcsText(event.title)}');
      final rrule = Recurrence.toRRule(event.recurrenceRule);
      if (rrule != null) {
        final until = event.recurrenceEnd;
        lines.add(
          until == null
              ? 'RRULE:$rrule'
              : 'RRULE:$rrule;UNTIL=${_formatUntil(until, event.allDay)}',
        );
      }
      final exceptions = Recurrence.exceptionDayKeys(
        event.recurrenceExceptions,
      );
      if (exceptions.isNotEmpty) {
        lines.add(
          'EXDATE:${_formatExceptions(exceptions, start, event.allDay)}',
        );
      }
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
      if (!event.allDay && event.hasReminder && event.reminderMinutes >= 0) {
        lines
          ..add('BEGIN:VALARM')
          ..add('ACTION:DISPLAY')
          ..add('DESCRIPTION:${_escapeIcsText(event.title)}')
          ..add('TRIGGER:-PT${event.reminderMinutes}M')
          ..add('END:VALARM');
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
            DateTime(
              year,
              month,
              lastDay,
              start.hour,
              start.minute,
              start.second,
              start.millisecond,
              start.microsecond,
            ),
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

  static String _formatEventDateTime(
    DateTime dt,
    String? recurrenceRule, {
    bool allDay = false,
  }) {
    if (allDay) return DateFormat('yyyyMMdd').format(dt);
    if (Recurrence.isRecurring(recurrenceRule)) {
      return DateFormat("yyyyMMdd'T'HHmmss").format(dt);
    }
    return _formatDateTime(dt);
  }

  static String _formatUntil(DateTime dt, bool allDay) {
    if (allDay) return DateFormat('yyyyMMdd').format(dt);
    return DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());
  }

  static String _formatExceptions(
    Set<String> days,
    DateTime start,
    bool allDay,
  ) {
    final sorted = days.toList()..sort();
    return sorted
        .map((key) {
          final day = DateTime.parse(key);
          if (allDay) return DateFormat('yyyyMMdd').format(day);
          return DateFormat("yyyyMMdd'T'HHmmss").format(
            DateTime(
              day.year,
              day.month,
              day.day,
              start.hour,
              start.minute,
              start.second,
            ),
          );
        })
        .join(',');
  }
}
