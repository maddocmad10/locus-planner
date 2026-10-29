import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app.dart';
import 'features/mobile/mobile_app.dart';
import 'core/db/app_database.dart';
import 'core/db/startup_checks.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/service_providers.dart';
import 'core/services/error_log_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_outbox_pruner.dart';
import 'core/services/window_service.dart';
import 'core/services/single_instance_service.dart';
import 'core/services/window_reveal.dart';
import 'features/events/data/event_repository.dart';
import 'features/mobile/data/mobile_sync_client.dart';
import 'core/providers/quick_capture_provider.dart';

final SingleInstanceService _singleInstanceService = SingleInstanceService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android uses a compact touch-first shell and the same local Drift schema.
  // Keep desktop-only window/tray/single-instance initialization out of the
  // mobile startup path.
  if (Platform.isAndroid) {
    await _runAndroidApp();
    return;
  }

  final instanceResult = await _singleInstanceService.acquire();
  if (instanceResult == SingleInstanceResult.alreadyRunning) {
    exit(0);
  }

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      _logGlobalError(details.exception, details.stack ?? StackTrace.current),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_logGlobalError(error, stack));
    return true;
  };

  AppDatabase? db;
  ProviderContainer? container;
  WindowService? windowService;
  NotificationService? notificationService;

  try {
    await windowManager.ensureInitialized();

    db = AppDatabase();
    windowService = WindowService();
    notificationService = NotificationService(db: db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        windowServiceProvider.overrideWithValue(windowService),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
    );

    windowService.onExit = () => _shutdown(
      db: db!,
      container: container!,
      notificationService: notificationService!,
      windowService: windowService!,
    );

    const options = WindowOptions(
      size: Size(1360, 860),
      center: true,
      title: 'Locus - Planner',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowService!.init();
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);
    _singleInstanceService.onSecondInstance = _revealMainWindow;

    // Open (and migrate) the database before anything optional runs. A broken
    // database must reach the startup error screen below, not be logged and
    // ignored as if it were a notification problem.
    await verifyDatabaseReady(db);

    // Render the database-backed UI before initializing optional integrations.
    // Reminder restoration and tray setup can take noticeable time on Windows;
    // neither should block the first usable frame after the database is ready.
    runApp(
      UncontrolledProviderScope(container: container, child: const LocusApp()),
    );
    _signalSmokeReadyAfterFirstFrame();
    unawaited(
      _initializeOptionalServices(
        container: container,
        notificationService: notificationService,
        windowService: windowService,
        db: db,
      ),
    );
    unawaited(_runAutoBackup(container));
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    _quietly(() => windowService?.dispose());
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {
      // The window manager may not have finished initializing.
    }
    _quietly(() => notificationService?.dispose());
    _quietly(() => container?.dispose());
    // If this throws, the error screen below would never be shown.
    await closeQuietly(db);
    final backupsPath = await _backupsPath();
    runApp(StartupErrorApp(error: error, backupsPath: backupsPath));
  }
}

Future<void> _runAndroidApp() async {
  final db = AppDatabase();
  try {
    await verifyDatabaseReady(db);
    await db.ensureDeviceIdentity();
    // An unpaired phone has no desktop to send its changes to, so its outbox
    // would otherwise grow forever and keep deleted diary text. A paired phone
    // is never cleared here; its outbox holds unsent changes.
    try {
      await MobileSyncClient(db).pruneOutboxIfUnpaired();
    } catch (error, stack) {
      // Housekeeping must not stop the app from starting.
      await _logGlobalError(error, stack);
    }
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => db.close());
            return db;
          }),
        ],
        child: const LocusMobileApp(),
      ),
    );
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    await closeQuietly(db);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Locus could not start',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your local database was not intentionally replaced.',
                      ),
                      const SizedBox(height: 12),
                      SelectableText('$error'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Optional CI handshake: write a marker after the first planner frame has
/// rendered. Startup-error UI intentionally does not emit this marker.
void _signalSmokeReadyAfterFirstFrame() {
  final readyPath = Platform.environment['LOCUS_SMOKE_READY_FILE'];
  if (readyPath == null || readyPath.isEmpty) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      try {
        await File(readyPath).writeAsString('ready');
      } catch (error, stack) {
        await _logGlobalError(error, stack);
      }
    }());
  });
}

