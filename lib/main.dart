import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/services/notification_service.dart';
import 'core/services/window_service.dart';
import 'core/db/app_database.dart';
import 'core/providers/database_provider.dart';
import 'features/events/data/event_repository.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_logGlobalError(details.exception, details.stack ?? StackTrace.current));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_logGlobalError(error, stack ?? StackTrace.current));
    return true;
  };

  try {
    await windowManager.ensureInitialized();
    WindowService.instance.onExit = _shutdown;
    const options = WindowOptions(
      size: Size(1360, 860),
      center: true,
      title: 'Locus - Planner',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await WindowService.instance.init();
      await windowManager.show();
      await windowManager.focus();
    });
    await windowManager.setPreventClose(true);

    _db = AppDatabase();
    await NotificationService.instance.init();
    await EventRepository(_db!).restoreFutureReminders();
    await _initSystemTray();

    runApp(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(_db!)],
        child: const LocusApp(),
      ),
    );
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    await _db?.close();
    _db = null;
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

Future<void> _initSystemTray() async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip('Locus Planner');
  final menu = Menu(
    items: [
      MenuItem(key: 'show_window', label: 'Show Locus', onClick: (menuItem) async {
        await windowManager.show();
        await windowManager.focus();
      }),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: 'Exit', onClick: (menuItem) async {
        await WindowService.instance.saveBounds();
        await _shutdown();
        await windowManager.setPreventClose(false);
        await windowManager.destroy();
      }),
    ],
  );
  await trayManager.setContextMenu(menu);
  trayManager.addListener(_TrayListener());
}

AppDatabase? _db;
bool _shuttingDown = false;

Future<void> _shutdown() async {
  if (_shuttingDown) return;
  _shuttingDown = true;
  NotificationService.instance.dispose();
  await _db?.close();
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
