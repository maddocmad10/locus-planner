import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_store.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
import 'package:locus_planner/core/services/sync_tls.dart';

import 'helpers/test_tls_identity.dart';

void main() {
  late AppDatabase database;
  late AttachmentStore store;
  late Directory root;
  late LanSyncServer server;
  late HttpClient client;
  late Uri base;
  late String token;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('locus-blob-server-');
    store = AttachmentStore(
      root: root,
      crypto: AttachmentCrypto(
        Uint8List.fromList(List.generate(32, (index) => index + 1)),
      ),
    );
    await store.ensureLayout();
    server = LanSyncServer(
      database,
      listenPort: 0,
      discoveryPort: null,
      identityLoader: () async => testTlsIdentity,
      blobStoreLoader: () async => store,
    );
    await server.start();
    base = Uri.parse('https://127.0.0.1:${server.boundPort}');
    client = pinnedSyncHttpClient(testTlsFingerprint);

    final pair = await _jsonRequest(
      client,
      base.resolve('/api/v1/pairing/exchange'),
      'POST',
      body: {
        'code': server.pairingCode,
        'deviceId': 'phone-blob-test',
        'name': 'Phone',
      },
      token: null,
    );
    token = pair['body']['token'] as String;
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await database.close();
    await root.delete(recursive: true);
  });

  test('status advertises attachments and the blob cap', () async {
    final response = await _jsonRequest(
      client,
      base.resolve('/api/v1/status'),
      'GET',
      token: token,
    );
    expect(response['status'], HttpStatus.ok);
    expect(response['body']['features'], contains('attachments-v1'));
    expect(response['body']['maxBlobBytes'], LanSyncServer.maxBlobBytes);
    expect(response['body']['blobsAvailable'], isTrue);
  });

  test('missing, upload and range download round-trip', () async {
    final bytes = Uint8List.fromList(utf8.encode('hello attachment'));
    final hash = sha256.convert(bytes).toString();

    final missing = await _jsonRequest(
      client,
      base.resolve('/api/v1/blobs/missing'),
      'POST',
      body: {
        'hashes': [hash, 'a' * 64],
      },
      token: token,
    );
    expect(missing['status'], HttpStatus.ok);
    expect(missing['body']['missing'], [hash, 'a' * 64]);

    final put = await client.openUrl(
      'PUT',
      base.resolve('/api/v1/blobs/$hash'),
    );
    put.headers
      ..contentType = ContentType.binary
      ..contentLength = bytes.length
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    put.add(bytes);
    final putResponse = await put.close();
    await putResponse.drain<void>();
    expect(putResponse.statusCode, HttpStatus.ok);
    expect(await store.hasBlob(hash), isTrue);

    final get = await client.openUrl(
      'GET',
      base.resolve('/api/v1/blobs/$hash'),
    );
    get.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final getResponse = await get.close();
    final body = await getResponse.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    expect(getResponse.statusCode, HttpStatus.ok);
    expect(body, bytes);
    expect(getResponse.headers.value('accept-ranges'), 'bytes');

    final range = await client.openUrl(
      'GET',
      base.resolve('/api/v1/blobs/$hash'),
    );
    range.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
      ..set(HttpHeaders.rangeHeader, 'bytes=6-15');
    final rangeResponse = await range.close();
    final rangeBody = await rangeResponse.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    expect(rangeResponse.statusCode, HttpStatus.partialContent);
    expect(
      rangeResponse.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 6-15/${bytes.length}',
    );
    expect(rangeBody, bytes.sublist(6, 16));
  });

  test('an upload whose hash does not match is rejected', () async {
    final bytes = Uint8List.fromList(utf8.encode('actual bytes'));
    final wrongHash = 'b' * 64;
    final put = await client.openUrl(
      'PUT',
      base.resolve('/api/v1/blobs/$wrongHash'),
    );
    put.headers
      ..contentType = ContentType.binary
      ..contentLength = bytes.length
      ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
    put.add(bytes);
    final response = await put.close();
    await response.drain<void>();
    expect(response.statusCode, 422);
    expect(await store.hasBlob(wrongHash), isFalse);
  });

  test('blob routes require the bearer token', () async {
    final response = await _jsonRequest(
      client,
      base.resolve('/api/v1/blobs/${'c' * 64}'),
      'GET',
      token: null,
    );
    expect(response['status'], HttpStatus.unauthorized);
  });
}

Future<Map<String, dynamic>> _jsonRequest(
  HttpClient client,
  Uri uri,
  String method, {
  Map<String, dynamic>? body,
  String? token,
}) async {
  final request = await client.openUrl(method, uri);
  if (body != null) request.headers.contentType = ContentType.json;
  if (token != null) {
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  }
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await response.transform(utf8.decoder).join();
  return {
    'status': response.statusCode,
    'body': text.isEmpty ? <String, dynamic>{} : jsonDecode(text),
  };
}
