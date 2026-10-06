import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app.dart';
import 'core/db/app_database.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/service_providers.dart';
import 'core/services/data_export_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/window_service.dart';
import 'features/events/data/event_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_logGlobalError(details.exception, details.stack ?? StackTrace.current));
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
    notificationService = NotificationService();
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

    await notificationService.init();
    await container.read(eventRepositoryProvider).restoreFutureReminders();
    await _initSystemTray(
      windowService,
      onExit: () => _shutdown(
        db: db!,
        container: container!,
        notificationService: notificationService!,
        windowService: windowService!,
      ),
    );

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const LocusApp(),
      ),
    );
    unawaited(DataExportService(db).createAutomaticBackupIfDue());
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    notificationService?.dispose();
    container?.dispose();
    await db?.close();
    final backupsPath = await _backupsPath();
    runApp(StartupErrorApp(error: error, backupsPath: backupsPath));
  }
}

Future<String> _backupsPath() async {
  try {
    final support = await getApplicationSupportDirectory();
    return '${support.path}${Platform.pathSeparator}backups';
  } catch (_) {
    return 'Application support\\backups';
  }
}

Future<void> _logGlobalError(Object error, StackTrace stack) async {
  try {
    final support = await getApplicationSupportDirectory();
    final logFile = File('${support.path}${Platform.pathSeparator}locus_error.log');
    await logFile.parent.create(recursive: true);
    await logFile.writeAsString(
      '${DateTime.now().toIso8601String()}\n$error\n$stack\n\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // Error reporting must never become another startup failure.
  }
}

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({required this.error, required this.backupsPath, super.key});

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
                  const Text('Locus could not start', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('The database or startup services failed to initialize. Your existing data was not intentionally replaced.'),
                  const SizedBox(height: 16),
                  SelectableText('Error: $error'),
                  const SizedBox(height: 16),
                  const Text('Recovery backups folder:'),
                  SelectableText(backupsPath),
                  const SizedBox(height: 12),
                  const Text('A detailed error log is stored as locus_error.log in the application support folder.'),
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
        onClick: (menuItem) async {
          await windowManager.show();
          await windowManager.focus();
        },
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit',
        onClick: (menuItem) async {
          await windowService.saveBounds();
          await onExit();
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
        },
      ),
    ],
  );
  await trayManager.setContextMenu(menu);
  trayManager.addListener(_TrayListener());
}

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
  container.dispose();
  await db.close();
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
