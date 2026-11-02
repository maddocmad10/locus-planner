import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import 'data_export_service.dart';
import 'error_log_service.dart';
import '../utils/app_clock.dart';

/// Owns scheduled automatic backups and their retention policy.
class AutoBackupService {
  AutoBackupService(this._db, this._exportService, {this.backupDirectory});

  static const _retentionCount = 7;
  static const _interval = Duration(hours: 24);

  final AppDatabase _db;
  final DataExportService _exportService;
  final Directory? backupDirectory;

  Future<void> runIfDue() async {
    final raw = await _db.getSetting(AppDatabase.lastAutoBackupSettingKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final now = AppClock.now();
    if (last != null && now.difference(last) < _interval) return;

    final backupDir =
        backupDirectory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}'
          '${Platform.pathSeparator}backups',
        );
    await backupDir.create(recursive: true);

    final stamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    try {
      final backup = await _exportService.buildAutomaticBackup();
      final file = File(
        '${backupDir.path}${Platform.pathSeparator}auto_$stamp'
        '${backup.extension}',
      );
      await file.writeAsString(backup.content);
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      rethrow;
    }
    await _prune(backupDir);
    await _db.setSetting(
      AppDatabase.lastAutoBackupSettingKey,
      now.toIso8601String(),
    );
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
      (path.endsWith('.json') || path.endsWith('.locusbackup')) &&
      path.contains('${Platform.pathSeparator}auto_');
}
