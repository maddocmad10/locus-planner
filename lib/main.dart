import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'core/services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Initialize notifications
  await NotificationService.instance.init();

  // Initialize System Tray
  await _initSystemTray();

  runApp(const ProviderScope(child: LocusApp()));
}

// ==================== SYSTEM TRAY SETUP ====================
Future<void> _initSystemTray() async {
  await trayManager.setIcon(
    'assets/tray_icon.ico', // We'll create this folder later
  );

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
          await windowManager.destroy();
        },
      ),
    ],
  );

  await trayManager.setContextMenu(menu);

  // Click on tray icon → Show window
  trayManager.addListener(_TrayListener());
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    // Left click on tray icon
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}