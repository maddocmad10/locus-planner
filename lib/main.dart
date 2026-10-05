import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/services/notification_service.dart';
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

  // Initialize window manager
  await windowManager.ensureInitialized();

  WindowOptions options = const WindowOptions(
    size: Size(1360, 860),
    center: true,
    title: 'Locus - Planner',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // Prevent the window from closing when the user clicks the X button
  await windowManager.setPreventClose(true);

  // Open the database and initialize notification state before the first
  // frame so persisted reminders are restored even if the Events page has
  // never been opened in this session.
  final db = AppDatabase();
  await NotificationService.instance.init();
  await EventRepository(db).restoreFutureReminders();

  // Initialize System Tray
  await _initSystemTray();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
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
          // Allow the app to close for real
          await windowManager.setPreventClose(false);
          await windowManager.destroy();
        },
      ),
    ],
  );

  await trayManager.setContextMenu(menu);

  // Listen to tray clicks
  trayManager.addListener(_TrayListener());

  // Listen to window events (important for minimize-to-tray)
  windowManager.addListener(_WindowListener());
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

class _WindowListener with WindowListener {
  @override
  void onWindowClose() async {
    // When user clicks the X button → hide instead of close
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await windowManager.hide();
    }
  }

  @override
  void onWindowMinimize() async {
    // Optional: also hide when minimized
    // await windowManager.hide();
  }
}