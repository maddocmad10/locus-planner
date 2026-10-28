import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/features/mobile/data/reminder_planner.dart';
import 'package:locus_planner/features/mobile/data/reminder_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(MethodChannelReminderPlatform.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('replaceAll sends plain maps the Android side can read', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final reminder = PlannedReminder(
      id: 'e1@1',
      eventId: 'e1',
      fireAt: DateTime.fromMillisecondsSinceEpoch(1790000000000),
      title: 'Dentist',
      body: 'Starts in 10 min',
    );

    await MethodChannelReminderPlatform().replaceAll([reminder]);

    expect(calls.single.method, 'replaceAll');
    expect(calls.single.arguments, {
      'reminders': [
        {
          'id': 'e1@1',
          'at': 1790000000000,
          'title': 'Dentist',
          'body': 'Starts in 10 min',
        },
      ],
    });
  });

  test('capabilities reads what Android allows', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'notificationsAllowed': false,
        'exactAlarmsAllowed': true,
      },
    );

    final capabilities = await MethodChannelReminderPlatform().capabilities();

    expect(capabilities.supported, isTrue);
    expect(capabilities.notificationsAllowed, isFalse);
    expect(capabilities.exactAlarmsAllowed, isTrue);
  });

  test('without Android behind it everything is unsupported', () async {
    final platform = MethodChannelReminderPlatform();

    expect((await platform.capabilities()).supported, isFalse);
    expect(await platform.requestNotificationPermission(), isFalse);
    await platform.openExactAlarmSettings();
    await platform.openNotificationSettings();
  });

  test('a failing settings screen is not an error for the caller', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'nope'),
    );
    final platform = MethodChannelReminderPlatform();

    expect((await platform.capabilities()).supported, isFalse);
    expect(await platform.requestNotificationPermission(), isFalse);
    await platform.openExactAlarmSettings();
    await platform.openNotificationSettings();
  });

  test('the permission answer comes back from Android', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => true);

    expect(
      await MethodChannelReminderPlatform().requestNotificationPermission(),
      isTrue,
    );
  });
}
