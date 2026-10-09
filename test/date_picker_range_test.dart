import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/utils/date_picker_range.dart';

void main() {
  final today = DateTime(2026, 10, 5, 15, 30);

  void expectConsistent(DatePickerRange r) {
    expect(
      r.initial.isBefore(r.first),
      isFalse,
      reason: 'initial < first asserts in showDatePicker',
    );
    expect(
      r.initial.isAfter(r.last),
      isFalse,
      reason: 'initial > last asserts in showDatePicker',
    );
  }

  test('with no current value it starts at today and allows today..2035', () {
    final r = datePickerRange(today: today);
    expect(r.initial, DateTime(2026, 10, 5));
    expect(r.first, DateTime(2026, 10, 5));
    expect(r.last, DateTime(2035, 12, 31));
    expectConsistent(r);
  });

  test(
    'an overdue date (before today) is still selectable and is the start point',
    () {
      final r = datePickerRange(current: DateTime(2026, 9, 1), today: today);
      expect(r.initial, DateTime(2026, 9, 1));
      expect(r.first, DateTime(2026, 9, 1));
      expectConsistent(r);
    },
  );

  test('a date after the default upper bound widens the range', () {
    final r = datePickerRange(current: DateTime(2040, 3, 3), today: today);
    expect(r.initial, DateTime(2040, 3, 3));
    expect(r.last, DateTime(2040, 3, 3));
    expectConsistent(r);
  });

  test('a future date inside the range leaves the bounds alone', () {
    final r = datePickerRange(current: DateTime(2027, 1, 1), today: today);
    expect(r.initial, DateTime(2027, 1, 1));
    expect(r.first, DateTime(2026, 10, 5));
    expect(r.last, DateTime(2035, 12, 31));
    expectConsistent(r);
  });

  test("today's own date is valid whatever the time of day", () {
    final r = datePickerRange(current: DateTime(2026, 10, 5, 8), today: today);
    expect(r.initial, DateTime(2026, 10, 5));
    expect(r.first, DateTime(2026, 10, 5));
    expectConsistent(r);
  });
}
