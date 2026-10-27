//import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
import 'package:locus_planner/core/services/sync_discovery.dart';

import 'helpers/test_tls_identity.dart';

void main() {
  final loopback = [InternetAddress.loopbackIPv4];
  const quick = Duration(milliseconds: 800);

  group('SyncDiscoveryResponder', () {
    late SyncDiscoveryResponder responder;

    setUp(() async {
      responder = SyncDiscoveryResponder(
        fingerprint: testTlsFingerprint,
        syncPort: 43821,
        port: 0,
      );
      expect(await responder.start(), isTrue);
    });

    tearDown(() => responder.stop());

    test('answers a phone that knows its fingerprint', () async {
      final found = await discoverDesktop(
        fingerprint: testTlsFingerprint,
        port: responder.boundPort!,
        targets: loopback,
        timeout: quick,
      );

      expect(found, (host: '127.0.0.1', port: 43821));
    });

    test('accepts the fingerprint in any notation', () async {
      final spaced = testTlsFingerprint.toUpperCase().replaceAllMapped(
        RegExp(r'..'),
        (m) => '${m[0]}:',
      );

      final found = await discoverDesktop(
        fingerprint: spaced,
        port: responder.boundPort!,
        targets: loopback,
        timeout: quick,
      );

      expect(found?.port, 43821);
    });

    test('is ignored by a phone expecting another certificate', () async {
      final found = await discoverDesktop(
        fingerprint: '0' * 64,
        port: responder.boundPort!,
        targets: loopback,
        timeout: const Duration(milliseconds: 400),
      );

      expect(found, isNull);
    });

    test('a malformed fingerprint finds nothing without any traffic', () async {
      expect(
        await discoverDesktop(
          fingerprint: 'abcd',
          port: responder.boundPort!,
          targets: loopback,
          timeout: const Duration(milliseconds: 400),
        ),
        isNull,
      );
    });

    test('does not answer anything but a discovery request', () async {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      addTearDown(socket.close);
      final replies = <Datagram>[];
      socket.listen((event) {
        final datagram = socket.receive();
        if (event == RawSocketEvent.read && datagram != null) {
          replies.add(datagram);
        }
      });

      socket.send(
        utf8.encode('GET / HTTP/1.1'),
        InternetAddress.loopbackIPv4,
        responder.boundPort!,
      );
      socket.send(
        List<int>.filled(200, 65),
        InternetAddress.loopbackIPv4,
        responder.boundPort!,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(replies, isEmpty);
    });

    test('stops answering once stopped', () async {
      final port = responder.boundPort!;
      responder.stop();

      expect(responder.boundPort, isNull);
      final found = await discoverDesktop(
        fingerprint: testTlsFingerprint,
        port: port,
        targets: loopback,
        timeout: const Duration(milliseconds: 400),
      );
      expect(found, isNull);
    });

    test('does not fail when its port is already taken', () async {
      final taken = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: false,
      );
      addTearDown(taken.close);

      final second = SyncDiscoveryResponder(
        fingerprint: testTlsFingerprint,
        syncPort: 43821,
        port: taken.port,
      );

      expect(await second.start(), isFalse);
      expect(second.boundPort, isNull);
    });
  });

  group('LanSyncServer discovery', () {
    late AppDatabase database;

    setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => database.close());

    test('advertises the HTTPS port and certificate it serves', () async {
      final server = LanSyncServer(
        database,
        listenPort: 0,
        discoveryPort: 0,
        identityLoader: () async => testTlsIdentity,
      );
      await server.start();
      addTearDown(server.stop);

      final found = await discoverDesktop(
        fingerprint: server.fingerprint!,
        port: server.boundDiscoveryPort!,
        targets: loopback,
        timeout: quick,
      );

      expect(found, (host: '127.0.0.1', port: server.boundPort!));
    });

    test('goes quiet when the server stops', () async {
      final server = LanSyncServer(
        database,
        listenPort: 0,
        discoveryPort: 0,
        identityLoader: () async => testTlsIdentity,
      );
      await server.start();
      expect(server.boundDiscoveryPort, isNotNull);

      await server.stop();

      expect(server.boundDiscoveryPort, isNull);
    });

    test('can be turned off', () async {
      final server = LanSyncServer(
        database,
        listenPort: 0,
        discoveryPort: null,
        identityLoader: () async => testTlsIdentity,
      );
      await server.start();
      addTearDown(server.stop);

      expect(server.isRunning, isTrue);
      expect(server.boundDiscoveryPort, isNull);
    });

    test('a busy discovery port does not stop sync from starting', () async {
      final taken = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: false,
      );
      addTearDown(taken.close);
      final server = LanSyncServer(
        database,
        listenPort: 0,
        discoveryPort: taken.port,
        identityLoader: () async => testTlsIdentity,
      );

      await server.start();
      addTearDown(server.stop);

      expect(server.isRunning, isTrue);
      expect(server.boundDiscoveryPort, isNull);
    });
  });
}
