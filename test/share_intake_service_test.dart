import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/features/mobile/data/share_intake_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ShareIntakeService.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('parses ordinals, reason codes and rejection-only content', () async {
    final completed = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takeSharedIntakes') {
        return [
          {
            'id': 'intake-1',
            'title': 'Shared files',
            'text': '',
            'createdAt': 1763711400000,
            'files': [
              {
                'path': '/tmp/a.txt',
                'name': 'a.txt',
                'mimeType': 'text/plain',
                'attachmentId': 'intake-1-0',
                'ordinal': 0,
                'status': 'staged',
              },
            ],
            'rejected': [
              {
                'name': 'huge.mp4',
                'mimeType': 'video/mp4',
                'reason': 'Files larger than 25 MB are not supported',
                'reasonCode': 'too_large',
                'ordinal': 1,
                'retryable': false,
              },
              {
                'name': 'gone.txt',
                'mimeType': 'text/plain',
                'reason': 'The file could not be read',
                'reasonCode': 'unreadable',
                'ordinal': 2,
                'retryable': true,
              },
            ],
          },
        ];
      }
      if (call.method == 'completeIntake') {
        completed.add((call.arguments as Map)['id'] as String);
        return null;
      }
      return null;
    });
    final service = ShareIntakeService();

    final intakes = await service.takeIntakes();
    expect(intakes, hasLength(1));
    final intake = intakes.single;
    expect(intake.id, 'intake-1');
    expect(intake.createdAt, 1763711400000);
    expect(intake.hasContent, isTrue);
    expect(intake.files.single.ordinal, 0);
    expect(intake.files.single.attachmentId, 'intake-1-0');
    expect(intake.rejected, hasLength(2));
    expect(intake.rejected[0].reasonCode, 'too_large');
    expect(intake.rejected[0].ordinal, 1);
    expect(intake.rejected[0].retryable, isFalse);
    expect(intake.rejected[1].reasonCode, 'unreadable');
    expect(intake.rejected[1].retryable, isTrue);

    await service.complete('intake-1');
    expect(completed, ['intake-1']);
    service.dispose();
  });

  test('a rejected-only intake is not considered empty', () {
    const intake = ShareIntake(
      id: 'intake-2',
      title: 'Shared file',
      text: '',
      files: [],
      rejected: [
        RejectedSharedItem(
          name: 'huge.mp4',
          mimeType: 'video/mp4',
          reason: 'Files larger than 25 MB are not supported',
          reasonCode: 'too_large',
        ),
      ],
    );

    expect(intake.isEmpty, isFalse);
    expect(intake.hasContent, isTrue);
  });
}
