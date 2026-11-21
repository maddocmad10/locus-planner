import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../db/app_database.dart';
import '../security/database_security_options.dart';
import '../utils/app_clock.dart';
import 'attachments/attachment_service.dart';
import 'attachments/locus_archive.dart';
import 'backup_encryption_service.dart';
import 'crypto/encrypted_envelope.dart';
import 'data_export_service.dart';
import 'error_log_service.dart';

enum BackupHealthState {
  setupNeeded,
  due,
  running,
  verified,
  incompleteArchive,
  failed,
}

class BackupHealth {
  const BackupHealth({
    required this.state,
    required this.lastAttempt,
    required this.lastVerified,
    required this.lastVerifiedFile,
    required this.format,
    required this.includeAttachments,
    required this.missingFiles,
    required this.failureCode,
    required this.nextDue,
  });

  final BackupHealthState state;
  final DateTime? lastAttempt;
  final DateTime? lastVerified;
  final String? lastVerifiedFile;
  final String? format;
  final bool includeAttachments;
  final int missingFiles;
  final String? failureCode;
  final DateTime? nextDue;
}

/// Owns scheduled automatic backups and their retention policy.
class AutoBackupService {
  AutoBackupService(
    this._db,
    this._exportService, {
    this.backupDirectory,
    this.attachments,
    this.backupEncryption,
    this.archiveService = const LocusArchiveService(),
  });

  static const _retentionCount = 7;
  static const _interval = Duration(hours: 24);

  final AppDatabase _db;
  final DataExportService _exportService;
  final Directory? backupDirectory;
  final Future<AttachmentService?> Function()? attachments;
  final BackupEncryptionService? backupEncryption;
  final LocusArchiveService archiveService;

  Future<void>? _inFlight;

  /// Runs automatic and manual attempts one at a time so two writers can never
  /// target the same file or prune each other's output.
  Future<T> _serialize<T>(Future<T> Function() action) async {
    while (_inFlight != null) {
      try {
        await _inFlight;
      } catch (_) {
        // A failed earlier attempt must not block the next one.
      }
    }
    final completer = Completer<void>();
    _inFlight = completer.future;
    try {
      return await action();
    } finally {
      _inFlight = null;
      completer.complete();
    }
  }

