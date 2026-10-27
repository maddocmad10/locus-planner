import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_tls.dart';

import 'helpers/test_tls_identity.dart';

void main() {
  group('fingerprints', () {
    test('the fingerprint is the SHA-256 of the DER certificate', () {
      expect(testTlsIdentity.fingerprint, testTlsFingerprint);
    });

    test('normalizeFingerprint accepts common notations only', () {
      final spaced = testTlsFingerprint.toUpperCase().replaceAllMapped(
        RegExp(r'..'),
        (m) => '${m[0]}:',
      );
      expect(normalizeFingerprint(spaced), testTlsFingerprint);
      expect(
        normalizeFingerprint(' $testTlsFingerprint\n'),
        testTlsFingerprint,
      );
      expect(normalizeFingerprint('abcd'), isNull);
      expect(normalizeFingerprint('z' * 64), isNull);
    });

    test('shortSyncFingerprint groups the first 96 bits', () {
      expect(
        shortSyncFingerprint(testTlsFingerprint),
        'CE08 0BB6 AE3E 1BDD 2DF3 0863',
      );
    });
  });

  group('SyncPairingPayload', () {
    const payload = SyncPairingPayload(
      host: '192.168.1.20',
      port: 43821,
      code: 'A1B2C3D4',
      fingerprint: testTlsFingerprint,
    );

    test('round-trips through its URI', () {
      final parsed = SyncPairingPayload.tryParse(payload.toUri().toString());
      expect(parsed, isNotNull);
      expect(parsed!.host, '192.168.1.20');
      expect(parsed.port, 43821);
      expect(parsed.code, 'A1B2C3D4');
      expect(parsed.fingerprint, testTlsFingerprint);
    });

    test('rejects anything that is not a well-formed pairing code', () {
      expect(SyncPairingPayload.tryParse('https://example.com'), isNull);
      expect(SyncPairingPayload.tryParse('locus://other?h=1.2.3.4'), isNull);
      expect(SyncPairingPayload.tryParse('not a uri at all'), isNull);
      final uri = payload.toUri();
      for (final changed in [
        {'f': 'abcd'},
        {'p': '0'},
        {'p': '70000'},
        {'h': 'bad host'},
        {'c': ''},
      ]) {
        final query = {...uri.queryParameters, ...changed};
        final changedUri = uri.replace(queryParameters: query);
        expect(
          SyncPairingPayload.tryParse(changedUri.toString()),
          isNull,
          reason: '$changed should be rejected',
        );
      }
    });
  });

  group('pinned connections', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        testTlsIdentity.toSecurityContext(),
      );
      server.listen((request) async {
        request.response.write('ok');
        await request.response.close();
      }, onError: (Object _) {});
    });

    tearDown(() => server.close(force: true));

    test('the pinned certificate is accepted', () async {
      final client = pinnedSyncHttpClient(testTlsFingerprint);
      addTearDown(() => client.close(force: true));
      final request = await client.getUrl(
        Uri.parse('https://127.0.0.1:${server.port}/'),
      );
      final response = await request.close();
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    });

    test('any other certificate is rejected', () async {
      final client = pinnedSyncHttpClient('0' * 64);
      addTearDown(() => client.close(force: true));
      await expectLater(
        client.getUrl(Uri.parse('https://127.0.0.1:${server.port}/')),
        throwsA(isA<TlsException>()),
      );
    });

    test('fetchSyncFingerprint returns the served fingerprint', () async {
      await expectLater(
        fetchSyncFingerprint('127.0.0.1', server.port),
        completion(testTlsFingerprint),
      );
    });
  });

  test('localLanAddresses only returns private IPv4 addresses', () async {
    final private = RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)');
    for (final address in await localLanAddresses()) {
      expect(address, matches(private));
    }
  });

  group('SyncTlsIdentity.loadOrCreate', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('keeps its key out of backups', () {
      expect(
        AppDatabase.isTransientSetting(
          AppDatabase.syncTlsCertificateSettingKey,
        ),
        isTrue,
      );
      expect(
        AppDatabase.isTransientSetting(AppDatabase.syncTlsPrivateKeySettingKey),
        isTrue,
      );
    });

    test('creates a usable identity once and then reuses it', () async {
      final first = await SyncTlsIdentity.loadOrCreate(db);
      expect(first.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(first.toSecurityContext, returnsNormally);

      final second = await SyncTlsIdentity.loadOrCreate(db);
      expect(second.fingerprint, first.fingerprint);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('replaces a damaged stored identity', () async {
      await db.setSetting(AppDatabase.syncTlsCertificateSettingKey, 'garbage');
      await db.setSetting(AppDatabase.syncTlsPrivateKeySettingKey, 'garbage');

      final identity = await SyncTlsIdentity.loadOrCreate(db);

      expect(identity.toSecurityContext, returnsNormally);
      expect(
        await db.getSetting(AppDatabase.syncTlsCertificateSettingKey),
        identity.certificatePem,
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
