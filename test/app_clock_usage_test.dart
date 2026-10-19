import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production code uses AppClock instead of DateTime.now directly', () {
    final libDirectory = Directory('lib');
    expect(
      libDirectory.existsSync(),
      isTrue,
      reason: 'Run this test from the project root.',
    );

    final directClockReference = RegExp(r'\bDateTime\s*\.\s*now\b');
    final violations = <String>[];

    for (final entity in libDirectory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final normalizedPath = entity.path.replaceAll('\\', '/');
      // AppClock is the single intentional adapter to the system clock.
      if (normalizedPath == 'lib/core/utils/app_clock.dart') continue;

      final source = entity.readAsStringSync();
      if (directClockReference.hasMatch(source)) {
        violations.add(normalizedPath);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Use AppClock.now instead of DateTime.now in production code. '
          'Direct references found in: ${violations.join(', ')}',
    );
  });
}
