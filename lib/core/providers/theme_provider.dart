import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/app_database.dart';
import 'database_provider.dart';

const _themeModeKey = AppDatabase.themeModeSettingKey;

class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// Set when the user picks a theme explicitly. The initial disk read is
  /// async: whatever it finds must never overwrite a choice made while it
  /// was in flight (slow first launch, or a quick tap on the radio button).
  bool _userChose = false;

  bool _disposed = false;

  @override
  ThemeMode build() {
    ref.onDispose(() => _disposed = true);
    _loadTheme();
    return ThemeMode.system;
  }

  Future<void> _loadTheme() async {
    final themeString = await _readTheme(migrateLegacy: true);
    // The user picked a theme while the disk read was in flight; keep it.
    if (_userChose || _disposed) return;

    if (themeString == null) return;
    state = _decode(themeString);
  }

  /// Applies the theme stored in the database after an import.
  Future<void> reload() async {
    final themeString = await _readTheme(migrateLegacy: false);
    if (_disposed) return;
    _userChose = true;
    state = _decode(themeString);
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setMode(next);
  }

  Future<void> setMode(ThemeMode mode) async {
    _userChose = true;
    state = mode;
    await _writeTheme(_encode(mode));
  }

  ThemeMode _decode(String? themeString) {
    return switch (themeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _encode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  Future<String?> _readTheme({required bool migrateLegacy}) async {
    try {
      final db = ref.read(databaseProvider);
      final stored = await db.getSetting(_themeModeKey);
      if (stored != null) return stored;
      if (!migrateLegacy || _userChose || _disposed) return null;
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(_themeModeKey);
      if (legacy != null && !_userChose && !_disposed) {
        await db.setSetting(_themeModeKey, legacy);
      }
      return legacy;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(_themeModeKey);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> _writeTheme(String value) async {
    if (_disposed) return;
    try {
      await ref.read(databaseProvider).setSetting(_themeModeKey, value);
      return;
    } catch (_) {
      // Tests without a database override still persist through the legacy store.
    }
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, value);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
