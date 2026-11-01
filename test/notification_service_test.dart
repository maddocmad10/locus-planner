import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/notification_service.dart';

void main() {
  test('re-arms a reminder even when showing the notification fails', () async {
    var rearmed = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {
        throw StateError('notification unavailable');
      },
    );

    await service.scheduleEventReminder(
      eventId: 'event',
      title: 'Event',
      scheduledTime: DateTime.now().subtract(const Duration(seconds: 1)),
      onTriggered: () async {
        rearmed = true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(rearmed, isTrue);
    service.dispose();
  });

  test('does not show a reminder that is more than 15 minutes late', () async {
    var shown = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {
        shown = true;
      },
    );

    await service.scheduleEventReminder(
      eventId: 'late',
      title: 'Late',
      scheduledTime: DateTime.now().subtract(const Duration(minutes: 16)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(shown, isFalse);
    service.dispose();
  });

  test('hands a skipped late reminder to the missed-reminder inbox', () async {
    var skipped = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {},
    );

    await service.scheduleEventReminder(
      eventId: 'late',
      title: 'Late',
      scheduledTime: DateTime.now().subtract(const Duration(minutes: 16)),
      onSkippedLate: () async {
        skipped = true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(skipped, isTrue);
    service.dispose();
  });

  test('does not mark an on-time reminder as missed', () async {
    var skipped = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {},
    );

    await service.scheduleEventReminder(
      eventId: 'on-time',
      title: 'On time',
      scheduledTime: DateTime.now().subtract(const Duration(seconds: 1)),
      onSkippedLate: () async {
        skipped = true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(skipped, isFalse);
    service.dispose();
  });

  test('fires a task reminder at its scheduled time', () async {
    var shownTitle = '';
    var triggered = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {
        shownTitle = title;
      },
    );

    await service.scheduleTaskReminder(
      taskId: 't1',
      title: 'Buy milk',
      scheduledTime: DateTime.now().subtract(const Duration(seconds: 1)),
      onTriggered: () async {
        triggered = true;
      },
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(shownTitle, 'Buy milk');
    expect(triggered, isTrue);
    service.dispose();
  });

  test('cancelling a task reminder stops it firing', () async {
    var shown = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {
        shown = true;
      },
    );

    await service.scheduleTaskReminder(
      taskId: 't1',
      title: 'Later',
      scheduledTime: DateTime.now().add(const Duration(hours: 1)),
    );
    service.cancelTaskReminder('t1');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(shown, isFalse);
    service.dispose();
  });

  test('event and task reminders with the same id are independent', () async {
    var taskShown = false;
    final service = NotificationService(
      showOverride: ({required title, required body}) async {
        if (title == 'Task') taskShown = true;
      },
    );

    await service.scheduleEventReminder(
      eventId: 'same',
      title: 'Event',
      scheduledTime: DateTime.now().add(const Duration(hours: 1)),
    );
    await service.scheduleTaskReminder(
      taskId: 'same',
      title: 'Task',
      scheduledTime: DateTime.now().subtract(const Duration(seconds: 1)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(taskShown, isTrue);
    service.dispose();
  });
}
