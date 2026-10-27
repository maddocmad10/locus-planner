import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
import 'package:locus_planner/core/utils/diary_merge.dart';
import 'package:locus_planner/features/mobile/data/mobile_sync_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/test_tls_identity.dart';

class _MemoryTokenStore implements SyncTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> delete() async => token = null;
}

/// End-to-end tests: a real [MobileSyncClient] (phone database) talking over
/// loopback HTTP to a real [LanSyncServer] (desktop database).
void main() {
  late AppDatabase desktop;
  late AppDatabase phone;
  late LanSyncServer server;
  late _MemoryTokenStore tokens;
  late MobileSyncClient client;
  late String host;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    desktop = AppDatabase.forTesting(NativeDatabase.memory());
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    await desktop.ensureDeviceIdentity();
    await phone.ensureDeviceIdentity();
    server = LanSyncServer(
      desktop,
      listenPort: 0,
      identityLoader: () async => testTlsIdentity,
    );
    await server.start();
    host = 'https://127.0.0.1:${server.boundPort}';
    tokens = _MemoryTokenStore();
    client = MobileSyncClient(phone, tokenStore: tokens);
  });

  tearDown(() async {
    await server.stop();
    await desktop.close();
    await phone.close();
  });

  Future<void> pair() => client.pair(
    host: host,
    code: server.pairingCode!,
    fingerprint: server.fingerprint!,
  );

  Future<void> insertTodo(AppDatabase db, String id, String title) =>
      db.customStatement(
        'INSERT INTO todo_items (id, title, completed, created_at) '
        'VALUES (?, ?, 0, 1760000000)',
        [id, title],
      );

  Future<void> renameTodo(AppDatabase db, String id, String title) =>
      db.customStatement('UPDATE todo_items SET title = ? WHERE id = ?', [
        title,
        id,
      ]);

  Future<List<String>> titles(AppDatabase db) async {
    final rows = await db
        .customSelect('SELECT title FROM todo_items ORDER BY id')
        .get();
    return [for (final row in rows) row.read<String>('title')];
  }

  Future<int> outboxCount(AppDatabase db) async {
    final row = await db
        .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
        .getSingle();
    return row.read<int>('n');
  }

  test('pairing stores the token and host, and unpair clears them', () async {
    expect((await client.status()).paired, isFalse);

    await pair();
    final status = await client.status();
    expect(status.paired, isTrue);
    expect(status.host, host);
    expect(tokens.token, isNotEmpty);

    await client.unpair();
    expect((await client.status()).paired, isFalse);
    expect(tokens.token, isNull);
  });

  test('a wrong pairing code is rejected', () async {
    await expectLater(
      client.pair(host: host, code: 'WRONG1', fingerprint: server.fingerprint!),
      throwsA(isA<HttpException>()),
    );
    expect((await client.status()).paired, isFalse);
  });

  test('a desktop with another certificate gets no pairing code', () async {
    final code = server.pairingCode!;

    await expectLater(
      client.pair(host: host, code: code, fingerprint: '0' * 64),
      throwsA(isA<SyncCertificateMismatch>()),
    );

    expect((await client.status()).paired, isFalse);
    expect(tokens.token, isNull);
    // The handshake failed before anything was sent, so the code is unused.
    expect(server.pairingCode, code);
  });

  test('a malformed fingerprint is rejected before connecting', () async {
    await expectLater(
      client.pair(host: host, code: server.pairingCode!, fingerprint: 'abcd'),
      throwsFormatException,
    );
  });

  test('manual pairing can read the desktop fingerprint first', () async {
    final fingerprint = await client.fetchDesktopFingerprint(host);

    expect(fingerprint, server.fingerprint);
    expect(server.pairingCode, isNotNull);
    await client.pair(
      host: host,
      code: server.pairingCode!,
      fingerprint: fingerprint,
    );
    expect((await client.status()).paired, isTrue);
  });

  test('an http:// address is upgraded to https', () async {
    await client.pair(
      host: host.replaceFirst('https://', 'http://'),
      code: server.pairingCode!,
      fingerprint: server.fingerprint!,
    );

    expect((await client.status()).host, host);
  });

  test('a pairing from before HTTPS must pair again', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locus.sync.host', 'http://192.168.1.20:43821');
    tokens.token = 'old-plain-http-token';

    final status = await client.status();

    expect(status.paired, isFalse);
    expect(status.needsRepair, isTrue);
    await expectLater(client.syncNow(), throwsStateError);
  });

  test('forgetting a pairing and pairing again works', () async {
    await pair();
    await client.unpair();
    server.regeneratePairingCode();

    await pair();
    await client.syncNow();

    expect((await client.status()).paired, isTrue);
  });

  test('sync stops if the desktop certificate changes', () async {
    await pair();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locus.sync.pin', '0' * 64);

    await expectLater(
      client.syncNow(),
      throwsA(isA<SyncCertificateMismatch>()),
    );
  });

  test('syncing before pairing explains what to do', () async {
    await expectLater(client.syncNow(), throwsStateError);
  });

  test('first sync merges existing data on both devices', () async {
    await insertTodo(desktop, 'd1', 'on desktop');
    await insertTodo(phone, 'p1', 'on phone');
    await pair();

    final message = await client.syncNow();

    expect(message, startsWith('Sync complete'));
    expect(await titles(phone), ['on desktop', 'on phone']);
    expect(await titles(desktop), ['on desktop', 'on phone']);
  });

  test('later edits and deletes flow in both directions', () async {
    await insertTodo(desktop, 'd1', 'desktop one');
    await insertTodo(desktop, 'd2', 'desktop two');
    await pair();
    await client.syncNow();

    await renameTodo(desktop, 'd1', 'desktop one (edited)');
    await insertTodo(phone, 'p1', 'phone new');
    await phone.customStatement("DELETE FROM todo_items WHERE id = 'd2'");
    await client.syncNow();

    const expected = ['desktop one (edited)', 'phone new'];
    expect(await titles(phone), expected);
    expect(await titles(desktop), expected);
  });

  test('concurrent edits converge on the later one', () async {
    await insertTodo(desktop, 'shared', 'original');
    await pair();
    await client.syncNow();

    await renameTodo(desktop, 'shared', 'from desktop');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await renameTodo(phone, 'shared', 'from phone');
    await client.syncNow();

    expect(await titles(desktop), ['from phone']);
    expect(await titles(phone), ['from phone']);
  });

  test('the same diary day on both devices is merged, not lost', () async {
    const insert =
        'INSERT INTO diary_entries (id, date, mood, content) '
        'VALUES (?, 1760000000, 3, ?)';
    await desktop.customStatement(insert, ['z-desktop', 'desktop entry']);
    await phone.customStatement(insert, ['a-phone', 'phone entry']);
    await pair();

    await client.syncNow();
    await client.syncNow();

    final expected = mergeDiaryContent('phone entry', 'desktop entry');
    for (final db in [desktop, phone]) {
      final rows = await db
          .customSelect(
            'SELECT id, content FROM diary_entries WHERE date = 1760000000',
          )
          .get();
      expect(rows.map((row) => row.read<String>('id')), ['a-phone']);
      expect(rows.map((row) => row.read<String>('content')), [expected]);
    }
  });

  test('synced outbox rows are pruned on both devices', () async {
    await insertTodo(phone, 'p1', 'phone');
    await insertTodo(desktop, 'd1', 'desktop');
    await pair();
    await client.syncNow();
    await renameTodo(desktop, 'd1', 'desktop edited');
    await renameTodo(phone, 'p1', 'phone edited');
    await client.syncNow();

    expect(await outboxCount(phone), 0);
    expect(await outboxCount(desktop), 0);
    expect(await desktop.outboxPrunedThrough(), greaterThan(0));
    expect(await titles(phone), ['desktop edited', 'phone edited']);
  });

  test('a reset desktop is repopulated from the phone', () async {
    await insertTodo(phone, 'p1', 'kept on phone');
    await pair();
    await client.syncNow();
    expect(await titles(desktop), ['kept on phone']);

    // Simulate a reinstalled desktop: empty data, outbox restarted, new epoch.
    await desktop.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
    await desktop.customStatement('DELETE FROM todo_items');
    await desktop.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
    await desktop.customStatement('DELETE FROM sync_outbox');
    await desktop.customStatement('DELETE FROM sync_row_versions');
    await desktop.customStatement(
      "DELETE FROM sqlite_sequence WHERE name = 'sync_outbox'",
    );
    await desktop.setSetting(
      AppDatabase.syncOutboxPrunedThroughSettingKey,
      '0',
    );
    await desktop.setSetting(AppDatabase.syncEpochSettingKey, 'new-epoch');
    expect(await titles(desktop), isEmpty);

    final message = await client.syncNow();

    expect(message, contains('re-synced'));
    expect(await titles(desktop), ['kept on phone']);
    expect(await titles(phone), ['kept on phone']);

    // The phone adopted the new epoch, so the next sync is a normal one.
    final next = await client.syncNow();
    expect(next, isNot(contains('re-synced')));
  });

  test('a cursor ahead of the desktop triggers a resync', () async {
    await insertTodo(desktop, 'd1', 'desktop');
    await pair();
    await client.syncNow();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('locus.sync.remote_cursor', 9999);
    await renameTodo(desktop, 'd1', 'edited after');

    final message = await client.syncNow();

    expect(message, contains('re-synced'));
    expect(await titles(phone), ['edited after']);
  });

  test('a revoked phone is told to pair again', () async {
    await pair();
    await client.syncNow();
    final deviceId = await phone.ensureDeviceIdentity();
    await server.revokeDevice(deviceId);

    await expectLater(client.syncNow(), throwsA(isA<HttpException>()));
  });
}