Future<void> _initializeOptionalServices({
  required ProviderContainer container,
  required NotificationService notificationService,
  required WindowService windowService,
  required AppDatabase db,
}) async {
  // Every local edit is queued in the outbox even while LAN sync is off. Trim
  // it at startup so it cannot grow without bound, and so deleted diary text
  // does not stay in the database. With no paired phones this clears it; a
  // phone that pairs later starts from a snapshot.
  try {
    await SyncOutboxPruner(db).prune();
  } catch (error, stack) {
    // Housekeeping must not prevent the planner from starting.
    await _logGlobalError(error, stack);
  }

  // Events that arrive from the phone are written straight to the database,
  // so their reminders must be armed (or cancelled) here.
  container.read(lanSyncServerProvider).onChangesApplied = (result) {
    final eventIds = [
      for (final change in result.changes)
        if (change.type == 'event') change.id,
    ];
    if (eventIds.isEmpty) return Future<void>.value();
    return container
        .read(eventRepositoryProvider)
        .rescheduleReminders(eventIds);
  };

  try {
    await notificationService.init();
    await container.read(eventRepositoryProvider).restoreFutureReminders();
  } catch (error, stack) {
    // Notifications are optional; failure must not prevent the planner UI.
    await _logGlobalError(error, stack);
  }

  try {
    await _initSystemTray(
      windowService,
      onExit: () => _shutdown(
        db: db,
        container: container,
        notificationService: notificationService,
        windowService: windowService,
      ),
    );
  } catch (error, stack) {
    // The window must remain usable if the tray integration is unavailable.
    await _logGlobalError(error, stack);
    windowService.trayReady = false;
    windowService.minimizeToTray = false;
  }

  try {
    await container
        .read(quickCaptureServiceProvider)
        .init(
          onTriggered: () async {
            await _revealMainWindow();
            container.read(quickCaptureRequestProvider.notifier).request();
          },
        );
  } catch (error, stack) {
    // The planner is usable without a global hotkey.
    await _logGlobalError(error, stack);
  }
}

Future<void> _runAutoBackup(ProviderContainer container) async {
  try {
    await container.read(autoBackupServiceProvider).runIfDue();
  } catch (error, stack) {
    // Automatic backups run in the background; surface failures through the
    // existing global error log instead of silently dropping them.
    await _logGlobalError(error, stack);
  }
}

/// Runs cleanup that must not be allowed to throw out of the error handler.
void _quietly(void Function() action) {
  try {
    action();
  } catch (_) {}
}

Future<String> _backupsPath() async {
  try {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}backups';
  } catch (_) {
    return 'Application support\\backups';
  }
}

Future<void> _logGlobalError(Object error, StackTrace stack) =>
    ErrorLogService.log(error, stack);

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    required this.error,
    required this.backupsPath,
    super.key,
  });

  final Object error;
  final String backupsPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Locus - Startup Error',
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Locus could not start',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The database or startup services failed to initialize. Your existing data was not intentionally replaced.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText('Error: $error'),
                  const SizedBox(height: 16),
                  const Text('Recovery backups folder:'),
                  SelectableText(backupsPath),
                  const SizedBox(height: 12),
                  const Text(
                    'A detailed error log is stored as locus_error.log in the application support folder.',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await windowManager.setPreventClose(false);
                        await windowManager.destroy();
                      } catch (_) {
                        // There is no recovery action left if the native window
                        // manager itself is unavailable.
                      } finally {
                        await _singleInstanceService.release();
                      }
                    },
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Exit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _initSystemTray(
  WindowService windowService, {
  required Future<void> Function() onExit,
}) async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip('Locus Planner');
  final menu = Menu(
    items: [
      MenuItem(
        key: 'show_window',
        label: 'Show Locus',
        onClick: (menuItem) => _revealMainWindow(),
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit',
        onClick: (menuItem) async {
          try {
            await Future.wait<void>([
              windowService.saveBounds().catchError((Object _) {}),
              onExit(),
            ]);
          } finally {
            try {
              await windowManager.setPreventClose(false);
            } finally {
              await windowManager.destroy();
            }
          }
        },
      ),
    ],
  );
  await trayManager.setContextMenu(menu);
  trayManager.addListener(_TrayListener());
  windowService.trayReady = true;
}

/// Shows the main window whether it is minimized, hidden in the tray, or
/// already visible. Used by the tray icon, the tray menu and second launches.
Future<void> _revealMainWindow() => revealWindow(
  isMinimized: windowManager.isMinimized,
  restore: windowManager.restore,
  show: windowManager.show,
  focus: windowManager.focus,
);

bool _shutdownStarted = false;

Future<void> _shutdown({
  required AppDatabase db,
  required ProviderContainer container,
  required NotificationService notificationService,
  required WindowService windowService,
}) async {
  if (_shutdownStarted) return;
  _shutdownStarted = true;
  windowService.dispose();
  notificationService.dispose();
  try {
    container.read(quickCaptureServiceProvider).dispose();
  } catch (_) {}
  try {
    await container.read(lanSyncServerProvider).stop();
  } catch (_) {}
  container.dispose();
  try {
    await db.close();
  } finally {
    await _singleInstanceService.release();
  }
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    unawaited(_revealMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