  Future<void> runIfDue() => _serialize(() async {
    final raw = await _db.getSetting(AppDatabase.lastAutoBackupSettingKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final now = AppClock.now();
    if (last != null && now.difference(last) < _interval) return;
    await _run(now);
  });

  /// User-initiated “Back up now”. It bypasses the cadence but still takes the
  /// same serialisation lock and verification path.
  Future<void> runNow() => _serialize(() => _run(AppClock.now()));

  Future<BackupHealth> health() async {
    final now = AppClock.now();
    final lastAuto = DateTime.tryParse(
      await _db.getSetting(AppDatabase.lastAutoBackupSettingKey) ?? '',
    );
    final lastAttempt = _date(
      await _db.getSetting(AppDatabase.backupHealthLastAttemptKey),
    );
    final lastVerified = _date(
      await _db.getSetting(AppDatabase.backupHealthLastVerifiedKey),
    );
    final failure = await _db.getSetting(
      AppDatabase.backupHealthLastFailureKey,
    );
    final missing =
        int.tryParse(
          await _db.getSetting(AppDatabase.backupHealthMissingFilesKey) ?? '0',
        ) ??
        0;
    final passphrase = await _passphrase();
    final includeAttachments =
        await _db.getSetting(
          AppDatabase.automaticBackupsIncludeAttachmentsKey,
        ) ==
        '1';
    final dueAt = lastAuto?.add(_interval);
    final state = switch (null) {
      _ when _inFlight != null => BackupHealthState.running,
      _ when passphrase == null && DatabaseSecurity.backupsMustBeEncrypted =>
        BackupHealthState.setupNeeded,
      _ when failure != null =>
        missing > 0
            ? BackupHealthState.incompleteArchive
            : BackupHealthState.failed,
      _ when lastVerified == null => BackupHealthState.setupNeeded,
      _ when dueAt == null || !now.isBefore(dueAt) => BackupHealthState.due,
      _ => BackupHealthState.verified,
    };
    return BackupHealth(
      state: state,
      lastAttempt: lastAttempt,
      lastVerified: lastVerified,
      lastVerifiedFile: await _db.getSetting(
        AppDatabase.backupHealthLastVerifiedFileKey,
      ),
      format: await _db.getSetting(AppDatabase.backupHealthFormatKey),
      includeAttachments: includeAttachments,
      missingFiles: missing,
      failureCode: failure,
      nextDue: dueAt,
    );
  }

  Future<void> _run(DateTime now) async {
    await _db.setSetting(
      AppDatabase.backupHealthLastAttemptKey,
      '${now.millisecondsSinceEpoch}',
    );
    try {
      final backupDir =
          backupDirectory ?? await _exportService.backupDirectoryFor();
      await backupDir.create(recursive: true);
      final includeAttachments =
          await _db.getSetting(
            AppDatabase.automaticBackupsIncludeAttachmentsKey,
          ) ==
          '1';
      final String path;
      final int missing;
      if (includeAttachments) {
        final result = await _writeAttachmentArchive(backupDir);
        path = result.file.path;
        missing = result.missingHashes.length;
      } else {
        path = await _exportService.writeAutomaticBackup(directory: backupDir);
        missing = 0;
        await _verifyLogicalFile(File(path));
      }
      if (missing > 0) {
        await _recordFailure(
          code: 'incomplete_archive',
          missing: missing,
          format: 'locusarchive',
          includeAttachments: true,
        );
        throw StateError(
          'The attachment archive is incomplete: $missing file'
          '${missing == 1 ? '' : 's'} missing. The previous verified copy was '
          'kept.',
        );
      }
      await _copyToIndependentDestination(File(path));
      await _prune(backupDir);
      await _db.setSetting(
        AppDatabase.lastAutoBackupSettingKey,
        now.toIso8601String(),
      );
      await _recordVerified(
        path: path,
        format: File(path).path.endsWith('.locusarchive')
            ? 'locusarchive'
            : 'locusbackup',
        includeAttachments: includeAttachments,
      );
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      await _recordFailure(
        code: _failureCode(error),
        missing: 0,
        format: 'auto',
        includeAttachments: false,
      );
      rethrow;
    }
  }

  Future<String?> _passphrase() async =>
      (await backupEncryption?.read()) ??
      (await _exportService.readAutomaticBackupPassphrase());

  Future<ArchiveBuildResult> _writeAttachmentArchive(
    Directory backupDir,
  ) async {
    final passphrase = await _passphrase();
    if (passphrase == null || passphrase.isEmpty) {
      throw StateError(
        'Automatic backups include attachments, but no backup passphrase is '
        'configured. Set a backup passphrase or turn the option off.',
      );
    }
    final service = await attachments?.call();
    if (service == null) {
      throw StateError(
        'Automatic attachment backups require the local attachment service.',
      );
    }
    final stamp = AppClock.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target = File(
      '${backupDir.path}${Platform.pathSeparator}auto_$stamp.locusarchive',
    );
    final temp = File('${target.path}.tmp');
    try {
      final result = await archiveService.create(
        db: _db,
        attachments: service,
        passphrase: passphrase,
        target: temp,
      );
      if (result.missingHashes.isNotEmpty) {
        // Never promote a partial archive over the previous full one.
        await temp.delete();
        return ArchiveBuildResult(
          file: target,
          blobCount: result.blobCount,
          missingHashes: result.missingHashes,
        );
      }
      await temp.rename(target.path);
      return ArchiveBuildResult(
        file: target,
        blobCount: result.blobCount,
        missingHashes: const [],
      );
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _verifyLogicalFile(File file) async {
    // Reuse the read path so a wrong key, corrupt envelope or unparseable
    // payload is detected before a backup is recorded as verified.
    final passphrase = await _passphrase();
    final raw = await file.readAsString();
    if (EncryptedEnvelope.looksEncrypted(raw)) {
      if (passphrase == null || passphrase.isEmpty) {
        throw StateError(
          'A backup passphrase is required to verify this file.',
        );
      }
      final opened = await EncryptedEnvelope.open(raw, passphrase);
      final decoded = jsonDecode(opened.plaintext);
      if (decoded is! Map || decoded['format_version'] == null) {
        throw const FormatException('The backup payload is incomplete.');
      }
      return;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['format_version'] == null) {
      throw const FormatException('The backup payload is incomplete.');
    }
  }

  Future<void> _copyToIndependentDestination(File source) async {
    final raw = await _db.getSetting(AppDatabase.backupIndependentDirectoryKey);
    if (raw == null || raw.trim().isEmpty) return;
    final directory = Directory(raw);
    if (directory.path == source.parent.path) return;
    await directory.create(recursive: true);
    final target = File(
      '${directory.path}${Platform.pathSeparator}'
      '${source.uri.pathSegments.last}',
    );
    final temp = File('${target.path}.tmp');
    try {
      await source.copy(temp.path);
      if (!temp.path.endsWith('.locusarchive')) {
        await _verifyLogicalFile(temp);
      }
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<void> _recordVerified({
    required String path,
    required String format,
    required bool includeAttachments,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.setSetting(AppDatabase.backupHealthLastVerifiedKey, '$now');
    await _db.setSetting(AppDatabase.backupHealthLastVerifiedFileKey, path);
    await _db.setSetting(AppDatabase.backupHealthFormatKey, format);
    await _db.setSetting(
      AppDatabase.backupHealthAttachmentsKey,
      includeAttachments ? '1' : '0',
    );
    await _db.setSetting(AppDatabase.backupHealthMissingFilesKey, '0');
    await _db.setSetting(AppDatabase.backupHealthLastFailureKey, '');
  }

  Future<void> _recordFailure({
    required String code,
    required int missing,
    required String format,
    required bool includeAttachments,
  }) async {
    await _db.setSetting(AppDatabase.backupHealthLastFailureKey, code);
    await _db.setSetting(AppDatabase.backupHealthMissingFilesKey, '$missing');
    await _db.setSetting(AppDatabase.backupHealthFormatKey, format);
    await _db.setSetting(
      AppDatabase.backupHealthAttachmentsKey,
      includeAttachments ? '1' : '0',
    );
  }

  String _failureCode(Object error) {
    final message = '$error'.toLowerCase();
    if (message.contains('passphrase')) return 'passphrase_missing';
    if (error is FileSystemException) return 'destination_unavailable';
    if (error is FormatException || message.contains('verify')) {
      return 'verification_failed';
    }
    if (message.contains('incomplete')) return 'incomplete_archive';
    return 'backup_failed';
  }

  static DateTime? _date(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final ms = int.tryParse(raw);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _prune(Directory backupDir) async {
    final files = await backupDir
        .list()
        .where((entity) => entity is File && _isAutomatic(entity.path))
        .cast<File>()
        .toList();
    final modified = <File, DateTime>{};
    for (final file in files) {
      modified[file] = (await file.stat()).modified;
    }
    files.sort((a, b) => modified[b]!.compareTo(modified[a]!));
    for (final oldFile in files.skip(_retentionCount)) {
      await oldFile.delete();
    }
  }

  bool _isAutomatic(String path) =>
      (path.endsWith('.json') ||
          path.endsWith('.locusbackup') ||
          path.endsWith('.locusarchive')) &&
      path.contains('${Platform.pathSeparator}auto_');
}
