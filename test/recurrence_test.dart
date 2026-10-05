import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/recurrence.dart';

void main() {
  test('daily recurrence finds next occurrence', () {
    final start = DateTime(2026, 10, 5, 9);
    expect(
      Recurrence.next(start, Recurrence.daily, from: DateTime(2026, 10, 5, 10)),
      DateTime(2026, 10, 6, 9),
    );
  });

  test('weekdays skips Saturday and Sunday', () {
    final friday = DateTime(2026, 10, 9, 9);
    expect(
      Recurrence.next(friday, Recurrence.weekdays, from: friday),
      DateTime(2026, 10, 12, 9),
    );
  });

  test('monthly recurrence clamps invalid month days', () {
    final jan31 = DateTime(2026, 1, 31, 9);
    expect(
      Recurrence.next(jan31, Recurrence.monthly, from: jan31),
      DateTime(2026, 2, 28, 9),
    );
  });
}
