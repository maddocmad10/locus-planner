// A refused lock means another instance is running, whether or not that
// instance could be asked to show its window.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

FileLockFunction refusing(int osErrorCode) =>
    (file) async => throw FileSystemException(
      'lock failed',
      'locus.lock',
      OSError('lock held by another process', osErrorCode),
    );

Future<void> eventually(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition was not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('locus_contention_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File portFile() =>
      File('${dir.path}${Platform.pathSeparator}locus.lock.port');

  for (final code in SingleInstanceService.lockHeldErrorCodes) {
    test(
      'refused lock (OS error $code) means another instance, unnotified',
      () async {
        final service = SingleInstanceService(lock: refusing(code));

        final result = await service.acquire(directory: dir);

        expect(result, SingleInstanceResult.alreadyRunning);
        expect(
          portFile().existsSync(),
          isFalse,
          reason: 'there is no activation channel to reach',
        );
        await service.release();
      },
    );
  }

  test('the wait for the courtesy notification stays short', () async {
    final service = SingleInstanceService(lock: refusing(33));
    final stopwatch = Stopwatch()..start();

    await service.acquire(directory: dir);

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    await service.release();
  });

  test('a running instance is still asked to show its window', () async {
    final first = SingleInstanceService();
    addTearDown(first.release);
    var activations = 0;
    first.onSecondInstance = () async => activations++;
    expect(await first.acquire(directory: dir), SingleInstanceResult.acquired);

    // The second launch is refused the lock (injected, so this runs the same on
    // every platform) and must still reach the first instance.
    final second = SingleInstanceService(lock: refusing(33));
    expect(
      await second.acquire(directory: dir),
      SingleInstanceResult.alreadyRunning,
    );

    await eventually(() => activations == 1);
  });

  test('a lock failure that is not "held" is not another instance', () async {
    // ENOSYS: the file system doesn't support locking. Says nothing about
    // other instances, so the planner must be allowed to start.
    final service = SingleInstanceService(lock: refusing(38));

    final result = await service.acquire(directory: dir);

    expect(result, SingleInstanceResult.checkFailed);
    await service.release();
  });

  test('an error without an OS code is inconclusive', () async {
    final service = SingleInstanceService(
      lock: (file) async => throw const FileSystemException('lock failed'),
    );
    expect(
      await service.acquire(directory: dir),
      SingleInstanceResult.checkFailed,
    );
    await service.release();
  });

  test('a non-file error is inconclusive too', () async {
    final service = SingleInstanceService(
      lock: (file) async => throw StateError('unexpected'),
    );
    expect(
      await service.acquire(directory: dir),
      SingleInstanceResult.checkFailed,
    );
    await service.release();
  });

  test('only lock-held error codes are recognised', () {
    bool held(int code) => SingleInstanceService.isLockHeldError(
      FileSystemException('x', 'y', OSError('z', code)),
    );
    expect(held(33), isTrue);
    expect(held(11), isTrue);
    expect(held(38), isFalse);
    expect(held(2), isFalse);
    expect(
      SingleInstanceService.isLockHeldError(const FileSystemException('x')),
      isFalse,
    );
    expect(SingleInstanceService.isLockHeldError(StateError('x')), isFalse);
  });

  test(
    'a real second lock is refused even without an activation channel',
    () async {
      final first = SingleInstanceService();
      addTearDown(first.release);
      expect(
        await first.acquire(directory: dir),
        SingleInstanceResult.acquired,
      );
      portFile().deleteSync(); // as if the first could not open its channel

      final second = SingleInstanceService();
      expect(
        await second.acquire(directory: dir),
        SingleInstanceResult.alreadyRunning,
      );
    },
    // POSIX file locks belong to the process, so a second lock taken from the
    // same process succeeds there. Windows locks belong to the handle.
    skip: Platform.isWindows ? false : 'POSIX file locks are per process',
  );
}
