import 'package:flutter/material.dart' show Size, Offset;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

class WindowService with WindowListener {
  WindowService._();
  static final instance = WindowService._();

  static const _widthKey = 'window_width';
  static const _heightKey = 'window_height';
  static const _xKey = 'window_x';
  static const _yKey = 'window_y';
  static const _minimizeToTrayKey = 'minimize_to_tray';

  bool minimizeToTray = true;

  Future<void> init() async {
    windowManager.addListener(this);
    final prefs = await SharedPreferences.getInstance();
    minimizeToTray = prefs.getBool(_minimizeToTrayKey) ?? true;

    final width = prefs.getDouble(_widthKey) ?? 1360;
    final height = prefs.getDouble(_heightKey) ?? 860;
    final x = prefs.getDouble(_xKey);
    final y = prefs.getDouble(_yKey);

    await windowManager.setMinimumSize(const Size(900, 600));
    await windowManager.setSize(Size(width, height));
    if (x != null && y != null) {
      await windowManager.setPosition(Offset(x, y));
    }
  }

  Future<void> saveBounds() async {
    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_widthKey, bounds.width);
    await prefs.setDouble(_heightKey, bounds.height);
    await prefs.setDouble(_xKey, bounds.left);
    await prefs.setDouble(_yKey, bounds.top);
  }

  Future<void> setMinimizeToTray(bool value) async {
    minimizeToTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_minimizeToTrayKey, value);
  }

  @override
  void onWindowClose() async {
    if (minimizeToTray) {
      await windowManager.hide();
    } else {
      await saveBounds();
      await windowManager.destroy();
    }
  }

  @override
  void onWindowResize() => saveBounds();

  @override
  void onWindowMove() => saveBounds();

  void dispose() {
    windowManager.removeListener(this);
  }
}
