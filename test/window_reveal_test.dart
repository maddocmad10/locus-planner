import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/window_reveal.dart';

void main() {
  late List<String> calls;

  setUp(() => calls = []);

  Future<void> reveal({
    required Future<bool> Function() isMinimized,
    Future<void> Function()? restore,
  }) => revealWindow(
    isMinimized: () async {
      calls.add('isMinimized');
      return isMinimized();
    },
    restore: () async {
      calls.add('restore');
      await restore?.call();
    },
    show: () async => calls.add('show'),
    focus: () async => calls.add('focus'),
  );

  test('a minimized window is restored, then shown and focused', () async {
    await reveal(isMinimized: () async => true);
    expect(calls, ['isMinimized', 'restore', 'show', 'focus']);
  });

  test('a window hidden in the tray is just shown and focused', () async {
    await reveal(isMinimized: () async => false);
    expect(calls, ['isMinimized', 'show', 'focus']);
  });

  test('an unreadable minimized state still shows and focuses', () async {
    await reveal(isMinimized: () async => throw StateError('no window'));
    expect(calls, ['isMinimized', 'show', 'focus']);
  });

  test('a failing restore does not stop the window being shown', () async {
    await reveal(
      isMinimized: () async => true,
      restore: () async => throw StateError('restore failed'),
    );
    expect(calls, ['isMinimized', 'restore', 'show', 'focus']);
  });
}
