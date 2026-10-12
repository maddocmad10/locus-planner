// The persisted theme must not overwrite a choice the user makes while the
// initial disk read is still in flight (slow first launch / quick tap).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locus_planner/core/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a choice made before the disk read lands wins', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // build() schedules the async load; pick a theme before it resolves.
    expect(container.read(themeModeProvider), ThemeMode.system);
    await container.read(themeModeProvider.notifier).setMode(ThemeMode.light);

    // Give the pending disk read every chance to (wrongly) overwrite.
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(themeModeProvider), ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('the persisted theme applies when the user has not chosen', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });
}
