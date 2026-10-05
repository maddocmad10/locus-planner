import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    debugPrint('Flutter framework error: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled application error: $error\n$stack');
    return true;
  };

  // Initialize window manager and restore the last size/position.
  await windowManager.ensureInitialized();
  WindowService.instance.onExit = _shutdown;

  WindowOptions options = const WindowOptions(
    size: Size(1360, 860),
    center: true,
    title: 'Locus - Planner',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    // Apply saved bounds after the default options, so a previous session wins.
    await WindowService.instance.init();
    await windowManager.show();
    await windowManager.focus();
  });

  // Prevent the window from closing when the user clicks the X button.
  // WindowService hides it (and saves bounds) unless Exit was chosen.
  await windowManager.setPreventClose(true);

  // Open the database and initialize notification state before the first
  // frame so persisted reminders are restored even if the Events page has
  // never been opened in this session.
  _db = AppDatabase();
  await NotificationService.instance.init();
  await EventRepository(_db!).restoreFutureReminders();

  // Initialize System Tray
  await _initSystemTray();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(_db!)],
      child: const LocusApp(),
    ),
  );
}

// ==================== SYSTEM TRAY + MINIMIZE TO TRAY ====================

Future<void> _initSystemTray() async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip('Locus Planner');

  // Right-click menu
  Menu menu = Menu(
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
          await WindowService.instance.saveBounds();
          await _shutdown();
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
        },
      ),
    ],
  );

  await trayManager.setContextMenu(menu);

  // Listen to tray clicks. Window close/resize is handled by WindowService.
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
    // Left click on tray icon → show window
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}

