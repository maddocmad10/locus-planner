import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../security/database_bootstrap.dart';
import '../security/database_paths.dart';
import '../services/attachments/attachment_crypto.dart';
import '../services/attachments/attachment_key_store.dart';
import '../services/attachments/attachment_service.dart';
import '../services/attachments/attachment_store.dart';
import '../services/auto_backup_service.dart';
import '../services/app_lock_service.dart';
import '../services/backup_encryption_service.dart';
import '../services/data_export_service.dart';
import '../services/encrypted_diary_service.dart';
import '../services/launch_at_startup_service.dart';
import '../services/notification_service.dart';
import '../services/lan_sync_server.dart';
import '../services/privacy_screen_service.dart';
import 'database_provider.dart';
import '../services/undo_service.dart';
import '../services/window_service.dart';

/// Loads the device-local blob key and prepares the encrypted attachment store.
///
/// Shared by the attachment UI and the LAN sync server so blobs received over
/// the LAN land in the same content-addressed store the UI reads.
final attachmentStoreProvider = FutureProvider<AttachmentStore>((ref) async {
  final key = await SecureAttachmentKeyStore().loadOrCreate();
  final root =
      DatabaseRuntimeContext.current?.paths.dataDirectory ??
      await DatabasePathsResolver.secureDataDirectory();
  final store = AttachmentStore(root: root, crypto: AttachmentCrypto(key));
  await store.ensureLayout();
  ref.onDispose(() {
    unawaited(store.clearOpenCopies());
  });
  return store;
});

/// Loads the attachment service. This is a [FutureProvider] because secure
/// Attachment counts per parent, used for the paperclip badge.
typedef AttachmentCounts = ({Map<String, int> todos, Map<String, int> events});

final attachmentCountsProvider = StreamProvider<AttachmentCounts>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.attachments).watch().map((rows) {
    final todos = <String, int>{};
    final events = <String, int>{};
    for (final row in rows) {
      final todoId = row.todoId;
      final eventId = row.eventId;
      if (todoId != null) {
        todos.update(todoId, (value) => value + 1, ifAbsent: () => 1);
      } else if (eventId != null) {
        events.update(eventId, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return (todos: todos, events: events);
  });
});

/// storage is asynchronous. Only attachment-aware widgets await it.
final attachmentServiceProvider = FutureProvider<AttachmentService>((
  ref,
) async {
  final store = await ref.watch(attachmentStoreProvider.future);
  final service = AttachmentService(
    ref.watch(databaseProvider),
    store,
    undo: ref.watch(undoServiceProvider),
  );
  await service.initialize();
  return service;
});

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
  return DataExportService(
    ref.watch(databaseProvider),
    undo: ref.watch(undoServiceProvider),
    backupEncryption: ref.watch(backupEncryptionServiceProvider),
  );
});

final backupEncryptionServiceProvider = Provider<BackupEncryptionService>((
  ref,
) {
  return BackupEncryptionService();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

final privacyScreenProvider = Provider<PrivacyScreen>((ref) {
  return const MethodChannelPrivacyScreen();
});

final encryptedDiaryServiceProvider = Provider<EncryptedDiaryService>((ref) {
  final export = ref.watch(dataExportServiceProvider);
  return EncryptedDiaryService(
    ref.watch(databaseProvider),
    recoveryBackup: () async {
      await export.createRecoveryBackup();
    },
  );
});

final autoBackupServiceProvider = Provider<AutoBackupService>((ref) {
  return AutoBackupService(
    ref.watch(databaseProvider),
    ref.watch(dataExportServiceProvider),
  );
});

final lanSyncServerProvider = Provider<LanSyncServer>((ref) {
  final store = ref.read(attachmentStoreProvider.future);
  final service = LanSyncServer(
    ref.watch(databaseProvider),
    blobStoreLoader: () => store,
  );
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});
