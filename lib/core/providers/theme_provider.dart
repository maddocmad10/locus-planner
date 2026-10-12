import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'theme_mode';

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
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString(_themeModeKey);
    // The user picked a theme while the disk read was in flight; keep it.
    if (_userChose || _disposed) return;

    if (themeString == null) return;
    state = switch (themeString) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setMode(next);
  }

  Future<void> setMode(ThemeMode mode) async {
    _userChose = true;
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    if (_disposed) return;
    await prefs.setString(_themeModeKey, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
