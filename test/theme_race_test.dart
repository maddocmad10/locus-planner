// The persisted theme must not overwrite a choice the user makes while the
// initial disk read is still in flight (slow first launch / quick tap).
// Theme mode lives in app_settings. SharedPreferences is only the legacy
// source migrated on first read.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/core/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('a choice made before the disk read lands wins', () async {
    SharedPreferences.setMockInitialValues({
      AppDatabase.themeModeSettingKey: 'dark',
    });
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    // build() schedules the async load; pick a theme before it resolves.
    expect(container.read(themeModeProvider), ThemeMode.system);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

    // Give the pending disk read every chance to (wrongly) overwrite.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(await db.getSetting(AppDatabase.themeModeSettingKey), 'light');
  });

  test(
    'a legacy preference is migrated when the database has no theme',
    () async {
      SharedPreferences.setMockInitialValues({
        AppDatabase.themeModeSettingKey: 'dark',
      });
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(await db.getSetting(AppDatabase.themeModeSettingKey), 'dark');
    },
  );

  test('reload applies a theme written by import', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await db.setSetting(AppDatabase.themeModeSettingKey, 'dark');
    await container.read(themeModeProvider.notifier).reload();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
