import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/lan_sync_server.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/services/sync_tls.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/core/utils/diary_merge.dart';
import 'package:drift/native.dart';

import 'helpers/test_tls_identity.dart';

void main() {
  late AppDatabase database;
  late LanSyncServer server;
  late HttpClient client;
  late DateTime Function() originalNow;

  setUp(() async {
    originalNow = AppClock.now;
    database = AppDatabase.forTesting(NativeDatabase.memory());
    server = LanSyncServer(
      database,
      identityLoader: () async => testTlsIdentity,
    );
    client = pinnedSyncHttpClient(testTlsFingerprint);
    await server.start();
  });

  tearDown(() async {
    AppClock.now = originalNow;
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
    final uri = Uri.parse('https://127.0.0.1:${LanSyncServer.port}$path');
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

  test(
    'initial snapshot includes existing data and its outbox cursor',
    () async {
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
      await database
          .into(database.todoItems)
          .insert(
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
          (change) =>
              change['entityType'] == 'todo' &&
              change['entityId'] == 'snapshot-todo',
        ),
        isTrue,
      );
    },
  );

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

  Future<void> addTodo(String id) => database
      .into(database.todoItems)
      .insert(
        TodoItemsCompanion.insert(
          id: id,
          title: id,
          createdAt: DateTime.utc(2026, 10, 22, 8),
        ),
      );

  test(
    'snapshot pages are bounded, retryable, and retain their cursor',
    () async {
      final token = await pairForTest('paged-snapshot-client');
      for (var i = 0; i < 250; i++) {
        await addTodo('snapshot-page-$i');
      }

      final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
      final first = await request(
        'GET',
        '/api/v1/snapshot?offset=0&limit=100',
        headers: auth,
      );
      expect(first['status'], HttpStatus.ok);
      expect(first['body']['changes'], hasLength(100));
      expect(first['body']['hasMore'], isTrue);
      final cursor = first['body']['cursor'] as int;

      // Simulate an interrupted transfer by retrying the same page. Applying
      // the page twice is safe and the page/cursor contract remains stable.
      final retry = await request(
        'GET',
        '/api/v1/snapshot?offset=0&limit=100&cursor=$cursor',
        headers: auth,
      );
      expect(retry['status'], HttpStatus.ok);
      expect(retry['body']['cursor'], cursor);
      expect(retry['body']['changes'], first['body']['changes']);

      // A concurrent write after the snapshot cursor must be available through
      // incremental changes even while the remaining snapshot pages are read.
      await addTodo('snapshot-concurrent-write');
      final second = await request(
        'GET',
        '/api/v1/snapshot?offset=100&limit=100&cursor=$cursor',
        headers: auth,
      );
      final third = await request(
        'GET',
        '/api/v1/snapshot?offset=200&limit=100&cursor=$cursor',
        headers: auth,
      );
      expect(second['status'], HttpStatus.ok);
      expect(third['status'], HttpStatus.ok);
      expect(second['body']['cursor'], cursor);
      expect(third['body']['cursor'], cursor);
      expect(second['body']['changes'], hasLength(100));
      expect(third['body']['hasMore'], isFalse);
      expect(
        server.debugSnapshotMaterializations,
        1,
        reason: 'every page of one transfer should reuse one materialisation',
      );

      final incremental = await request(
        'GET',
        '/api/v1/changes?after=$cursor&limit=100',
        headers: auth,
      );
      expect(incremental['status'], HttpStatus.ok);
      expect(
        (incremental['body']['changes'] as List).any(
          (change) => change['entityId'] == 'snapshot-concurrent-write',
        ),
        isTrue,
      );
    },
  );

  test(
    'snapshot resume tokens do not skip rows deleted between pages',
    () async {
      final token = await pairForTest('keyset-snapshot-client');
      final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
      for (var i = 0; i < 250; i++) {
        await addTodo('keyset-$i');
      }

      final first = await request(
        'GET',
        '/api/v1/snapshot?limit=100',
        headers: auth,
      );
      expect(first['status'], HttpStatus.ok);
      final cursor = first['body']['cursor'] as int;
      final seen = <String>{
        for (final change in first['body']['changes'] as List)
          change['entityId'] as String,
      };
      expect(seen, hasLength(100));
      final firstAfter = first['body']['nextAfter'] as String?;
      expect(firstAfter, isNotNull);

      // Delete a row the phone already received. Positional paging would shift
      // every later row one place and silently skip the last unsent row.
      await database.customStatement('DELETE FROM todo_items WHERE id = ?', [
        'keyset-0',
      ]);
      seen.remove('keyset-0');

      var after = firstAfter;
      while (after != null) {
        final page = await request(
          'GET',
          '/api/v1/snapshot?limit=100&cursor=$cursor&after=$after',
          headers: auth,
        );
        expect(page['status'], HttpStatus.ok);
        expect(page['body']['cursor'], cursor);
        seen.addAll([
          for (final change in page['body']['changes'] as List)
            change['entityId'] as String,
        ]);
        if (page['body']['hasMore'] != true) break;
        after = page['body']['nextAfter'] as String?;
        expect(after, isNotNull);
      }

      expect(seen, hasLength(249));
      expect(seen, isNot(contains('keyset-0')));
      expect(seen, contains('keyset-249'));

      final invalid = await request(
        'GET',
        '/api/v1/snapshot?after=not-a-token',
        headers: auth,
      );
      expect(invalid['status'], HttpStatus.badRequest);
    },
  );

  test(
    'inbound changes are queued for other phones without echoing to origin',
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
          .customSelect(
            'SELECT COUNT(*) AS count FROM sync_outbox WHERE entity_id = ?',
            variables: [Variable.withString('remote-event-1')],
          )
          .getSingle();
      expect(outbox.data['count'], 1);
      final fanOut = await database
          .customSelect(
            'SELECT device_id, operation FROM sync_outbox WHERE entity_id = ?',
            variables: [Variable.withString('remote-event-1')],
          )
          .getSingle();
      expect(fanOut.read<String>('device_id'), 'test-client-apply');
      expect(fanOut.read<String>('operation'), 'upsert');
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

  test(
    'changes from one paired phone are available to another paired phone',
    () async {
      final phoneAToken = await pairForTest('fanout-phone-a');

      // Pairing codes are intentionally one-time; issue a fresh code for the
      // second device so this test models two independently paired phones.
      server.regeneratePairingCode();
      final phoneBToken = await pairForTest('fanout-phone-b');

      final applied = await request(
        'POST',
        '/api/v1/changes/apply',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $phoneAToken'},
        body: {
          'changes': [
            {
              'entityType': 'event',
              'entityId': 'fanout-event',
              'operation': 'upsert',
              'payload': {
                'id': 'fanout-event',
                'title': 'Created on phone A',
                'description': null,
                'start_time': 1790000000,
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
      expect(applied['status'], HttpStatus.ok);

      final receivedByB = await request(
        'GET',
        '/api/v1/changes?after=0&limit=100',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $phoneBToken'},
      );
      expect(receivedByB['status'], HttpStatus.ok);
      expect(
        (receivedByB['body']['changes'] as List).any(
          (change) => change['entityId'] == 'fanout-event',
        ),
        isTrue,
        reason: 'A change accepted from phone A must be queued for phone B.',
      );
      final receivedByA = await request(
        'GET',
        '/api/v1/changes?after=0&limit=100',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $phoneAToken'},
      );
      expect(receivedByA['status'], HttpStatus.ok);
      expect(
        (receivedByA['body']['changes'] as List).any(
          (change) => change['entityId'] == 'fanout-event',
        ),
        isFalse,
        reason: 'A phone must not receive its own fan-out row.',
      );
    },
  );

  Map<String, dynamic> diaryChange(String id, int date, String content) => {
    'entityType': 'diary_entry',
    'entityId': id,
    'operation': 'upsert',
    'payload': {'id': id, 'date': date, 'mood': 3, 'content': content},
  };

  test('same-day diary clash converges and keeps both texts', () async {
    final token = await pairForTest('diary-clash-client');
    final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
    await database.customStatement(
      "INSERT INTO diary_entries (id, date, mood, content) "
      "VALUES ('m-desktop', 1760000000, 3, 'desktop')",
    );

    Future<List<Map<String, Object?>>> diaryRows() async {
      final rows = await database
          .customSelect(
            'SELECT id, content FROM diary_entries WHERE date = 1760000000',
          )
          .get();
      return [for (final row in rows) row.data];
    }

    // Incoming id sorts before the existing one: incoming keeps its id and
    // the desktop text is merged into it.
    var response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: auth,
      body: {
        'changes': [diaryChange('a-phone', 1760000000, 'phone')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    final merged = mergeDiaryContent('phone', 'desktop');
    expect(await diaryRows(), [
      {'id': 'a-phone', 'content': merged},
    ]);

    // Incoming id sorts after the existing one: the existing row keeps its id
    // and the incoming text is merged into it.
    response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: auth,
      body: {
        'changes': [diaryChange('z-phone', 1760000000, 'late')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    expect(await diaryRows(), [
      {'id': 'a-phone', 'content': mergeDiaryContent(merged, 'late')},
    ]);
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

  Future<int> outboxCount() async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS n FROM sync_outbox')
        .getSingle();
    return row.read<int>('n');
  }

  test('epoch is created with the database and kept out of backups', () async {
    final epoch = await database.getSetting(AppDatabase.syncEpochSettingKey);
    expect(epoch, isNotEmpty);
    expect(
      AppDatabase.isTransientSetting(AppDatabase.syncEpochSettingKey),
      true,
    );
    expect(
      AppDatabase.isTransientSetting(
        AppDatabase.syncOutboxPrunedThroughSettingKey,
      ),
      true,
    );
    expect(
      AppDatabase.isTransientSetting(AppDatabase.syncServerEnabledSettingKey),
      true,
    );
  });
  test('a stale epoch is rejected but the snapshot stays reachable', () async {
    final pair = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': 'epoch-client',
        'name': 'Epoch client',
      },
    );
    final token = pair['body']['token'] as String;
    final epoch = pair['body']['epoch'] as String;
    expect(epoch, await database.getSetting(AppDatabase.syncEpochSettingKey));
    final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};

    final matching = await request(
      'GET',
      '/api/v1/changes?after=0',
      headers: {...auth, LanSyncServer.epochHeader: epoch},
    );
    expect(matching['status'], HttpStatus.ok);
    expect(matching['body']['epoch'], epoch);

    final stale = await request(
      'GET',
      '/api/v1/changes?after=0',
      headers: {...auth, LanSyncServer.epochHeader: 'old-epoch'},
    );
    expect(stale['status'], HttpStatus.conflict);
    expect(stale['body']['error'], 'epoch_mismatch');

    final staleApply = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: {...auth, LanSyncServer.epochHeader: 'old-epoch'},
      body: {'changes': <Object>[]},
    );
    expect(staleApply['status'], HttpStatus.conflict);

    final snapshot = await request(
      'GET',
      '/api/v1/snapshot',
      headers: {...auth, LanSyncServer.epochHeader: 'old-epoch'},
    );
    expect(snapshot['status'], HttpStatus.ok);
    expect(snapshot['body']['epoch'], epoch);
  });

  test('a cursor ahead of the desktop history requires a resync', () async {
    final token = await pairForTest('ahead-client');
    await addTodo('one');
    final response = await request(
      'GET',
      '/api/v1/changes?after=999',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );
    expect(response['status'], HttpStatus.conflict);
    expect(response['body']['error'], 'cursor_ahead');
  });

  test('acknowledged outbox rows are pruned and old cursors resync', () async {
    final token = await pairForTest('prune-client');
    final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
    await addTodo('first');
    await addTodo('second');
    expect(await outboxCount(), 2);

    final ack = await request(
      'POST',
      '/api/v1/changes/ack',
      headers: auth,
      body: {'cursor': 1},
    );
    expect(ack['status'], HttpStatus.ok);
    expect(await outboxCount(), 1);
    expect(await database.outboxPrunedThrough(), 1);

    final tooOld = await request(
      'GET',
      '/api/v1/changes?after=0',
      headers: auth,
    );
    expect(tooOld['status'], HttpStatus.conflict);
    expect(tooOld['body']['error'], 'resync_required');

    final current = await request(
      'GET',
      '/api/v1/changes?after=1',
      headers: auth,
    );
    expect(current['status'], HttpStatus.ok);
    expect(current['body']['changes'], hasLength(1));
    expect(current['body']['changes'][0]['entityId'], 'second');
  });

  test(
    'with no paired phones the outbox is cleared without reusing ids',
    () async {
      await addTodo('before-pairing');
      await server.pruneOutbox();
      expect(await outboxCount(), 0);
      expect(await database.outboxPrunedThrough(), 1);

      await addTodo('after-pruning');
      final row = await database
          .customSelect('SELECT MAX(id) AS id FROM sync_outbox')
          .getSingle();
      expect(row.read<int>('id'), 2);
      expect(await database.outboxHead(), 2);
    },
  );

  test('an unresponsive phone cannot pin the outbox forever', () async {
    await database.customStatement(
      'INSERT INTO sync_outbox '
      '(entity_type, entity_id, operation, payload, device_id, created_at) '
      "VALUES ('todo', 'ancient', 'upsert', '{}', NULL, 1)",
    );
    await pairForTest('silent-client');
    await addTodo('recent');

    await server.pruneOutbox();
    expect(await outboxCount(), 1);
    expect(await database.outboxPrunedThrough(), 1);
  });

  Map<String, dynamic> eventApplyChange(String id) => {
    'entityType': 'event',
    'entityId': id,
    'operation': 'upsert',
    'payload': {
      'id': id,
      'title': 'From phone',
      'description': null,
      'start_time': 1790000000,
      'end_time': null,
      'category': 'general',
      'has_reminder': 1,
      'reminder_minutes': 10,
      'recurrence_rule': null,
    },
  };

  test(
    'unknown entity types are skipped without blocking known changes',
    () async {
      final token = await pairForTest('unknown-entity-client');
      final response = await request(
        'POST',
        '/api/v1/changes/apply',
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
        body: {
          'changes': [
            eventApplyChange('known-event-before-unknown'),
            {
              'entityType': 'future_entity',
              'entityId': 'future-entity-1',
              'operation': 'upsert',
              'payload': {
                'id': 'future-entity-1',
                'value': 'newer desktop entity',
              },
            },
          ],
        },
      );

      expect(response['status'], HttpStatus.ok);
      expect(response['body']['accepted'], 2);
      expect(response['body']['applied'], 1);
      expect(response['body']['skipped'], 1);
      final known = await database
          .customSelect(
            "SELECT id FROM events WHERE id = 'known-event-before-unknown'",
          )
          .get();
      expect(known, hasLength(1));
    },
  );

  test('a malformed change is rejected without losing the batch', () async {
    final token = await pairForTest('malformed-payload-client');
    final response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      body: {
        'changes': [
          eventApplyChange('applied-before-malformed'),
          {
            'entityType': 'event',
            'entityId': 'malformed-event',
            'operation': 'upsert',
            'payload': {
              'id': 'malformed-event',
              'title': 'Missing required fields',
              'description': null,
            },
          },
          eventApplyChange('applied-after-malformed'),
        ],
      },
    );

    // The request succeeds so the phone advances its cursor. The offending
    // change is named in the response instead of poisoning the whole page.
    expect(response['status'], HttpStatus.ok);
    expect(response['body']['applied'], 2);
    expect(response['body']['skipped'], 0);
    expect(response['body']['rejected'], hasLength(1));
    expect(response['body']['rejected'][0]['entityType'], 'event');
    expect(response['body']['rejected'][0]['entityId'], 'malformed-event');
    expect(response['body']['rejected'][0]['reason'], isNotEmpty);

    for (final id in ['applied-before-malformed', 'applied-after-malformed']) {
      final rows = await database
          .customSelect(
            'SELECT id FROM events WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .get();
      expect(rows, hasLength(1), reason: '$id should still be applied');
    }
    final malformed = await database
        .customSelect("SELECT id FROM events WHERE id = 'malformed-event'")
        .get();
    expect(malformed, isEmpty);
  });

  test('onChangesApplied receives the rows a phone changed', () async {
    final token = await pairForTest('hook-client');
    final seen = <SyncApplyResult>[];
    server.onChangesApplied = (result) async => seen.add(result);

    final response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      body: {
        'changes': [eventApplyChange('hook-event')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    expect(response['body']['applied'], 1);
    expect(seen, hasLength(1));
    expect(seen.single.changes.single, (
      type: 'event',
      id: 'hook-event',
      deleted: false,
    ));
  });

  test('a failing onChangesApplied hook does not fail the sync', () async {
    final token = await pairForTest('bad-hook-client');
    server.onChangesApplied = (result) async => throw StateError('boom');

    final response = await request(
      'POST',
      '/api/v1/changes/apply',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      body: {
        'changes': [eventApplyChange('bad-hook-event')],
      },
    );
    expect(response['status'], HttpStatus.ok);
    final rows = await database
        .customSelect("SELECT id FROM events WHERE id = 'bad-hook-event'")
        .get();
    expect(rows, hasLength(1));
  });

  test('the server reports the fingerprint of the certificate it serves', () {
    expect(server.fingerprint, testTlsFingerprint);
  });

  test('a client pinned to another certificate is turned away', () async {
    final wrong = pinnedSyncHttpClient('0' * 64);
    addTearDown(() => wrong.close(force: true));
    await expectLater(
      wrong.getUrl(
        Uri.parse('https://127.0.0.1:${LanSyncServer.port}/api/v1/health'),
      ),
      throwsA(isA<TlsException>()),
    );

    // The failed handshake must not take the server down.
    final response = await request('GET', '/api/v1/health');
    expect(response['status'], HttpStatus.ok);
  });

  test('plain HTTP is not served', () async {
    final plain = HttpClient();
    addTearDown(() => plain.close(force: true));
    Future<void> attempt() async {
      final req = await plain.getUrl(
        Uri.parse('http://127.0.0.1:${LanSyncServer.port}/api/v1/health'),
      );
      final res = await req.close();
      await res.drain<void>();
    }

    await expectLater(
      attempt().timeout(const Duration(seconds: 5)),
      throwsA(isA<IOException>()),
    );
    final response = await request('GET', '/api/v1/health');
    expect(response['status'], HttpStatus.ok);
  });

  test('a new pairing code resets the failed-attempt lockout', () async {
    for (var i = 0; i < 20; i++) {
      final response = await request(
        'POST',
        '/api/v1/pairing/exchange',
        body: {'code': 'WRONG$i', 'deviceId': 'guesser', 'name': 'Guesser'},
      );
      expect(response['status'], HttpStatus.forbidden);
    }
    final locked = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': 'real-phone',
        'name': 'Real phone',
      },
    );
    expect(locked['status'], 429);

    final before = server.pairingCode;
    server.regeneratePairingCode();
    expect(server.pairingCode, isNot(before));
    expect(server.pairingCode, hasLength(8));

    final paired = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {
        'code': server.pairingCode,
        'deviceId': 'real-phone',
        'name': 'Real phone',
      },
    );
    expect(paired['status'], HttpStatus.ok);
  });

  test('pairing again replaces the old token of the same device', () async {
    final oldToken = await pairForTest('returning-phone');
    server.regeneratePairingCode();
    final newToken = await pairForTest('returning-phone');
    expect(newToken, isNot(oldToken));

    final stale = await request(
      'GET',
      '/api/v1/changes',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $oldToken'},
    );
    expect(stale['status'], HttpStatus.unauthorized);
    final fresh = await request(
      'GET',
      '/api/v1/changes',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $newToken'},
    );
    expect(fresh['status'], HttpStatus.ok);
    expect(await server.pairedDevices(), hasLength(1));
  });

  test('overlapping acknowledgements from phones all persist', () async {
    final tokens = <String, String>{};
    for (final id in ['device-a', 'device-b', 'device-c']) {
      server.regeneratePairingCode();
      tokens[id] = await pairForTest(id);
    }
    final cursors = {'device-a': 11, 'device-b': 22, 'device-c': 33};

    // Each acknowledgement reads and rewrites the shared list of paired
    // phones. Without serialising, they all start from the same old list and
    // the last one to finish erases the others' progress.
    final responses = await Future.wait([
      for (final entry in cursors.entries)
        request(
          'POST',
          '/api/v1/changes/ack',
          headers: {
            HttpHeaders.authorizationHeader: 'Bearer ${tokens[entry.key]}',
          },
          body: {'cursor': entry.value},
        ),
    ]);
    expect(responses.map((r) => r['status']), everyElement(HttpStatus.ok));

    final stored =
        jsonDecode(
              (await database.getSetting(
                AppDatabase.syncServerPairedClientsSettingKey,
              ))!,
            )
            as List<dynamic>;
    expect(stored, hasLength(3));
    for (final client in stored.cast<Map<String, dynamic>>()) {
      final acknowledged = (client['cursors'] as Map)['desktop'];
      expect(acknowledged, cursors[client['deviceId']]);
    }
  });

  test('a revoked phone stays revoked after a late acknowledgement', () async {
    final token = await pairForTest('revoked-then-ack');
    await server.revokeDevice('revoked-then-ack');

    final late = await request(
      'POST',
      '/api/v1/changes/ack',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      body: {'cursor': 5},
    );

    expect(late['status'], HttpStatus.unauthorized);
    expect(await server.pairedDevices(), isEmpty);
  });

  test('an unexpected failure does not leak its cause', () async {
    final token = await pairForTest('error-client');
    // With its outbox table gone the changes endpoint fails unexpectedly.
    await database.customStatement('DROP TABLE sync_outbox');

    final response = await request(
      'GET',
      '/api/v1/changes?after=0&limit=10',
      headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
    );

    expect(response['status'], HttpStatus.internalServerError);
    expect(response['body'], {'error': 'internal_error'});
  });

  test(
    'changes reports hasMore only when another row actually exists',
    () async {
      final token = await pairForTest('has-more-client');
      final auth = {HttpHeaders.authorizationHeader: 'Bearer $token'};
      for (var i = 0; i < 3; i++) {
        await addTodo('has-more-$i');
      }

      // Exactly a page of rows: no extra round-trip should be needed.
      final exact = await request(
        'GET',
        '/api/v1/changes?after=0&limit=3',
        headers: auth,
      );
      expect(exact['body']['changes'], hasLength(3));
      expect(exact['body']['hasMore'], isFalse);

      // One row beyond the page: hasMore is true, and nextCursor names the last
      // row actually returned, not the look-ahead row.
      final more = await request(
        'GET',
        '/api/v1/changes?after=0&limit=2',
        headers: auth,
      );
      expect(more['body']['changes'], hasLength(2));
      expect(more['body']['hasMore'], isTrue);
      final next = more['body']['nextCursor'] as int;
      expect(next, (more['body']['changes'] as List).last['id']);

      final rest = await request(
        'GET',
        '/api/v1/changes?after=$next&limit=2',
        headers: auth,
      );
      expect(rest['body']['changes'], hasLength(1));
      expect(rest['body']['changes'][0]['entityId'], 'has-more-2');
      expect(rest['body']['hasMore'], isFalse);
    },
  );

  test('a malformed JSON body is reported as invalid_json', () async {
    final token = await pairForTest('invalid-json-client');
    final request = await client.postUrl(
      Uri.parse('https://127.0.0.1:${LanSyncServer.port}/api/v1/changes/apply'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.headers.contentType = ContentType.json;
    request.write('{"changes": [');
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();

    expect(response.statusCode, HttpStatus.badRequest);
    expect(jsonDecode(text), {'error': 'invalid_json'});
  });

  test('a request body that never finishes is timed out', () async {
    final slowServer = LanSyncServer(
      database,
      listenPort: 0,
      discoveryPort: null,
      identityLoader: () async => testTlsIdentity,
      requestReadTimeout: const Duration(milliseconds: 200),
    );
    await slowServer.start();
    addTearDown(slowServer.stop);

    final socket = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      slowServer.boundPort!,
      onBadCertificate: (_) => true,
    );
    addTearDown(socket.destroy);
    // Send complete headers and only part of the declared body, as a
    // slowloris client would.
    socket.write(
      'POST /api/v1/pairing/exchange HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: 100\r\n'
      '\r\n'
      '{"code":',
    );
    final response = StringBuffer();
    await for (final chunk
        in socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 5))) {
      response.write(chunk);
      if (response.toString().contains('request_timeout')) break;
    }

    expect(response.toString(), contains(' 408 '));
    expect(response.toString(), contains('request_timeout'));
  });

  test('an oversized request body is rejected with 413', () async {
    const size = 1024 * 1024 + 1;
    final socket = await SecureSocket.connect(
      InternetAddress.loopbackIPv4,
      server.boundPort!,
      onBadCertificate: (_) => true,
    );
    addTearDown(socket.destroy);

    socket.write(
      'POST /api/v1/pairing/exchange HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: $size\r\n'
      '\r\n',
    );
    try {
      socket.write('x' * size);
    } catch (_) {
      // The server may close the connection as soon as it sees the limit.
    }

    final response = StringBuffer();
    await for (final chunk
        in socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .timeout(const Duration(seconds: 5))) {
      response.write(chunk);
      if (response.toString().contains('request_too_large')) break;
    }

    expect(response.toString(), contains(' 413 '));
    expect(response.toString(), contains('request_too_large'));
  });

  test('LAN sync remembers being switched on across restarts', () async {
    expect(await server.enabledPreference(), isFalse);
    await server.saveEnabledPreference(true);
    await server.stop();

    final restarted = LanSyncServer(
      database,
      listenPort: 0,
      discoveryPort: null,
      identityLoader: () async => testTlsIdentity,
    );
    addTearDown(restarted.stop);
    expect(await restarted.startFromSavedPreference(), isTrue);
    expect(restarted.isRunning, isTrue);

    await restarted.saveEnabledPreference(false);
    await restarted.stop();
    expect(await restarted.startFromSavedPreference(), isFalse);
    expect(restarted.isRunning, isFalse);
  });

  test('an expired pairing code is hidden and refused', () async {
    server.regeneratePairingCode();
    final code = server.pairingCode!;
    final expiresAt = server.pairingExpiresAt!;
    expect(expiresAt.difference(originalNow()), greaterThan(Duration.zero));
    expect(
      expiresAt.difference(originalNow()),
      lessThanOrEqualTo(const Duration(minutes: 5)),
    );

    AppClock.now = () => expiresAt.add(const Duration(seconds: 1));
    expect(server.pairingCode, isNull);
    expect(server.pairingExpiresAt, isNull);

    final late = await request(
      'POST',
      '/api/v1/pairing/exchange',
      body: {'code': code, 'deviceId': 'late-phone', 'name': 'Late phone'},
    );
    expect(late['status'], HttpStatus.forbidden);

    AppClock.now = originalNow;
    server.regeneratePairingCode();
    expect(server.pairingCode, isNotNull);
  });

  test('the pairing countdown reports minutes, seconds, and expiry', () {
    final now = DateTime(2026, 10, 29, 12);
    expect(pairingCodeExpiryLabel(null, now), 'expires soon');
    expect(
      pairingCodeExpiryLabel(
        now.add(const Duration(minutes: 4, seconds: 5)),
        now,
      ),
      'expires in 4:05',
    );
    expect(pairingCodeExpiryLabel(now, now), 'expired');
    expect(
      pairingCodeExpiryLabel(now.subtract(const Duration(seconds: 1)), now),
      'expired',
    );
  });
}
