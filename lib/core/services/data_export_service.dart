import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../domain/project_status.dart';
import '../security/atomic_file.dart';
import '../planning/saved_filter.dart';
import '../security/database_bootstrap.dart';
import '../security/database_lifecycle_lock.dart';
import '../security/database_paths.dart';
import '../security/database_security_options.dart';
import '../utils/completion_slot.dart';
import 'backup_encryption_service.dart';
import 'crypto/encrypted_envelope.dart';
import 'crypto/key_derivation.dart';
import 'error_log_service.dart';
import 'ics_export_service.dart';
import 'ics_import_service.dart';
export 'ics_import_service.dart' show IcsImportReport, IcsPreview;
import 'undo_service.dart';
import '../utils/day_math.dart';
import '../utils/app_clock.dart';

/// Asks the user for a backup passphrase. Return null to cancel.
typedef PasswordPrompt = Future<String?> Function(String message);

/// Logical backup format written by this build.
///
/// v5 adds `import_receipts`. v4 added the `attachments` metadata section and
/// an explicit `attachments_included: false` flag. Blob bytes are never part of
/// a logical JSON backup; the `.locusarchive` container carries them separately.
const backupFormatVersion = 5;

/// Deterministic JSON used for manifest checksums.
///
/// Object keys are sorted so a backup written by one platform verifies on
/// another, and so a whitespace-only edit does not look like data corruption.
String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    final buffer = StringBuffer('{');
    for (var index = 0; index < keys.length; index++) {
      if (index > 0) buffer.write(',');
      final key = keys[index];
      buffer
        ..write(jsonEncode(key))
        ..write(':')
        ..write(_canonicalJson(value[key]));
    }
    buffer.write('}');
    return buffer.toString();
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}

