import 'dart:async';

import 'package:flutter/material.dart' show Size, Offset, Rect;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

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
    final savedRect = Rect.fromLTWH(saved.dx, saved.dy, size.width, size.height);
    final displays = await screenRetriever.getAllDisplays();

    // Prefer the display that still contains a meaningful part of the saved
    // window so normal restarts preserve a secondary-monitor layout.
    for (final display in displays) {
      final visiblePosition = display.visiblePosition;
      final visibleSize = display.visibleSize;
      if (visiblePosition == null || visibleSize == null) continue;
      final workArea = Rect.fromLTWH(
        visiblePosition.dx,
        visiblePosition.dy,
        visibleSize.width,
        visibleSize.height,
      );
      final intersection = savedRect.intersect(workArea);
      if (intersection.width >= 120 || intersection.height >= 80) {
        return _clampPosition(saved, size, workArea);
      }
    }

    // A monitor may have been unplugged. Restore to the primary display.
    final primary = await screenRetriever.getPrimaryDisplay();
    final position = primary.visiblePosition;
    final visibleSize = primary.visibleSize;
    if (position == null || visibleSize == null) return saved;
    return _clampPosition(
      saved,
      size,
      Rect.fromLTWH(
        position.dx,
        position.dy,
        visibleSize.width,
        visibleSize.height,
      ),
    );
  }

  Offset _clampPosition(Offset position, Size size, Rect workArea) {
    final maxX = workArea.right - size.width;
    final maxY = workArea.bottom - size.height;
    final x = maxX < workArea.left
        ? workArea.left
        : position.dx.clamp(workArea.left, maxX).toDouble();
    final y = maxY < workArea.top
        ? workArea.top
        : position.dy.clamp(workArea.top, maxY).toDouble();
    return Offset(x, y);
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
