import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/data_export_service.dart';
import '../services/notification_service.dart';
import 'database_provider.dart';
import '../services/undo_service.dart';
import '../services/window_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.dispose);
  return service;
});

final windowServiceProvider = Provider<WindowService>((ref) {
  final service = WindowService();
  ref.onDispose(service.dispose);
  return service;
});

final undoServiceProvider = Provider<UndoService>((ref) {
  final service = UndoService();
  ref.onDispose(service.dispose);
  return service;
});

final dataExportServiceProvider = Provider<DataExportService>((ref) {
  return DataExportService(ref.watch(databaseProvider));
});