String _sha256Hex(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Map<String, dynamic> _sectionRowsFrom(Map<String, dynamic> decoded) {
  final nested = decoded['sections'];
  final rows = <String, dynamic>{};
  for (final key in BackupImportPlan.allSections) {
    final topLevel = decoded[key];
    final inner = nested is Map<String, dynamic> ? nested[key] : null;
    final value = topLevel ?? inner;
    if (value != null) rows[key] = value;
  }
  return rows;
}

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
    'task_schedule_blocks',
    'project_statuses',
    'project_milestones',
    'task_dependencies',
    'saved_filters',
    'planning_preferences',
    'working_hours',
    'working_breaks',
    'progress_logs',
    'attachments',
    'import_receipts',
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
    'task_schedule_blocks',
    'project_statuses',
    'project_milestones',
    'task_dependencies',
    'saved_filters',
    'planning_preferences',
    'working_hours',
    'working_breaks',
    'progress_logs',
    'attachments',
    'import_receipts',
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
    if (version != null && version > backupFormatVersion) {
      throw FormatException(
        'Backup format version $version is newer than this app supports.',
      );
    }
    if (version != null && version < 1) {
      throw FormatException('Invalid backup format version $version.');
    }

    final sectionRows = _sectionRowsFrom(decoded);
    final invalidSections = sectionRows.entries
        .where((entry) => entry.value is! List)
        .map((entry) => entry.key)
        .toList();
    if (invalidSections.isNotEmpty) {
      throw FormatException(
        'Backup sections must be arrays: ${invalidSections.join(', ')}',
      );
    }
    if (sectionRows.isEmpty) {
      throw const FormatException(
        'Backup contains no recognized data sections.',
      );
    }

    // v3 manifest: authenticate the payload and every table before any row is
    // written. A mismatch means a damaged or edited file, never a "best
    // effort" restore.
    final expectedPayloadHash = decoded['payload_sha256'];
    if (expectedPayloadHash != null) {
      if (expectedPayloadHash is! String) {
        throw const FormatException('Backup checksum is invalid.');
      }
      final actual = _sha256Hex(_canonicalJson(sectionRows));
      if (actual != expectedPayloadHash) {
        throw const FormatException(
          'Backup checksum does not match its contents.',
        );
      }
    }
    final tableManifest = decoded['tables'];
    if (tableManifest is Map<String, dynamic>) {
      for (final entry in sectionRows.entries) {
        final meta = tableManifest[entry.key];
        if (meta is! Map<String, dynamic>) continue;
        final rows = entry.value as List;
        final expectedRows = meta['rows'];
        if (expectedRows is int && expectedRows != rows.length) {
          throw FormatException(
            'Backup table "${entry.key}" has ${rows.length} rows, '
            'expected $expectedRows.',
          );
        }
        final expectedHash = meta['sha256'];
        if (expectedHash is String) {
          final actual = _sha256Hex(_canonicalJson(rows));
          if (actual != expectedHash) {
            throw FormatException(
              'Backup table "${entry.key}" does not match its checksum.',
            );
          }
        }
      }
    }

    final originalSections = sectionRows.keys.toSet();
    if (replaceEverything && version != null && version >= 2) {
      throw const FormatException(
        'Replace everything is only available for older backup formats.',
      );
    }
    final effectiveData = <String, dynamic>{...decoded, ...sectionRows};
    if (replaceEverything) {
      for (final section in dataSections) {
        effectiveData[section] = effectiveData[section] ?? <dynamic>[];
      }
    }
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
      'project_statuses',
      'project_milestones',
      'task_dependencies',
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
  static const fallbackAppVersion = '1.6.1+6';

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

  /// Serialises the whole database to the v3 backup JSON document.
  ///
  /// Every table is read inside one transaction, so the manifest and the rows
  /// it describes come from exactly the same snapshot. Dates are written by
  /// Drift's default serializer (milliseconds since the epoch);
  /// [restoreFromJson] accepts that as well as ISO-8601 strings.
  ///
  /// [backupEncryption] records how the document will be stored: `none` for a
  /// plaintext export, or the envelope identifier when the caller wraps it.
  Future<String> buildBackupJson({String backupEncryption = 'none'}) async {
    final context = DatabaseRuntimeContext.current;
    Future<String> build() async {
      final appVersion = await _appVersion();
      final document = await db.transaction(() async {
        final events = await db.select(db.events).get();
        final projects = await db.select(db.projects).get();
        final tasks = await db.select(db.tasks).get();
        final diaryEntries = await db.select(db.diaryEntries).get();
        final habits = await db.select(db.habits).get();
        final habitLogs = await db.select(db.habitLogs).get();
        final focusSessions = await db.select(db.focusSessions).get();
        final todoItems = await db.select(db.todoItems).get();
        final todoCompletions = await db.select(db.todoCompletions).get();
        final dailyPlans = await db.select(db.dailyPlans).get();
        final dailyPlanItems = await db.select(db.dailyPlanItems).get();
        final scheduleBlocks = await db.select(db.taskScheduleBlocks).get();
        final projectStatuses = await db.select(db.projectStatuses).get();
        final projectMilestones = await db.select(db.projectMilestones).get();
        final taskDependencies = await db.select(db.taskDependencies).get();
        final savedFilters = await db.select(db.savedFilters).get();
        final planningPreferences = await db
            .select(db.planningPreferences)
            .get();
        final workingHours = await db.select(db.workingHours).get();
        final workingBreaks = await db.select(db.workingBreaks).get();
        final progressLogs = await db.select(db.progressLogs).get();
        final attachments = await db.select(db.attachments).get();
        final importReceipts = await db
            .customSelect('SELECT * FROM import_receipts')
            .get();
        final settings = await db.select(db.appSettings).get();
        final exportedSettings = settings
            .where((s) => !AppDatabase.isTransientSetting(s.key))
            .toList();

        final sections = <String, List<Map<String, dynamic>>>{
          'events': _sortedRows(events.map((e) => e.toJson())),
          'projects': _sortedRows(projects.map((p) => p.toJson())),
          'tasks': _sortedRows(tasks.map((t) => t.toJson())),
          'diary_entries': _sortedRows(diaryEntries.map((d) => d.toJson())),
          'habits': _sortedRows(habits.map((h) => h.toJson())),
          'habit_logs': _sortedRows(habitLogs.map((h) => h.toJson())),
          'focus_sessions': _sortedRows(focusSessions.map((f) => f.toJson())),
          'todo_items': _sortedRows(todoItems.map((t) => t.toJson())),
          'todo_completions': _sortedRows(
            todoCompletions.map((c) => c.toJson()),
          ),
          'daily_plans': _sortedRows(dailyPlans.map((p) => p.toJson())),
          'daily_plan_items': _sortedRows(
            dailyPlanItems.map((i) => i.toJson()),
          ),
          'task_schedule_blocks': _sortedRows(
            scheduleBlocks.map((b) => b.toJson()),
          ),
          'project_statuses': _sortedRows(
            projectStatuses.map((s) => s.toJson()),
          ),
          'project_milestones': _sortedRows(
            projectMilestones.map((m) => m.toJson()),
          ),
          'task_dependencies': _sortedRows(
            taskDependencies.map((d) => d.toJson()),
          ),
          'saved_filters': _sortedRows(savedFilters.map((f) => f.toJson())),
          'planning_preferences': _sortedRows(
            planningPreferences.map((p) => p.toJson()),
          ),
          'working_hours': _sortedRows(workingHours.map((h) => h.toJson())),
          'working_breaks': _sortedRows(workingBreaks.map((b) => b.toJson())),
          'progress_logs': _sortedRows(progressLogs.map((p) => p.toJson())),
          // Metadata only. The local `attachment_blobs` cache is never exported.
          'attachments': _sortedRows(attachments.map((a) => a.toJson())),
          'import_receipts': [
            for (final row in importReceipts)
              Map<String, dynamic>.from(row.data),
          ],
          'app_settings': _sortedRows(
            exportedSettings.map((s) => s.toJson()),
            key: 'key',
          ),
        };

        final tables = <String, Map<String, Object?>>{
          for (final entry in sections.entries)
            entry.key: <String, Object?>{
              'rows': entry.value.length,
              'sha256': _sha256Hex(_canonicalJson(entry.value)),
            },
        };

        return <String, dynamic>{
          'exported_at': AppClock.now().toIso8601String(),
          'format_version': backupFormatVersion,
          'version': appVersion,
          'database_schema_version': AppDatabase.currentSchemaVersion,
          'source_database_id': await db.sourceDatabaseId(),
          'backup_encryption': backupEncryption,
          // Logical backups never carry blob bytes. A future .locusarchive
          // writes them as separate authenticated entries.
          'attachments_included': false,
          'payload_sha256': _sha256Hex(_canonicalJson(sections)),
          'tables': tables,
          ...sections,
        };
      });
      return const JsonEncoder.withIndent('  ').convert(document);
    }

    if (context == null) return build();
    // A shared lock keeps the snapshot from overlapping a migration, rotation
    // or raw restore, which take the exclusive side of the same lock.
    return DatabaseLifecycleLock(
      context.paths.lifecycleLockFile,
    ).withLock(DatabaseLockMode.shared, build);
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
      final jsonString = await buildBackupJson(
        backupEncryption:
            '${EncryptedEnvelope.format}-v${EncryptedEnvelope.version}',
      );
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

  /// The passphrase used for unattended automatic backups, if configured.
  Future<String?> readAutomaticBackupPassphrase() async =>
      backupEncryption?.read();

  /// The content and extension for an automatic or recovery backup.
  ///
  /// Once database encryption (or the backup policy) requires encrypted
  /// automatic backups, an absent or unreadable passphrase is a hard failure.
  /// Falling back to a plaintext JSON file would silently defeat the setting.
  Future<({String content, String extension})> buildAutomaticBackup() async {
    String? passphrase;
    final encryption = backupEncryption;
    if (encryption != null) {
      passphrase = await encryption.read();
    }

    if (passphrase == null) {
      if (DatabaseSecurity.backupsMustBeEncrypted) {
        throw StateError(
          'Automatic backups must be encrypted, but no backup passphrase is '
          'configured. Set a backup passphrase or create a manual export.',
        );
      }
      return (content: await buildBackupJson(), extension: '.json');
    }

    final plain = await buildBackupJson(
      backupEncryption:
          '${EncryptedEnvelope.format}-v${EncryptedEnvelope.version}',
    );
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

  /// Writes an automatic backup through the durable temp+flush+rename path.
  ///
  /// Returns the final path. The caller prunes retention only after this
  /// returns, so a failed write never deletes a previous good backup.
  Future<String> writeAutomaticBackup({Directory? directory}) {
    return _writeBackup(prefix: 'auto', directory: directory);
  }

  /// Writes a pre-import recovery point through the same durable path.
  Future<String> writeRecoveryBackup({Directory? directory}) {
    return _writeBackup(prefix: 'manual', directory: directory);
  }

  Future<String> _writeBackup({
    required String prefix,
    Directory? directory,
  }) async {
    try {
      final backupDir = directory ?? await backupDirectoryFor();
      await backupDir.create(recursive: true);
      final stamp = AppClock.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final backup = await buildAutomaticBackup();
      final file = File(
        '${backupDir.path}${Platform.pathSeparator}${prefix}_$stamp'
        '${backup.extension}',
      );
      await _writeBackupDurably(file, backup.content);
      return file.path;
    } catch (e, st) {
      if (e is StateError) rethrow;
      Error.throwWithStackTrace(
        StateError('Could not write a $prefix backup: $e'),
        st,
      );
    }
  }

  /// Writes [content] to a temp file, flushes it, reads it back, and only then
  /// replaces [target]. A backup that cannot be read back is never promoted.
  Future<void> _writeBackupDurably(File target, String content) async {
    await target.parent.create(recursive: true);
    final temp = File(
      '${target.path}.tmp-${AppClock.now().microsecondsSinceEpoch}',
    );
    try {
      final handle = await temp.open(mode: FileMode.writeOnly);
      try {
        await handle.writeFrom(utf8.encode(content));
        await handle.flush();
      } finally {
        await handle.close();
      }
      final readBack = await temp.readAsString();
      if (_sha256Hex(readBack) != _sha256Hex(content)) {
        throw StateError('The backup did not survive a verification read.');
      }
      await AtomicFile.replace(temp, target);
    } finally {
      await AtomicFile.deleteIfExists(temp);
    }
  }

  /// Removes only unencrypted automatic, manual and pre-import JSON files plus
  /// plaintext migration copies. Encrypted files and quarantined originals are
  /// never touched.
  Future<int> deleteUnencryptedBackups() async {
    final dir = await backupDirectoryFor();
    var deleted = 0;

    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        if (!_isUnencryptedBackupName(p.basename(entity.path))) continue;
        await AtomicFile.deleteIfExists(entity);
        deleted++;
      }
    }

    // Pre-migration snapshots and interrupted migration temp files live next
    // to the database, which is the parent of the backups directory.
    final dataDir = dir.parent;
    if (await dataDir.exists()) {
      await for (final entity in dataDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        final isCandidate =
            name.contains('.pre-migration-v') && name.endsWith('.bak') ||
            name.contains('.encrypting-') ||
            name.contains('.move-');
        if (!isCandidate) continue;
        await AtomicFile.deleteIfExists(entity);
        deleted++;
      }
    }
    return deleted;
  }

  bool _isUnencryptedBackupName(String name) {
    if (name.endsWith('.json')) {
      return name.startsWith('auto_') ||
          name.startsWith('manual_') ||
          name.startsWith('pre_import_');
    }
    return (name.contains('.pre-migration-v') && name.endsWith('.bak')) ||
        (name.contains('.pre-encryption-') && name.endsWith('.plaintext.bak'));
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
    final support = await DatabasePathsResolver.secureDataDirectory();
    return Directory('${support.path}${Platform.pathSeparator}backups');
  }

  // ==================== ICS ====================

  static const maxIcsImportFileBytes = IcsImportService.maxFileBytes;

  static String buildIcsCalendar(
    List<Event> events, {
    DateTime? now,
    Map<String, int> attachmentCounts = const {},
  }) => IcsExportService.buildIcsCalendar(
    events,
    now: now,
    attachmentCounts: attachmentCounts,
  );

  Future<bool> exportEventsAsIcs() => const IcsExportService().export(db);

  Future<IcsPreview?> previewEventsFromIcs() =>
      IcsImportService(db, undo: undo).previewFromPicker();

  Future<IcsPreview> previewIcs(String source) =>
      IcsImportService(db, undo: undo).preview(source);

  Future<IcsImportReport?> importEventsFromIcs() =>
      IcsImportService(db, undo: undo).importFromPicker();

  Future<IcsImportReport> importEventsFromIcsText(String source) =>
      IcsImportService(db, undo: undo).importText(source);

  Future<IcsImportReport> importIcs(
    IcsPreview preview, {
    required bool keepSimplified,
  }) => IcsImportService(
    db,
    undo: undo,
  ).importPreview(preview, keepSimplified: keepSimplified);

  Future<String> readIcsFile(File file) =>
      IcsImportService(db, undo: undo).readFile(file);
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
      final path = await writeRecoveryBackup(directory: backupDir);
      await _pruneBackups(backupDir);
      return path;
    } catch (e, st) {
      if (e is StateError) rethrow;
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
    final eventRows = uniqueRows('events');
    final fileEventIds = eventRows.map((e) => _str(e, 'id')).toSet();
    final events = [
      for (final e in eventRows)
        EventsCompanion(
          id: Value(_str(e, 'id')),
          title: Value(_str(e, 'title')),
          description: Value(_strOrNull(e, 'description')),
          descriptionFormat: Value(
            _strOrNull(e, 'descriptionFormat') == 'md1' ? 'md1' : 'plain',
          ),
          startTime: Value(_dt(e['startTime'], 'startTime')),
          endTime: Value(_dtOrNull(e['endTime'], 'endTime')),
          category: Value(_strOrNull(e, 'category') ?? 'general'),
          hasReminder: Value(_bool(e, 'hasReminder', fallback: false)),
          reminderMinutes: Value(
            bounded(e, 'reminderMinutes', 0, 525600, fallback: 10),
          ),
          recurrenceRule: Value(_strOrNull(e, 'recurrenceRule')),
          recurrenceSpec: Value(_strOrNull(e, 'recurrenceSpec')),
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
    final hasScheduleBlocks = data.containsKey('task_schedule_blocks');
    final hasProjectStatuses = data.containsKey('project_statuses');
    final hasProjectMilestones = data.containsKey('project_milestones');
    final hasTaskDependencies = data.containsKey('task_dependencies');
    final hasSavedFilters = data.containsKey('saved_filters');
    final hasPlanningPreferences = data.containsKey('planning_preferences');
    final hasWorkingHours = data.containsKey('working_hours');
    final hasWorkingBreaks = data.containsKey('working_breaks');
    final hasAttachments = data.containsKey('attachments');
    final hasImportReceipts = data.containsKey('import_receipts');
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
    final existingEventIds = hasEvents
        ? const <String>{}
        : (await db.select(db.events).get()).map((e) => e.id).toSet();
    final linkableEventIds = fileEventIds.union(existingEventIds);

    // Attachment metadata only. A row whose parent is in neither the file nor
    // the existing database is skipped, and a logical backup never restores
    // blob bytes: the local cache is rebuilt by importing the files again.
    final attachments = <AttachmentsCompanion>[];
    for (final a in uniqueRows('attachments')) {
      final todoId = a['todoId'];
      final eventId = a['eventId'];
      final kind = a['kind'];
      final name = a['displayName'];
      final mime = a['mimeType'];
      final sha = a['sha256'];
      final size = a['sizeBytes'];
      final altText = _strOrNull(a, 'altText')?.trim();
      final validParent = (todoId is String) != (eventId is String);
      if (!validParent ||
          (altText != null && altText.length > 500) ||
          (kind != 'file' && kind != 'image') ||
          name is! String ||
          name.trim().isEmpty ||
          name.length > 200 ||
          mime is! String ||
          mime.trim().isEmpty ||
          mime.length > 120 ||
          sha is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
          size is! num ||
          size < 0) {
        skipped++;
        continue;
      }
      if (todoId is String && !linkableTodoIds.contains(todoId)) {
        skipped++;
        continue;
      }
      if (eventId is String && !linkableEventIds.contains(eventId)) {
        skipped++;
        continue;
      }
      int? dimension(Object? value) =>
          value is num && value > 0 && value <= 100000 ? value.toInt() : null;
      final position = a['position'];
      attachments.add(
        AttachmentsCompanion(
          id: Value(_id(a)),
          todoId: Value(todoId is String ? todoId : null),
          eventId: Value(eventId is String ? eventId : null),
          kind: Value(kind),
          displayName: Value(name.trim()),
          mimeType: Value(mime.trim()),
          sizeBytes: Value(size.toInt()),
          sha256: Value(sha),
          width: Value(dimension(a['width'])),
          height: Value(dimension(a['height'])),
          altText: Value(altText == null || altText.isEmpty ? null : altText),
          position: Value(
            position is num && position >= 0 && position <= 100000
                ? position.toInt()
                : 0,
          ),
          createdAt: Value(_dt(a['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(a['updatedAt'], 'updatedAt')),
        ),
      );
    }

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
          notesFormat: Value(
            _strOrNull(t, 'notesFormat') == 'md1' ? 'md1' : 'plain',
          ),
          completed: Value(_bool(t, 'completed', fallback: false)),
          createdAt: Value(_dt(t['createdAt'], 'createdAt')),
          startDate: Value(_dtOrNull(t['startDate'], 'startDate')),
          dueDate: Value(_dtOrNull(t['dueDate'], 'dueDate')),
          priority: Value(bounded(t, 'priority', 0, 3, fallback: 0)),
          tags: Value(_tagJson(t['tags'])),
          recurrenceRule: Value(_strOrNull(t, 'recurrenceRule')),
          recurrenceSpec: Value(_strOrNull(t, 'recurrenceSpec')),
          parentId: Value(todoParentById[id]),
          projectId: Value(linked ? projectId : null),
          reminderAt: Value(_dtOrNull(t['reminderAt'], 'reminderAt')),
          dueKind: Value(
            CompletionSlot.isKnownKind(_strOrNull(t, 'dueKind'))
                ? _strOrNull(t, 'dueKind')!
                : CompletionSlot.legacyInstant,
          ),
          dueDateKey: Value(_strOrNull(t, 'dueDateKey')),
          undatedGeneration: Value(_strOrNull(t, 'undatedGeneration')),
          estimatedMinutes: Value(
            _optionalPositiveInt(t['estimatedMinutes'], 'estimatedMinutes'),
          ),
          isImportant: Value(_bool(t, 'isImportant', fallback: false)),
          urgencyOverride: Value(
            _nullableBool(t['urgencyOverride'], 'urgencyOverride'),
          ),
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
          occurrenceKey: Value(_strOrNull(c, 'occurrenceKey')),
          slotKind: Value(
            CompletionSlot.isKnownKind(_strOrNull(c, 'slotKind'))
                ? _strOrNull(c, 'slotKind')!
                : CompletionSlot.legacyInstant,
          ),
          slotDate: Value(_strOrNull(c, 'slotDate')),
          slotGeneration: Value(_strOrNull(c, 'slotGeneration')),
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
      final completedFlag = _bool(t, 'completed', fallback: false);
      final rawStatus = _strOrNull(t, 'statusKey');
      final statusKey =
          rawStatus != null && ProjectStatusCatalog.contains(rawStatus)
          ? rawStatus
          : (completedFlag
                ? ProjectStatusCatalog.done.key
                : ProjectStatusCatalog.todo.key);
      tasks.add(
        TasksCompanion(
          id: Value(_str(t, 'id')),
          projectId: Value(_str(t, 'projectId')),
          title: Value(_str(t, 'title')),
          completed: Value(ProjectStatusCatalog.isDoneKey(statusKey)),
          statusKey: Value(statusKey),
          startDate: Value(_dtOrNull(t['startDate'], 'startDate')),
          dueDate: Value(_dtOrNull(t['dueDate'], 'dueDate')),
          estimatedMinutes: Value(
            _optionalPositiveInt(t['estimatedMinutes'], 'estimatedMinutes'),
          ),
          priority: Value(bounded(t, 'priority', 0, 3, fallback: 0)),
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
    // Only plans that were actually inserted may hold items. A plan skipped
    // because its day appears twice in the file is not linkable, even though
    // its id is in the file.
    final linkablePlanIds = {
      for (final plan in dailyPlans) plan.id.value,
      ...existingPlanIds,
    };
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

    // Phase 2 calendar blocks. Exactly one parent must survive, and the
    // interval is re-validated because a hand-edited backup must not create a
    // block that the repository would reject.
    final scheduleBlocks = <TaskScheduleBlocksCompanion>[];
    for (final b in uniqueRows('task_schedule_blocks')) {
      final todoId = _strOrNull(b, 'todoItemId');
      final taskId = _strOrNull(b, 'projectTaskId');
      if ((todoId == null) == (taskId == null)) {
        skipped++;
        continue;
      }
      if ((todoId != null && !linkableTodoIds.contains(todoId)) ||
          (taskId != null && !linkableTaskIds.contains(taskId))) {
        skipped++;
        continue;
      }
      final start = _dt(b['startAt'], 'startAt');
      final end = _dt(b['endAt'], 'endAt');
      final minutes = end.difference(start).inMinutes;
      if (minutes < 5 || minutes > 24 * 60) {
        skipped++;
        continue;
      }
      final kind = _strOrNull(b, 'blockKind') ?? 'work';
      if (!const {'work', 'focus', 'buffer'}.contains(kind)) {
        skipped++;
        continue;
      }
      scheduleBlocks.add(
        TaskScheduleBlocksCompanion(
          id: Value(_str(b, 'id')),
          todoItemId: Value(todoId),
          projectTaskId: Value(taskId),
          startAt: Value(start),
          endAt: Value(end),
          timezoneId: Value(_strOrNull(b, 'timezoneId')),
          blockKind: Value(kind),
          note: Value(
            _strOrNull(b, 'note')?.trim().isEmpty ?? true
                ? null
                : _strOrNull(b, 'note')!.trim(),
          ),
          createdAt: Value(_dt(b['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(b['updatedAt'], 'updatedAt')),
          sortOrder: Value(bounded(b, 'sortOrder', 0, 1000000, fallback: 0)),
        ),
      );
    }

    // Phase 3 project workflow. Status rows are display metadata for the five
    // fixed keys; an old backup without them gets the canonical defaults.
    final projectStatuses = <ProjectStatusesCompanion>[];
    final seenStatuses = <String>{};
    for (final status in uniqueRows('project_statuses')) {
      final projectId = _str(status, 'projectId');
      final rawKey = _strOrNull(status, 'statusKey');
      final name = _strOrNull(status, 'name')?.trim() ?? '';
      if (!linkableProjectIds.contains(projectId) ||
          rawKey == null ||
          !ProjectStatusCatalog.contains(rawKey) ||
          !seenStatuses.add('$projectId|$rawKey') ||
          name.isEmpty ||
          name.length > 40) {
        skipped++;
        continue;
      }
      final key = rawKey;
      final color = _strOrNull(status, 'colorToken') ?? 'blue';
      projectStatuses.add(
        ProjectStatusesCompanion(
          id: Value(_str(status, 'id')),
          projectId: Value(projectId),
          statusKey: Value(key),
          name: Value(name),
          colorToken: Value(
            ProjectStatusCatalog.colorTokens.contains(color) ? color : 'blue',
          ),
          position: Value(bounded(status, 'position', 0, 1000000, fallback: 0)),
          isDone: Value(ProjectStatusCatalog.isDoneKey(key)),
          isDefault: Value(_bool(status, 'isDefault', fallback: true)),
          createdAt: Value(_dt(status['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(status['updatedAt'], 'updatedAt')),
        ),
      );
    }
    final projectMilestones = <ProjectMilestonesCompanion>[];
    for (final milestone in uniqueRows('project_milestones')) {
      final projectId = _str(milestone, 'projectId');
      final title = _strOrNull(milestone, 'title')?.trim() ?? '';
      if (!linkableProjectIds.contains(projectId) || title.isEmpty) {
        skipped++;
        continue;
      }
      projectMilestones.add(
        ProjectMilestonesCompanion(
          id: Value(_str(milestone, 'id')),
          projectId: Value(projectId),
          title: Value(title),
          description: Value(
            _strOrNull(milestone, 'description')?.trim().isEmpty ?? true
                ? null
                : _strOrNull(milestone, 'description')!.trim(),
          ),
          targetDate: Value(_dtOrNull(milestone['targetDate'], 'targetDate')),
          completedAt: Value(
            _dtOrNull(milestone['completedAt'], 'completedAt'),
          ),
          position: Value(
            bounded(milestone, 'position', 0, 1000000, fallback: 0),
          ),
          createdAt: Value(_dt(milestone['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(milestone['updatedAt'], 'updatedAt')),
        ),
      );
    }

    final taskProjectById = <String, String>{
      for (final task in taskRows)
        if (linkableProjectIds.contains(_strOrNull(task, 'projectId')))
          _str(task, 'id'): _str(task, 'projectId'),
    };
    final taskDependencies = <TaskDependenciesCompanion>[];
    final seenDependencyPairs = <String>{};
    final dependencyAdjacency = <String, List<String>>{};
    for (final dependency in uniqueRows('task_dependencies')) {
      final predecessor = _str(dependency, 'predecessorTaskId');
      final successor = _str(dependency, 'successorTaskId');
      final type =
          _strOrNull(dependency, 'dependencyType') ?? 'finish_to_start';
      final pairKey = '$predecessor|$successor';
      if (predecessor == successor ||
          !linkableTaskIds.contains(predecessor) ||
          !linkableTaskIds.contains(successor) ||
          taskProjectById[predecessor] != taskProjectById[successor] ||
          type != 'finish_to_start' ||
          !seenDependencyPairs.add(pairKey)) {
        skipped++;
        continue;
      }
      // Keep the imported graph acyclic even if the file was hand-edited.
      final stack = <String>[successor];
      final seen = <String>{};
      var cycle = false;
      while (stack.isNotEmpty) {
        final current = stack.removeLast();
        if (current == predecessor) {
          cycle = true;
          break;
        }
        if (!seen.add(current)) continue;
        stack.addAll(dependencyAdjacency[current] ?? const []);
      }
      if (cycle) {
        skipped++;
        continue;
      }
      dependencyAdjacency.putIfAbsent(predecessor, () => []).add(successor);
      taskDependencies.add(
        TaskDependenciesCompanion(
          id: Value(_str(dependency, 'id')),
          predecessorTaskId: Value(predecessor),
          successorTaskId: Value(successor),
          dependencyType: Value(type),
          lagMinutes: Value(
            bounded(dependency, 'lagMinutes', 0, 10080, fallback: 0),
          ),
          createdAt: Value(_dt(dependency['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(dependency['updatedAt'], 'updatedAt')),
        ),
      );
    }

    // Saved views are stored as validated JSON. A definition this build does
    // not understand is skipped, never rewritten or executed.
    final savedFilters = <SavedFiltersCompanion>[];
    final seenFilterNames = <String>{};
    for (final f in uniqueRows('saved_filters')) {
      final scope = _str(f, 'entityScope');
      final name = _strOrNull(f, 'name')?.trim() ?? '';
      final filterJson = _strOrNull(f, 'filterJson');
      if (name.isEmpty ||
          !SavedFilterDefinition.scopes.contains(scope) ||
          filterJson == null ||
          !seenFilterNames.add('$scope|${name.toLowerCase()}')) {
        skipped++;
        continue;
      }
      final definitionVersion = bounded(
        f,
        'definitionVersion',
        1,
        SavedFilterDefinition.supportedVersion,
        fallback: SavedFilterDefinition.supportedVersion,
      );
      final SavedFilterDefinition definition;
      try {
        definition = SavedFilterDefinition.parse(
          scope: scope,
          filterJson: filterJson,
          sortJson: _strOrNull(f, 'sortJson') ?? '[]',
          definitionVersion: definitionVersion,
        );
      } on SavedFilterException {
        skipped++;
        continue;
      } on FormatException {
        skipped++;
        continue;
      }
      savedFilters.add(
        SavedFiltersCompanion(
          id: Value(_str(f, 'id')),
          name: Value(name),
          entityScope: Value(scope),
          filterJson: Value(definition.toFilterJson()),
          sortJson: Value(definition.toSortJson()),
          isPinned: Value(_bool(f, 'isPinned', fallback: false)),
          position: Value(bounded(f, 'position', 0, 1000000, fallback: 0)),
          createdAt: Value(_dt(f['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(f['updatedAt'], 'updatedAt')),
          definitionVersion: Value(definitionVersion),
        ),
      );
    }

    final planningPreferences = <PlanningPreferencesCompanion>[];
    final seenPreference = <String>{};
    for (final p in uniqueRows('planning_preferences')) {
      // One profile is supported; a malformed duplicate is ignored rather than
      // allowed to fight over the same defaults.
      if (!seenPreference.add('profile')) {
        skipped++;
        continue;
      }
      var dayStart = bounded(p, 'dayStartMinute', 0, 1439, fallback: 480);
      var dayEnd = bounded(p, 'dayEndMinute', 1, 1440, fallback: 1080);
      if (dayEnd <= dayStart) {
        dayStart = 480;
        dayEnd = 1080;
        adjusted++;
      }
      planningPreferences.add(
        PlanningPreferencesCompanion(
          id: Value(_str(p, 'id')),
          timezoneId: Value(_strOrNull(p, 'timezoneId')),
          defaultSlotMinutes: Value(
            bounded(p, 'defaultSlotMinutes', 5, 720, fallback: 30),
          ),
          weekStartDay: Value(bounded(p, 'weekStartDay', 1, 7, fallback: 1)),
          dayStartMinute: Value(dayStart),
          dayEndMinute: Value(dayEnd),
          bufferMinutes: Value(
            bounded(p, 'bufferMinutes', 0, 240, fallback: 10),
          ),
          urgencyWindowDays: Value(
            bounded(p, 'urgencyWindowDays', 1, 30, fallback: 3),
          ),
          createdAt: Value(_dt(p['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(p['updatedAt'], 'updatedAt')),
        ),
      );
    }

    final workingHours = <WorkingHoursCompanion>[];
    for (final h in uniqueRows('working_hours')) {
      final weekday = _int(h, 'weekday', fallback: 0);
      final start = _int(h, 'startMinute', fallback: 0);
      final end = _int(h, 'endMinute', fallback: 0);
      if (weekday < 1 || weekday > 7 || start < 0 || start > 1439) {
        skipped++;
        continue;
      }
      if (end < 1 || end > 1440 || end <= start) {
        skipped++;
        continue;
      }
      workingHours.add(
        WorkingHoursCompanion(
          id: Value(_str(h, 'id')),
          weekday: Value(weekday),
          enabled: Value(_bool(h, 'enabled', fallback: true)),
          startMinute: Value(start),
          endMinute: Value(end),
          createdAt: Value(_dt(h['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(h['updatedAt'], 'updatedAt')),
        ),
      );
    }

    final workingBreaks = <WorkingBreaksCompanion>[];
    for (final b in uniqueRows('working_breaks')) {
      final weekday = _int(b, 'weekday', fallback: 0);
      final start = _int(b, 'startMinute', fallback: 0);
      final end = _int(b, 'endMinute', fallback: 0);
      if (weekday < 1 || weekday > 7 || start < 0 || start > 1439) {
        skipped++;
        continue;
      }
      if (end < 1 || end > 1440 || end <= start) {
        skipped++;
        continue;
      }
      workingBreaks.add(
        WorkingBreaksCompanion(
          id: Value(_str(b, 'id')),
          weekday: Value(weekday),
          startMinute: Value(start),
          endMinute: Value(end),
          label: Value(_strOrNull(b, 'label')),
          createdAt: Value(_dt(b['createdAt'], 'createdAt')),
          updatedAt: Value(_dt(b['updatedAt'], 'updatedAt')),
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
      if (hasAttachments) await db.delete(db.attachments).go();
      if (hasImportReceipts) {
        await db.customStatement('DELETE FROM import_receipts');
      }
      if (hasProgressLogs) await db.delete(db.progressLogs).go();
      if (hasScheduleBlocks) await db.delete(db.taskScheduleBlocks).go();
      if (hasTaskDependencies) await db.delete(db.taskDependencies).go();
      if (hasProjectMilestones) await db.delete(db.projectMilestones).go();
      if (hasProjectStatuses) await db.delete(db.projectStatuses).go();
      if (hasDailyPlanItems) await db.delete(db.dailyPlanItems).go();
      if (replaceDailyPlans) await db.delete(db.dailyPlans).go();
      if (hasSavedFilters) await db.delete(db.savedFilters).go();
      if (hasWorkingBreaks) await db.delete(db.workingBreaks).go();
      if (hasWorkingHours) await db.delete(db.workingHours).go();
      if (hasPlanningPreferences) await db.delete(db.planningPreferences).go();
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
        if (projectStatuses.isNotEmpty) {
          b.insertAllOnConflictUpdate(db.projectStatuses, projectStatuses);
        }
        if (hasProjectMilestones) {
          b.insertAll(db.projectMilestones, projectMilestones);
        }
        if (hasTaskDependencies) {
          b.insertAll(db.taskDependencies, taskDependencies);
        }
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
        if (hasScheduleBlocks) {
          b.insertAll(db.taskScheduleBlocks, scheduleBlocks);
        }
        if (hasSavedFilters) b.insertAll(db.savedFilters, savedFilters);
        if (hasPlanningPreferences) {
          b.insertAll(db.planningPreferences, planningPreferences);
        }
        if (hasWorkingHours) b.insertAll(db.workingHours, workingHours);
        if (hasWorkingBreaks) b.insertAll(db.workingBreaks, workingBreaks);
        if (hasProgressLogs) b.insertAll(db.progressLogs, progressLogs);
        if (hasHabitLogs) b.insertAll(db.habitLogs, habitLogs);
        if (hasAttachments) b.insertAll(db.attachments, attachments);
        if (hasSettings) {
          b.insertAll(db.appSettings, settings);
        }
      });
      if (hasImportReceipts) {
        for (final row in data['import_receipts'] as List) {
          if (row is! Map) continue;
          final map = Map<String, dynamic>.from(row);
          final sourceKind = map['source_kind'];
          final destination = map['destination_id'];
          final fileHash = map['file_sha256'];
          final rowNumber = map['row_number'];
          final fingerprint = map['row_fingerprint'];
          final importedAt = map['imported_at_ms'];
          if (sourceKind is! String ||
              destination is! String ||
              fileHash is! String ||
              rowNumber is! int ||
              fingerprint is! String ||
              importedAt is! int) {
            skipped++;
            continue;
          }
          await db.customStatement(
            'INSERT OR REPLACE INTO import_receipts '
            '(source_kind, destination_id, file_sha256, row_number, '
            'target_id, row_fingerprint, imported_at_ms) '
            'VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              sourceKind,
              destination,
              fileHash,
              rowNumber,
              map['target_id'] is String ? map['target_id'] as String : null,
              fingerprint,
              importedAt,
            ],
          );
        }
      }
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

  bool? _nullableBool(Object? value, String key) {
    if (value == null) return null;
    if (value is! bool) throw FormatException('Invalid "$key" in backup row.');
    return value;
  }

  /// Optional positive duration in minutes. Zero, negative and absurd values
  /// become "no estimate" instead of discarding the task.
  int? _optionalPositiveInt(Object? value, String key) {
    if (value == null) return null;
    if (value is! num) {
      throw FormatException('Invalid "$key" in backup row.');
    }
    final minutes = value.toInt();
    if (minutes <= 0 || minutes > 525600) return null;
    return minutes;
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
}
