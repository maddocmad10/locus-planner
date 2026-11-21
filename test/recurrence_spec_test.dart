import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/recurrence_spec.dart';

void main() {
  test('after-completion advances calendar days and keeps the local time', () {
    final spec = RecurrenceSpec.tryParse(
      RecurrenceSpec.encodeAfterCompletion(10),
    )!;
    final next = spec.nextAfterCompletion(
      DateTime(2026, 12, 2, 9, 30),
      DateTime(2026, 12, 5, 18, 0),
    );
    expect(next, DateTime(2026, 12, 15, 9, 30));
  });

  test('after-completion is bounded to 1..3650 days', () {
    expect(
      () => RecurrenceSpec.encodeAfterCompletion(0),
      throwsFormatException,
    );
    expect(
      () => RecurrenceSpec.encodeAfterCompletion(3651),
      throwsFormatException,
    );
    expect(
      RecurrenceSpec.tryParse('{"v":1,"type":"after_completion","days":0}'),
      isNull,
    );
  });

  test('last Friday preview is 29 January 2027', () {
    final spec = RecurrenceSpec.tryParse(
      RecurrenceSpec.encodeMonthlyWeekday(
        ordinal: -1,
        weekday: DateTime.friday,
      ),
    )!;
    final preview = spec.previewMonthlyWeekday(DateTime(2027, 1, 1));
    expect(preview.first, DateTime(2027, 1, 29));
  });

  test('a missing fifth weekday is skipped', () {
    final spec = RecurrenceSpec.tryParse(
      RecurrenceSpec.encodeMonthlyWeekday(ordinal: 5, weekday: DateTime.monday),
    )!;
    final preview = spec.previewMonthlyWeekday(DateTime(2027, 1, 1), count: 3);
    // January and April 2027 have four Mondays; March has five.
    expect(preview[0], DateTime(2027, 3, 29));
    expect(preview[1], DateTime(2027, 5, 31));
  });

  test('monthly weekday matches the RRULE used for ICS export', () {
    final spec = RecurrenceSpec.tryParse(
      RecurrenceSpec.encodeMonthlyWeekday(
        ordinal: -1,
        weekday: DateTime.friday,
      ),
    )!;
    expect(spec.toRRule(), 'FREQ=MONTHLY;BYDAY=-1FR');
  });

  test('unknown future specs stay readable and are not scheduled', () {
    const raw = '{"v":2,"type":"future_rule"}';
    expect(RecurrenceSpec.tryParse(raw), isNull);
  });

  test('schema 28 exposes recurrence_spec on tasks and events', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final columns = await db
        .customSelect("PRAGMA table_info('todo_items')")
        .get();
    expect(
      columns.map((row) => row.read<String>('name')),
      contains('recurrence_spec'),
    );
    final eventColumns = await db
        .customSelect("PRAGMA table_info('events')")
        .get();
    expect(
      eventColumns.map((row) => row.read<String>('name')),
      contains('recurrence_spec'),
    );
  });
}
