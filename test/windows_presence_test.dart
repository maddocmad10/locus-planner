import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/reminders/windows_toast_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(WindowsToastPlatform.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('setBadge reports the native result', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    expect(await const WindowsToastPlatform().setBadge(4), isTrue);
    expect(calls.single.method, 'setBadge');
    expect(calls.single.arguments, 4);
  });

  test('updateJumpList sends stable ids, titles and URI arguments', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    final result = await const WindowsToastPlatform().updateJumpList([
      {
        'id': 'mini',
        'title': 'Mini Today',
        'arguments': 'locus://mini',
        'description': 'Compact view',
      },
    ]);
    expect(result, isTrue);
    expect(calls.single.method, 'updateJumpList');
    expect(calls.single.arguments, [
      {
        'id': 'mini',
        'title': 'Mini Today',
        'arguments': 'locus://mini',
        'description': 'Compact view',
      },
    ]);
  });

  test('a missing native bridge degrades without throwing', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    expect(await const WindowsToastPlatform().updateJumpList([]), isTrue);
  });

  test('listScheduled reports unknown instead of empty on failure', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'nope'),
    );
    expect(await const WindowsToastPlatform().listScheduled(), isNull);
  });

  test('listScheduled returns the native ids', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => ['ABC', 'DEF']);
    expect(await const WindowsToastPlatform().listScheduled(), ['ABC', 'DEF']);
  });
}
