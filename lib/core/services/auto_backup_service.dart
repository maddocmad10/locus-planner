import 'dart:io';

import '../db/app_database.dart';
import 'attachments/attachment_service.dart';
import 'attachments/locus_archive.dart';
import 'backup_encryption_service.dart';
import 'data_export_service.dart';
import 'error_log_service.dart';
import '../utils/app_clock.dart';

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

  Future<void> runIfDue() async {
    final raw = await _db.getSetting(AppDatabase.lastAutoBackupSettingKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final now = AppClock.now();
    if (last != null && now.difference(last) < _interval) return;

    try {
      final backupDir =
          backupDirectory ?? await _exportService.backupDirectoryFor();
      await backupDir.create(recursive: true);
      final includeAttachments =
          await _db.getSetting(
            AppDatabase.automaticBackupsIncludeAttachmentsKey,
          ) ==
          '1';
      if (includeAttachments) {
        await _writeAttachmentArchive(backupDir);
      } else {
        // The export service owns the durable write: temp file, flush, read-back
        // verification, then atomic replace. Encryption is enforced there too.
        await _exportService.writeAutomaticBackup(directory: backupDir);
      }
      await _prune(backupDir);
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      rethrow;
    }

    // Record the cadence only after a backup was durably written. A failure
    // must retry on the next launch instead of waiting another 24 hours.
    await _db.setSetting(
      AppDatabase.lastAutoBackupSettingKey,
      now.toIso8601String(),
    );
  }

  Future<void> _writeAttachmentArchive(Directory backupDir) async {
    final passphrase = await backupEncryption?.read();
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
      await archiveService.create(
        db: _db,
        attachments: service,
        passphrase: passphrase,
        target: temp,
      );
      await temp.rename(target.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
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
