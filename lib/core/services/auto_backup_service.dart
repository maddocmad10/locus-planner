import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../db/app_database.dart';
import 'data_export_service.dart';

/// Owns scheduled automatic backups and their retention policy.
class AutoBackupService {
  AutoBackupService(this._db, this._exportService);

  static const _retentionCount = 7;
  static const _interval = Duration(hours: 24);

  final AppDatabase _db;
  final DataExportService _exportService;

  Future<void> runIfDue() async {
    final raw = await _db.getSetting(AppDatabase.lastAutoBackupSettingKey);
    final last = raw == null ? null : DateTime.tryParse(raw);
    final now = DateTime.now();
    if (last != null && now.difference(last) < _interval) return;

    final supportDir = await getApplicationSupportDirectory();
    final backupDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}backups',
    );
    await backupDir.create(recursive: true);

    final stamp = now
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(
      '${backupDir.path}${Platform.pathSeparator}auto_$stamp.json',
    );
    await file.writeAsString(await _exportService.buildBackupJson());
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
    files.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    for (final oldFile in files.skip(_retentionCount)) {
      await oldFile.delete();
    }
  }

  bool _isAutomatic(String path) =>
      path.endsWith('.json') && path.contains('${Platform.pathSeparator}auto_');
}
