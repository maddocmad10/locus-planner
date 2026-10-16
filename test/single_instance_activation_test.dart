// The "show your window" channel: authenticated, bounded and time-limited.
import 'dart:async';
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

Future<void> settle() {
  return Future<void>.delayed(const Duration(milliseconds: 250));
}

void main() {
  late Directory dir;
  final services = <SingleInstanceService>[];

  setUp(() => dir = Directory.systemTemp.createTempSync('locus_activation_'));
  tearDown(() async {
    for (final s in services) {
      await s.release();
    }
    services.clear();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<SingleInstanceService> start({
    Directory? at,
    Duration timeout = const Duration(seconds: 2),
    Future<void> Function()? onActivated,
  }) async {
    final service = SingleInstanceService(activationReadTimeout: timeout);
    services.add(service);
    if (onActivated != null) service.onSecondInstance = onActivated;
    final result = await service.acquire(directory: at ?? dir);
    expect(result, SingleInstanceResult.acquired);
    return service;
  }

  Future<({int port, String token})> endpoint([Directory? at]) async {
    final file = File(
      '${(at ?? dir).path}${Platform.pathSeparator}locus.lock.port',
    );
    final lines = (await file.readAsString()).trim().split('\n');
    return (port: int.parse(lines[0]), token: lines[1]);
  }

  Future<void> send(int port, String text) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    socket.write(text);
    await socket.flush();
    await socket.close();
  }

  test('the endpoint file holds the port and a random token', () async {
    await start();
    final e = await endpoint();
    expect(e.port, greaterThan(0));
    expect(e.token, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('each instance gets its own token', () async {
    final otherDir = Directory.systemTemp.createTempSync('locus_activation_b_');
    addTearDown(() {
      try {
        otherDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    await start();
    await start(at: otherDir);
    expect((await endpoint()).token, isNot((await endpoint(otherDir)).token));
  });

  test('a request with the right token activates', () async {
    var activations = 0;
    await start(onActivated: () async => activations++);
    final e = await endpoint();

    await send(e.port, 'activate ${e.token}');

    await eventually(() => activations == 1);
  });

  test('requests without the right token are ignored', () async {
    var activations = 0;
    await start(onActivated: () async => activations++);
    final e = await endpoint();

    await send(e.port, 'activate');
    await send(e.port, 'activate ${'0' * 32}');
    await send(e.port, 'activate ${e.token} extra');
    await send(e.port, 'show ${e.token}');
    await send(e.port, 'GET / HTTP/1.1\r\nHost: localhost\r\n\r\n');
    await settle();

    expect(activations, 0);
  });

  test('an oversized request is dropped even if otherwise valid', () async {
    var activations = 0;
    await start(onActivated: () async => activations++);
    final e = await endpoint();

    // Valid once trimmed, but far longer than any real request.
    final padding = ' ' * (SingleInstanceService.maxActivationBytes * 4);
    try {
      await send(e.port, 'activate ${e.token}$padding');
    } on SocketException {
      // The server may hang up while the client is still writing; fine.
    }
    await settle();

    expect(activations, 0);

    // The listener is still healthy afterwards.
    await send(e.port, 'activate ${e.token}');
    await eventually(() => activations == 1);
  });

  test('a client that connects and sends nothing is disconnected', () async {
    await start(timeout: const Duration(milliseconds: 100));
    final e = await endpoint();

    final socket = await Socket.connect(InternetAddress.loopbackIPv4, e.port);
    final closed = Completer<void>();
    socket.listen(
      (_) {},
      onDone: closed.complete,
      onError: (Object _) => closed.complete(),
      cancelOnError: true,
    );

    await closed.future.timeout(const Duration(seconds: 2));
    socket.destroy();
  });

  test('a request made before the callback is set is delivered', () async {
    final service = await start();
    final e = await endpoint();

    await send(e.port, 'activate ${e.token}');
    await settle();

    var activations = 0;
    service.onSecondInstance = () async => activations++;

    await eventually(() => activations == 1);
    await settle();
    expect(activations, 1, reason: 'delivered once, not repeatedly');
  });

  test('a failing callback does not break later activations', () async {
    var calls = 0;
    await start(
      onActivated: () async {
        calls++;
        throw StateError('window plugin unavailable');
      },
    );
    final e = await endpoint();

    await send(e.port, 'activate ${e.token}');
    await eventually(() => calls == 1);
    await send(e.port, 'activate ${e.token}');
    await eventually(() => calls == 2);
  });

  test('the endpoint disappears on release', () async {
    final service = await start();
    final e = await endpoint();

    await service.release();

    expect(
      File('${dir.path}${Platform.pathSeparator}locus.lock.port').existsSync(),
      isFalse,
    );
    await expectLater(
      Socket.connect(
        InternetAddress.loopbackIPv4,
        e.port,
        timeout: const Duration(milliseconds: 300),
      ),
      throwsA(isA<SocketException>()),
    );
  });
}
