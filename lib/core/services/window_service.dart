import 'dart:async';

import 'package:flutter/material.dart' show Size, Offset, Rect;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/window_placement.dart';

class WindowService with WindowListener {
  WindowService();

  static const _widthKey = 'window_width';
  static const _heightKey = 'window_height';
  static const _xKey = 'window_x';
  static const _yKey = 'window_y';
  static const _minimizeToTrayKey = 'minimize_to_tray';

  bool minimizeToTray = true;

  /// Called when the window is actually closing (Exit, or close with
  /// minimize-to-tray disabled). Used to flush the database.
  Future<void> Function()? onExit;
  bool _closing = false;

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
      final position = await _safeRestorePosition(
        Offset(x, y),
        Size(width, height),
      );
      await windowManager.setPosition(position);
    }
  }

  Future<Offset> _safeRestorePosition(Offset saved, Size size) async {
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      return restoredWindowPosition(
        saved: saved,
        size: size,
        workAreas: [for (final display in displays) ?_workArea(display)],
        primaryWorkArea: _workArea(primary),
      );
    } catch (_) {
      // Display information only improves the restored position. If it isn't
      // available, opening the window where it was beats failing to start.
      return saved;
    }
  }

  Rect? _workArea(Display display) {
    final position = display.visiblePosition;
    final size = display.visibleSize;
    if (position == null || size == null) return null;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  Timer? _saveBoundsTimer;

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
    await saveBounds();
    final preventClose = await windowManager.isPreventClose();
    if (preventClose && minimizeToTray) {
      await windowManager.hide();
      return;
    }
    if (_closing) return;
    _closing = true;
    if (onExit != null) await onExit!();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  void _scheduleSaveBounds() {
    _saveBoundsTimer?.cancel();
    _saveBoundsTimer = Timer(const Duration(milliseconds: 350), () {
      saveBounds();
    });
  }

  @override
  void onWindowResize() => _scheduleSaveBounds();

  @override
  void onWindowMove() => _scheduleSaveBounds();

  void dispose() {
    _saveBoundsTimer?.cancel();
    _saveBoundsTimer = null;
    windowManager.removeListener(this);
  }
}
