import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/app_clock.dart';

void main() {
  late DateTime Function() original;
  setUp(() => original = AppClock.now);
  tearDown(() => AppClock.now = original);

  test('the shared clock can be frozen for deterministic tests', () {
    final fixed = DateTime(2026, 10, 19, 23, 59);
    AppClock.now = () => fixed;
    expect(AppClock.now(), fixed);
  });
}
