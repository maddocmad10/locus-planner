import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'error_log_service.dart';

typedef QuickCaptureRegister =
    Future<void> Function(Future<void> Function() onTriggered);
typedef QuickCaptureUnregister = Future<void> Function();

/// Registers a system-wide hotkey that opens the quick-capture dialog.
/// Registration and persistence are kept consistent when either operation
/// fails. The callbacks are injectable so lifecycle/error paths can be tested.
class QuickCaptureService {
  QuickCaptureService({
    QuickCaptureRegister? register,
    QuickCaptureUnregister? unregister,
    SharedPreferences? preferences,
  }) : _registerOverride = register,
       _unregisterOverride = unregister,
       _preferences = preferences;

  static const preferenceKey = 'quick_capture_enabled';
  static const defaultAccelerator = 'Ctrl+Shift+L';

  final QuickCaptureRegister? _registerOverride;
  final QuickCaptureUnregister? _unregisterOverride;
  final SharedPreferences? _preferences;
  SharedPreferences? _loadedPreferences;
  Future<void> Function()? _onTriggered;
  bool _enabled = false;
  bool _registered = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  HotKey? _systemHotKey;

  bool get enabled => _enabled;
  String get accelerator => defaultAccelerator;

  Future<SharedPreferences> get _prefs async {
    final injected = _preferences;
    if (injected != null) return injected;
    final loaded = _loadedPreferences;
    if (loaded != null) return loaded;
    final prefs = await SharedPreferences.getInstance();
    _loadedPreferences = prefs;
    return prefs;
  }

  Future<void> init({required Future<void> Function() onTriggered}) async {
    if (_disposed) throw StateError('QuickCaptureService is disposed');
    _onTriggered = onTriggered;
    final prefs = await _prefs;
    final shouldEnable = prefs.getBool(preferenceKey) ?? true;
    if (!shouldEnable) {
      _enabled = false;
      return;
    }
    try {
      await _register();
      _enabled = true;
    } catch (_) {
      _enabled = false;
      await prefs.setBool(preferenceKey, false);
      rethrow;
    }
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed) throw StateError('QuickCaptureService is disposed');
    if (_enabled == value && (!value || _registered)) return;
    final prefs = await _prefs;
    if (!value) {
      // If unregister fails, retain the old enabled preference/state.
      await _unregister();
      await prefs.setBool(preferenceKey, false);
      _enabled = false;
      return;
    }

    // Do not persist or expose enabled=true until registration succeeds.
    await _register();
    try {
      await prefs.setBool(preferenceKey, true);
      _enabled = true;
    } catch (_) {
      try {
        await _unregister();
      } catch (_) {}
      _enabled = false;
      rethrow;
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _unregister();
    } catch (error, stack) {
      // Shutdown must continue even if the platform plugin cannot unregister.
      await ErrorLogService.log(error, stack);
    } finally {
      _onTriggered = null;
      _enabled = false;
    }
  }

  Future<void> _register() async {
    if (_registered) return;
    final register = _registerOverride;
    await (register ?? _registerSystemHotkey)(() async {
      final callback = _onTriggered;
      if (callback == null || _disposed) return;
      await _runCallbackSafely(callback);
    });
    _registered = true;
  }

  Future<void> _unregister() async {
    if (!_registered) return;
    final unregister = _unregisterOverride;
    await (unregister ?? _unregisterSystemHotkey)();
    _registered = false;
  }

  Future<void> _registerSystemHotkey(
    Future<void> Function() onTriggered,
  ) async {
    final hotKey = HotKey(
      key: PhysicalKeyboardKey.keyL,
      modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
      scope: HotKeyScope.system,
    );
    await hotKeyManager.register(
      hotKey,
      keyDownHandler: (_) => unawaited(onTriggered()),
    );
    _systemHotKey = hotKey;
  }

  Future<void> _unregisterSystemHotkey() async {
    final hotKey = _systemHotKey;
    if (hotKey == null) return;
    await hotKeyManager.unregister(hotKey);
    _systemHotKey = null;
  }

  Future<void> _runCallbackSafely(Future<void> Function() callback) async {
    try {
      await callback();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
    }
  }
}
