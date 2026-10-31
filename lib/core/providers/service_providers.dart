import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auto_backup_service.dart';
import '../services/app_lock_service.dart';
import '../services/data_export_service.dart';
import '../services/encrypted_diary_service.dart';
import '../services/launch_at_startup_service.dart';
import '../services/notification_service.dart';
import '../services/lan_sync_server.dart';
import 'database_provider.dart';
import '../services/undo_service.dart';
import '../services/window_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(db: ref.watch(databaseProvider));
  ref.onDispose(service.dispose);
  return service;
});

final windowServiceProvider = Provider<WindowService>((ref) {
  final service = WindowService();
  ref.onDispose(service.dispose);
  return service;
});

final launchAtStartupServiceProvider = Provider<LaunchAtStartupService>((ref) {
  return LaunchAtStartupService();
});

final undoServiceProvider = Provider<UndoService>((ref) {
  final service = UndoService();
  ref.onDispose(service.dispose);
  return service;
});

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(ref.watch(databaseProvider));
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

final encryptedDiaryServiceProvider = Provider<EncryptedDiaryService>((ref) {
  return EncryptedDiaryService(ref.watch(databaseProvider));
});

final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  return AutoBackupService(
    ref.watch(databaseProvider),
    ref.watch(dataExportServiceProvider),
  );
});

final lanSyncServerProvider = Provider<LanSyncServer>((ref) {
  final service = LanSyncServer(ref.watch(databaseProvider));
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});
