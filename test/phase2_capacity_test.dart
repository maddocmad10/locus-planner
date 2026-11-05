import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/planning/capacity_service.dart';

BookedInterval block(String task, int startHour, int minutes, {int day = 20}) {
  final start = DateTime(2026, 5, day, startHour);
  return BookedInterval(
    taskKey: task,
    start: start,
    end: start.add(Duration(minutes: minutes)),
  );
}

void main() {
  final day = DateTime(2026, 5, 20);

  test('subtracts breaks, busy events, buffer and planned blocks', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        breaks: const [ClockWindow(12 * 60, 13 * 60)],
        busyEvents: [
          (start: DateTime(2026, 5, 20, 10), end: DateTime(2026, 5, 20, 11)),
        ],
        blocks: [block('todo:a', 9, 100), block('todo:b', 13, 40)],
        bufferMinutes: 10,
      ),
    );

    expect(summary.workingMinutes, 480);
    expect(summary.breakMinutes, 60);
    expect(summary.busyMinutes, 60);
    expect(summary.bufferMinutes, 20);
    expect(summary.availableMinutes, 340);
    expect(summary.bookedMinutes, 140);
    expect(summary.plannedMinutes, 140);
    expect(summary.remainingMinutes, 200);
    expect(summary.overcommittedBy, 0);
    expect(summary.isOvercommitted, isFalse);
    expect(summary.taskMinutes, {'todo:a': 100, 'todo:b': 40});
  });

  test('counts a task once: a block wins over its My Day estimate', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        blocks: [block('todo:blocked', 9, 60)],
        plannedMinutesByTask: {'todo:blocked': 300, 'todo:estimate': 30},
      ),
    );

    expect(summary.bookedMinutes, 60);
    expect(summary.plannedMinutes, 90);
    expect(summary.taskMinutes, {'todo:blocked': 60, 'todo:estimate': 30});
    expect(
      summary.reasons.map((reason) => reason.reason),
      contains(CapacityReason.myDayEstimateFallback),
    );
  });

  test('adds My Day estimates without double counting blocks', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        blocks: [block('todo:a', 9, 30)],
        plannedMinutesByTask: {'todo:a': 30, 'todo:b': 20},
      ),
    );

    expect(summary.taskMinutes, {'todo:a': 30, 'todo:b': 20});
    expect(summary.plannedMinutes, 50);
  });

  test('overlapping blocks are each real planned work', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        blocks: [block('todo:a', 9, 60), block('todo:a', 9, 30)],
        bufferMinutes: 0,
      ),
    );

    expect(summary.bookedMinutes, 90);
    expect(summary.taskMinutes, {'todo:a': 90});
    expect(summary.availableMinutes, 480);
    expect(summary.remainingMinutes, 390);
  });

  test('clips blocks that cross the day boundary', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        blocks: [
          BookedInterval(
            taskKey: 'todo:late',
            start: DateTime(2026, 5, 19, 23),
            end: DateTime(2026, 5, 20, 0, 30),
          ),
          BookedInterval(
            taskKey: 'todo:early',
            start: DateTime(2026, 5, 20, 8),
            end: DateTime(2026, 5, 20, 9, 30),
          ),
        ],
      ),
    );

    expect(summary.bookedMinutes, 120);
  });

  test('reports missing working hours and overcommitment', () {
    final summary = CapacityService.summarize(
      CapacityInput(day: day, blocks: [block('todo:a', 9, 60)]),
    );

    expect(summary.availableMinutes, 0);
    expect(summary.isOvercommitted, isTrue);
    expect(summary.overcommittedBy, 60);
    expect(
      summary.reasons.map((reason) => reason.reason),
      containsAll([
        CapacityReason.noWorkingHours,
        CapacityReason.overcommitted,
      ]),
    );
  });

  test('applies the configured overcommit threshold', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        // 400 of 480 minutes is above 80% but not over 100%.
        blocks: [block('todo:a', 9, 400)],
        overcommitThresholdPercent: 80,
      ),
    );

    expect(summary.isOvercommitted, isFalse);
    expect(summary.remainingMinutes, 80);
    expect(summary.reasons.single.reason, CapacityReason.overcommitted);
    expect(summary.reasons.single.message, contains('80% threshold'));
  });

  test('reports the transition buffer once per block', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [ClockWindow(9 * 60, 17 * 60)],
        blocks: [block('todo:a', 9, 30), block('todo:b', 10, 30)],
        bufferMinutes: 15,
      ),
    );

    expect(summary.bufferMinutes, 30);
    expect(summary.availableMinutes, 450);
    expect(
      summary.reasons.map((reason) => reason.reason),
      contains(CapacityReason.bufferApplied),
    );
  });

  test('ignores disabled and invalid windows', () {
    final summary = CapacityService.summarize(
      CapacityInput(
        day: day,
        workingHours: const [
          ClockWindow(9 * 60, 17 * 60),
          ClockWindow(10 * 60, 10 * 60),
        ],
      ),
    );

    expect(summary.workingMinutes, 480);
  });

  test('utilization is infinite when capacity has run out', () {
    final summary = CapacityService.summarize(
      CapacityInput(day: day, blocks: [block('todo:a', 9, 60)]),
    );
    expect(summary.utilization, double.infinity);

    final empty = CapacityService.summarize(CapacityInput(day: day));
    expect(empty.utilization, 0);
  });
}
