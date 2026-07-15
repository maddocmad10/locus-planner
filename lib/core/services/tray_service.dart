import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener {
  TrayService._();
  static final instance = TrayService._();

  VoidCallback? onQuickAddEvent;
  VoidCallback? onStartFocus;
  VoidCallback? onShowWindow;

  Future<void> init() async {
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');
    await trayManager.setToolTip('Locus Planner');
    trayManager.addListener(this);
    await _setContextMenu();
  }

  Future<void> _setContextMenu() async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'show', label: 'Show Locus'),
          MenuItem.separator(),
          MenuItem(key: 'add_event', label: 'Quick Add Event'),
          MenuItem(key: 'start_focus', label: 'Start Focus (25 min)'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Exit'),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    onShowWindow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowWindow?.call();
      case 'add_event':
        onQuickAddEvent?.call();
      case 'start_focus':
        onStartFocus?.call();
      case 'exit':
        windowManager.destroy();
    }
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
