import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition was not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

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

  SingleInstanceService createService({FileLockFunction? lock}) {
    final service = SingleInstanceService(lock: lock);
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
    final second = createService(
      lock: (file) async {
        throw FileSystemException(
          'lock held by another process',
          'locus.lock',
          OSError('lock held', 33),
        );
      },
    );
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
    await eventually(() => activated);
  });

  test('release allows acquisition again', () async {
    final first = createService();
    final second = createService(lock: (file) async {});

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
