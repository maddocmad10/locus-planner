import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/window_placement.dart';

void main() {
  const size = Size(1360, 860);
  const primary = Rect.fromLTWH(0, 0, 1920, 1040);
  const right = Rect.fromLTWH(1920, 0, 1920, 1040);
  const left = Rect.fromLTWH(-1920, 0, 1920, 1040);

  test('keeps a window that is on a still-connected secondary monitor', () {
    final p = restoredWindowPosition(
      saved: const Offset(2000, 100),
      size: size,
      workAreas: const [primary, right],
      primaryWorkArea: primary,
    );
    expect(p, const Offset(2000, 100));
  });

  test('moves a window whose monitor was unplugged onto the primary one', () {
    final p = restoredWindowPosition(
      saved: const Offset(2500, 100),
      size: size,
      workAreas: const [primary],
      primaryWorkArea: primary,
    );
    // Clamped so the whole window fits: 1920 - 1360 = 560.
    expect(p, const Offset(560, 100));
  });

  test('pulls a window that hangs off the bottom back inside', () {
    final p = restoredWindowPosition(
      saved: const Offset(100, 900),
      size: size,
      workAreas: const [primary],
    );
    expect(p, const Offset(100, 180)); // 1040 - 860
  });

  test('a sliver of overlap does not count as visible', () {
    final p = restoredWindowPosition(
      saved: const Offset(1880, 100), // only 40px on the primary monitor
      size: size,
      workAreas: const [primary],
      primaryWorkArea: primary,
    );
    expect(p, const Offset(560, 100));
  });

  test(
    'supports monitors to the left of the primary (negative coordinates)',
    () {
      final p = restoredWindowPosition(
        saved: const Offset(-1800, 50),
        size: size,
        workAreas: const [left, primary],
        primaryWorkArea: primary,
      );
      expect(p, const Offset(-1800, 50));
    },
  );

  test(
    'a window larger than the work area is pinned to its top-left corner',
    () {
      final p = restoredWindowPosition(
        saved: const Offset(300, 300),
        size: const Size(2000, 1200),
        workAreas: const [primary],
      );
      expect(p, const Offset(0, 0));
    },
  );

  test('falls back to the first monitor when no primary is given', () {
    final p = restoredWindowPosition(
      saved: const Offset(9000, 9000),
      size: size,
      workAreas: const [right, primary],
    );
    expect(p, const Offset(2480, 180)); // clamped into `right`
  });

  test('without any monitor information the saved position is unchanged', () {
    final p = restoredWindowPosition(
      saved: const Offset(42, 24),
      size: size,
      workAreas: const [],
    );
    expect(p, const Offset(42, 24));
  });
}
