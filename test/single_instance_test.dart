import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

void main() {
  late Directory tempDirectory;
  late List<SingleInstanceService> services;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('locus-instance-');
    services = [];
  });

  tearDown(() async {
    for (final service in services.reversed) {
      await service.release();
    }
    await tempDirectory.delete(recursive: true);
  });

  SingleInstanceService createService() {
    final service = SingleInstanceService();
    services.add(service);
    return service;
  }

  test('first acquisition succeeds on every platform', () async {
    final service = createService();

    expect(
      await service.acquire(directory: tempDirectory),
      SingleInstanceResult.acquired,
    );
  });

  test('second acquisition signals the existing instance', () async {
    final first = createService();
    final second = createService();
    var activated = false;
    first.onSecondInstance = () async {
      activated = true;
    };

    expect(
      await first.acquire(directory: tempDirectory),
      SingleInstanceResult.acquired,
    );
    expect(
      await second.acquire(directory: tempDirectory),
      SingleInstanceResult.alreadyRunning,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(activated, isTrue);
  });

  test('release allows acquisition again', () async {
    final first = createService();
    final second = createService();

    expect(
      await first.acquire(directory: tempDirectory),
      SingleInstanceResult.acquired,
    );
    await first.release();
    expect(
      await second.acquire(directory: tempDirectory),
      SingleInstanceResult.acquired,
    );
  });

  test(
    'a directory failure is reported as checkFailed, not alreadyRunning',
    () async {
      final service = createService();
      final regularFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}not-a-directory',
      );
      await regularFile.writeAsString('file');

      expect(
        await service.acquire(directory: Directory(regularFile.path)),
        SingleInstanceResult.checkFailed,
      );
    },
  );
}
