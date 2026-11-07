import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_store.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
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

void main() {
  late AppDatabase desktop;
  late AppDatabase phone;
  late AttachmentStore desktopStore;
  late AttachmentStore phoneStore;
  late Directory desktopRoot;
  late Directory phoneRoot;
  late LanSyncServer server;
  late MobileSyncClient client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    desktop = AppDatabase.forTesting(NativeDatabase.memory());
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    await desktop.ensureDeviceIdentity();
    await phone.ensureDeviceIdentity();

    desktopRoot = await Directory.systemTemp.createTemp('locus-desktop-blobs-');
    phoneRoot = await Directory.systemTemp.createTemp('locus-phone-blobs-');
    desktopStore = AttachmentStore(
      root: desktopRoot,
      crypto: AttachmentCrypto(
        Uint8List.fromList(List.generate(32, (index) => index)),
      ),
    );
    phoneStore = AttachmentStore(
      root: phoneRoot,
      crypto: AttachmentCrypto(
        Uint8List.fromList(List.generate(32, (index) => 255 - index)),
      ),
    );
    await desktopStore.ensureLayout();
    await phoneStore.ensureLayout();

    server = LanSyncServer(
      desktop,
      listenPort: 0,
      discoveryPort: null,
      identityLoader: () async => testTlsIdentity,
      blobStoreLoader: () async => desktopStore,
    );
    await server.start();

    client = MobileSyncClient(
      phone,
      tokenStore: _MemoryTokenStore(),
      storeLoader: () async => phoneStore,
    );
    await client.pair(
      host: '127.0.0.1:${server.boundPort}',
      code: server.pairingCode!,
      fingerprint: testTlsFingerprint,
    );
  });

  tearDown(() async {
    await server.stop();
    await desktop.close();
    await phone.close();
    await desktopRoot.delete(recursive: true);
    await phoneRoot.delete(recursive: true);
  });

  Future<String> attach(
    AppDatabase db,
    AttachmentStore store,
    String todoId,
    String name,
    String text,
  ) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final hash = await store.putBytes(bytes);
    final now = DateTime(2026, 11, 7);
    await db
        .into(db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: 'attachment-$name',
            todoId: Value(todoId),
            kind: 'file',
            displayName: name,
            mimeType: 'text/plain',
            sizeBytes: bytes.length,
            sha256: hash,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return hash;
  }

  test('phone and desktop exchange metadata and blobs', () async {
    final desktopTodo = await desktop.addTodoItem('Desktop task', null);
    final phoneTodo = await phone.addTodoItem('Phone task', null);
    final desktopHash = await attach(
      desktop,
      desktopStore,
      desktopTodo,
      'desktop.txt',
      'desktop file',
    );
    final phoneHash = await attach(
      phone,
      phoneStore,
      phoneTodo,
      'phone.txt',
      'phone file',
    );

    final message = await client.syncNow();

    expect(message, startsWith('Sync complete'));
    expect(message, contains('1 files uploaded'));
    expect(message, contains('1 downloaded'));
    expect(await phoneStore.hasBlob(desktopHash), isTrue);
    expect(await desktopStore.hasBlob(phoneHash), isTrue);
    expect(
      await phoneStore.readBytes(desktopHash),
      utf8.encode('desktop file'),
    );
    expect(await desktopStore.readBytes(phoneHash), utf8.encode('phone file'));

    final phoneAttachments = await phone.select(phone.attachments).get();
    expect(
      phoneAttachments.map((row) => row.displayName),
      containsAll(['desktop.txt', 'phone.txt']),
    );
  });

  test('manual policy leaves blobs for an explicit download', () async {
    await phone.setSetting('attachments.download_policy', 'manual');
    final desktopTodo = await desktop.addTodoItem('Desktop task', null);
    final desktopHash = await attach(
      desktop,
      desktopStore,
      desktopTodo,
      'manual.txt',
      'do not download yet',
    );

    await client.syncNow();

    expect(await phoneStore.hasBlob(desktopHash), isFalse);
    expect(
      (await phone.select(phone.attachments).get()).single.displayName,
      'manual.txt',
    );
  });
}
