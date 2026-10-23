import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
import 'package:drift/native.dart';

void main() {
  late AppDatabase database;
  late LanSyncServer server;
  late HttpClient client;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    server = LanSyncServer(database);
    client = HttpClient();
    await server.start();
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await database.close();
  });

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    final uri = Uri.parse('http://127.0.0.1:${LanSyncServer.port}$path');
    final req = await client.openUrl(method, uri);
    headers.forEach((name, value) => req.headers.set(name, value));
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close();
    final text = await response.transform(utf8.decoder).join();
    return {
      'status': response.statusCode,
      'body': text.isEmpty ? <String, dynamic>{} : jsonDecode(text),
    };
  }

  test(
    'health endpoint is versioned and does not require authentication',
    () async {
      final response = await request('GET', '/api/v1/health');
      expect(response['status'], HttpStatus.ok);
      expect(response['body']['apiVersion'], 1);
      expect(response['body']['service'], 'locus-sync');
    },
  );

  test(
    'pairing code is one-time and issued token is required for changes',
    () async {
      final code = server.pairingCode!;
      final pair = await request(
        'POST',
        '/api/v1/pairing/exchange',
        body: {
          'code': code,
          'deviceId': 'test-client-1',
          'name': 'Test client',
        },
      );
      expect(pair['status'], HttpStatus.ok);
      final token = pair['body']['token'] as String;
      expect(token, isNotEmpty);
      expect(server.pairingCode, isNull);

      final unauthorized = await request('GET', '/api/v1/changes');
      expect(unauthorized['status'], HttpStatus.unauthorized);

      await database
          .into(database.events)
          .insert(
            EventsCompanion.insert(
              id: 'outgoing-event-1',
              title: 'Outbound event',
              startTime: DateTime.utc(2026, 10, 22, 9),
            ),
          );

      final authorized = await request(
        'GET',
        '/api/v1/changes?after=0&limit=10',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      expect(authorized['status'], HttpStatus.ok);
      expect(authorized['body']['apiVersion'], 1);
      expect(authorized['body']['changes'], hasLength(1));
      expect(authorized['body']['changes'][0]['entityType'], 'event');
      expect(authorized['body']['changes'][0]['entityId'], 'outgoing-event-1');
    },
  );

  test('initial snapshot includes existing data and its outbox cursor', () async {
    final pair = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': 'snapshot-client',
        'name': 'Snapshot client',
      },
    );
    final token = pair['body']['token'] as String;
    await database.into(database.todoItems).insert(
      TodoItemsCompanion.insert(
        id: 'snapshot-todo',
        title: 'Already on desktop',
        createdAt: DateTime.utc(2026, 10, 22, 8),
      ),
    );

    final response = await request(
      'GET',
      '/api/v1/snapshot',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );
    expect(response['status'], HttpStatus.ok);
    expect(response['body']['apiVersion'], 1);
    expect(response['body']['cursor'], greaterThan(0));
    expect(
      (response['body']['changes'] as List).any(
        (change) => change['entityType'] == 'todo' &&
            change['entityId'] == 'snapshot-todo',
      ),
      isTrue,
    );
  });

  test(
    'inbound changes apply atomically without creating outbox echoes',
    () async {
      final pair = await request(
        'POST',
        '/api/v1/pairing/exchange',
        body: {
          'code': server.pairingCode,
          'deviceId': 'test-client-apply',
          'name': 'Apply test',
        },
      );
      final token = pair['body']['token'] as String;
      final response = await request(
        'POST',
        '/api/v1/changes/apply',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        body: {
          'changes': [
            {
              'entityType': 'event',
              'entityId': 'remote-event-1',
              'operation': 'upsert',
              'payload': {
                'id': 'remote-event-1',
                'title': 'Synced event',
                'description': null,
                'start_time': 1760000000000,
                'end_time': null,
                'category': 'general',
                'has_reminder': 0,
                'reminder_minutes': 10,
                'recurrence_rule': null,
              },
            },
          ],
        },
      );

      expect(response['status'], HttpStatus.ok);
      final events = await database
          .customSelect("SELECT title FROM events WHERE id = 'remote-event-1'")
          .getSingle();
      expect(events.data['title'], 'Synced event');
      final outbox = await database
          .customSelect('SELECT COUNT(*) AS count FROM sync_outbox')
          .getSingle();
      expect(outbox.data['count'], 0);
    },
  );

  test('revoking a paired device invalidates its bearer token', () async {
    final pair = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': 'test-client-2',
        'name': 'Revoked client',
      },
    );
    final token = pair['body']['token'] as String;
    await server.revokeDevice('test-client-2');

    final response = await request(
      'GET',
      '/api/v1/changes',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );
    expect(response['status'], HttpStatus.unauthorized);
  });

  Future<String> pairForTest(String deviceId) async {
    final pair = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': deviceId,
        'name': 'Test device',
      },
    );
    return pair['body']['token'] as String;
  }

  Map<String, dynamic> diaryChange(String id, int date, String content) => {
    'entityType': 'diary_entry',
    'entityId': id,
    'operation': 'upsert',
    'payload': {'id': id, 'date': date, 'mood': 3, 'content': content},
  };

  test('same-day diary clash converges', () async {
    final token = await pairForTest('diary-clash-client');
    final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
    await database.customStatement(
      "INSERT INTO diary_entries (id, date, mood, content) "
      "VALUES ('m-desktop', 1760000000, 3, 'desktop')",
    );

    // Incoming id sorts before the existing one: incoming replaces it.
    var response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: auth,
      body: {
        'changes': [diaryChange('a-phone', 1760000000, 'phone')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    var rows = await database
        .customSelect('SELECT id FROM diary_entries WHERE date = 1760000000')
        .get();
    expect(rows.map((row) => row.data['id']), ['a-phone']);

    // Incoming id sorts after the existing one: incoming is ignored.
    response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: auth,
      body: {
        'changes': [diaryChange('z-phone', 1760000000, 'late')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    rows = await database
        .customSelect('SELECT id FROM diary_entries WHERE date = 1760000000')
        .get();
    expect(rows.map((row) => row.data['id']), ['a-phone']);
  });

  test('task for a deleted project is skipped instead of failing', () async {
    final token = await pairForTest('orphan-task-client');
    final response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      body: {
        'changes': [
          {
            'entityType': 'project_task',
            'entityId': 'orphan-task',
            'operation': 'upsert',
            'payload': {
              'id': 'orphan-task',
              'project_id': 'missing-project',
              'title': 'Orphan',
              'completed': 0,
              'sort_order': 0,
            },
          },
        ],
      },
    );
    expect(response['status'], HttpStatus.ok);
    final rows = await database
        .customSelect("SELECT id FROM tasks WHERE id = 'orphan-task'")
        .get();
    expect(rows, isEmpty);
  });
}
