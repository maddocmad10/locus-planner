import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';

/// Versioned LAN sync host. Pairing codes are short-lived and exchanged once
/// for a random bearer token; only its SHA-256 digest is persisted.
class LanSyncServer {
  LanSyncServer(this._db);

  static const port = 43821;
  static const _pairingKey = AppDatabase.syncServerPairedClientsSettingKey;
  static const _maxBodyBytes = 1024 * 1024;
  static const _maxChanges = 200;

  final AppDatabase _db;
  HttpServer? _server;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  int _failedPairAttempts = 0;
  bool _pairingInProgress = false;

  bool get isRunning => _server != null;
  String? get pairingCode =>
      _pairingExpiresAt != null &&
          AppClock.now().isBefore(_pairingExpiresAt!) &&
          _server != null
      ? _pairingCode
      : null;
  Future<void> start() async {
    if (_server != null) return;
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      throw UnsupportedError('LAN sync hosting is available on desktop only.');
    }
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    _server = server;
    _pairingCode = _randomHex(3).toUpperCase();
    _pairingExpiresAt = AppClock.now().add(const Duration(minutes: 5));
    _failedPairAttempts = 0;
    server.listen((request) => unawaited(_handle(request)));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairingCode = null;
    _pairingExpiresAt = null;
    await server?.close(force: true);
  }

  Future<List<Map<String, dynamic>>> pairedDevices() async {
    final raw = await _db.getSetting(_pairingKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(
            (entry) => {
              'deviceId': entry['deviceId'],
              'name': entry['name'],
              'pairedAt': entry['pairedAt'],
            },
          )
          .toList(growable: false);
    } catch (_) {
      return [];
    }
  }

  Future<void> revokeDevice(String deviceId) async {
    final clients = await _readClients();
    clients.removeWhere((client) => client['deviceId'] == deviceId);
    await _saveClients(clients);
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
        ..set('Cache-Control', 'no-store')
        ..set('X-Content-Type-Options', 'nosniff');
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/api/v1/health') {
        await _json(request, 200, {
          'apiVersion': 1,
          'service': 'locus-sync',
          'pairingAvailable': pairingCode != null,
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/pairing/exchange') {
        await _pair(request);
        return;
      }
      final client = await _authenticatedClient(request);
      if (client == null) {
        await _json(request, 401, {'error': 'unauthorized'});
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/changes') {
        final requestedAfter = request.uri.queryParameters['after'];
        final storedCursors =
            client['cursors'] as Map<String, dynamic>? ?? <String, dynamic>{};
        final after = requestedAfter == null
            ? (storedCursors['desktop'] as int? ?? 0)
            : int.tryParse(requestedAfter);
        final limit = int.tryParse(
          request.uri.queryParameters['limit'] ?? '100',
        );
        if (after == null ||
            after < 0 ||
            limit == null ||
            limit < 1 ||
            limit > 100) {
          await _json(request, 400, {'error': 'invalid_cursor_or_limit'});
          return;
        }
        final rows = await _db
            .customSelect(
              'SELECT id, entity_type, entity_id, operation, payload, device_id, created_at '
              'FROM sync_outbox WHERE id > ? ORDER BY id LIMIT ?',
              variables: [Variable.withInt(after), Variable.withInt(limit)],
            )
            .get();
        final filtered = rows
            .map((row) {
              final data = row.data;
              return <String, dynamic>{
                'id': data['id'],
                'entityType': data['entity_type'],
                'entityId': data['entity_id'],
                'operation': data['operation'],
                'payload': jsonDecode(data['payload'] as String),
                'deviceId': data['device_id'],
                'createdAt': data['created_at'],
              };
            })
            .toList(growable: false);
        await _json(request, 200, {
          'apiVersion': 1,
          'changes': filtered,
          'nextCursor': filtered.isEmpty ? after : filtered.last['id'],
          'hasMore': filtered.length == limit,
        });
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/changes/ack') {
        final body = await _readJson(request);
        final cursor = body['cursor'];
        if (cursor is! int || cursor < 0) {
          await _json(request, 400, {'error': 'invalid_cursor'});
          return;
        }
        final deviceId = client['deviceId'] as String;
        final clients = await _readClients();
        final index = clients.indexWhere(
          (entry) => entry['deviceId'] == deviceId,
        );
        if (index >= 0) {
          final cursors =
              (clients[index]['cursors'] as Map<String, dynamic>?) ?? {};
          final old = cursors['desktop'] is int ? cursors['desktop'] as int : 0;
          if (cursor > old) cursors['desktop'] = cursor;
          clients[index]['cursors'] = cursors;
          await _saveClients(clients);
        }
        await _json(request, 200, {'acknowledgedCursor': cursor});
        return;
      }
      if (request.method == 'POST' && path == '/api/v1/changes/apply') {
        final body = await _readJson(request);
        final rawChanges = body['changes'];
        if (rawChanges is! List || rawChanges.length > _maxChanges) {
          await _json(request, 400, {'error': 'invalid_changes'});
          return;
        }
        final changes = rawChanges.whereType<Map<String, dynamic>>().toList();
        if (changes.length != rawChanges.length) {
          await _json(request, 400, {'error': 'invalid_change_shape'});
          return;
        }
        await _applyChanges(changes);
        await _json(request, 200, {'accepted': changes.length});
        return;
      }
      await _json(request, 404, {'error': 'not_found'});
    } on FormatException {
      await _json(request, 400, {'error': 'invalid_json'});
    } on _RequestTooLarge {
      await _json(request, 413, {'error': 'request_too_large'});
    } catch (error, stackTrace) {
      print('LAN sync apply failed: $error');
      print(stackTrace);

      //  rethrow;

      await _json(request, 500, {
        'error': 'internal_error',
        'details': error.toString(),
      });
    }
  }

  Future<void> _pair(HttpRequest request) async {
    if (_failedPairAttempts >= 20) {
      await _json(request, 429, {'error': 'pairing_rate_limited'});
      return;
    }
    final body = await _readJson(request);
    final code = body['code'];
    final deviceId = body['deviceId'];
    final name = body['name'];
    if (code is! String ||
        deviceId is! String ||
        deviceId.length > 128 ||
        name is! String ||
        name.trim().isEmpty ||
        name.length > 80) {
      await _json(request, 400, {'error': 'invalid_pairing_request'});
      return;
    }
    if (_pairingInProgress) {
      await _json(request, 409, {'error': 'pairing_already_in_progress'});
      return;
    }
    if (pairingCode == null || code != _pairingCode) {
      _failedPairAttempts++;
      await _json(request, 403, {'error': 'invalid_or_expired_pairing_code'});
      return;
    }
    // Claim the one-time code before the first await so parallel requests
    // cannot exchange the same code for multiple tokens.
    _pairingInProgress = true;
    try {
      final clients = await _readClients();
      if (clients.any((entry) => entry['deviceId'] == deviceId)) {
        await _json(request, 409, {'error': 'device_already_paired'});
        return;
      }
      final token = _randomHex(32);
      clients.add({
        'deviceId': deviceId,
        'name': name.trim(),
        'pairedAt': AppClock.now().toUtc().toIso8601String(),
        'tokenHash': sha256.convert(utf8.encode(token)).toString(),
        'cursors': <String, dynamic>{},
      });
      await _saveClients(clients);
      // Pairing code is one-time. The user must explicitly generate another.
      _pairingCode = null;
      _pairingExpiresAt = null;
      await _json(request, 200, {
        'apiVersion': 1,
        'token': token,
        'serverDeviceId': await _db.getSetting(
          AppDatabase.syncDeviceIdSettingKey,
        ),
      });
    } finally {
      _pairingInProgress = false;
    }
  }

  Future<Map<String, dynamic>?> _authenticatedClient(
    HttpRequest request,
  ) async {
    final authorization = request.headers.value(
      HttpHeaders.authorizationHeader,
    );
    if (authorization == null || !authorization.startsWith('Bearer '))
      return null;
    final token = authorization.substring(7).trim();
    if (token.isEmpty || token.length > 256) return null;
    final digest = sha256.convert(utf8.encode(token)).toString();
    final clients = await _readClients();
    for (final client in clients) {
      if (client['tokenHash'] == digest) return client;
    }
    return null;
  }

  Future<void> _applyChanges(List<Map<String, dynamic>> changes) async {
    const schemas = <String, ({String table, List<String> columns})>{
      'project': (
        table: 'projects',
        columns: [
          'id',
          'name',
          'description',
          'created_at',
          'target_date',
          'target_progress',
        ],
      ),
      'event': (
        table: 'events',
        columns: [
          'id',
          'title',
          'description',
          'start_time',
          'end_time',
          'category',
          'has_reminder',
          'reminder_minutes',
          'recurrence_rule',
        ],
      ),
      'project_task': (
        table: 'tasks',
        columns: ['id', 'project_id', 'title', 'completed', 'sort_order'],
      ),
      'todo': (
        table: 'todo_items',
        columns: ['id', 'title', 'completed', 'created_at', 'due_date'],
      ),
      'diary_entry': (
        table: 'diary_entries',
        columns: ['id', 'date', 'mood', 'content'],
      ),
    };
    await _db.transaction(() async {
      await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '1');
      try {
        for (final change in changes) {
          final type = change['entityType'];
          final operation = change['operation'];
          final entityId = change['entityId'];
          if (type is! String ||
              !schemas.containsKey(type) ||
              entityId is! String ||
              entityId.isEmpty ||
              (operation != 'upsert' && operation != 'delete')) {
            throw const FormatException('Unsupported change');
          }
          final schema = schemas[type]!;
          final payload = change['payload'];
          if (payload is! Map<String, dynamic> || payload['id'] != entityId) {
            throw const FormatException('Invalid payload');
          }
          if (operation == 'delete') {
            await _db.customStatement(
              'DELETE FROM ${schema.table} WHERE id = ?',
              [Variable.withString(entityId)],
            );
            continue;
          }
          final values = schema.columns.map((column) {
            if (!payload.containsKey(column)) {
              throw const FormatException('Missing payload field');
            }
            final value = payload[column];
            if (value == null) return null;
            if (value is String) return value;
            if (value is bool) return value ? 1 : 0;
            if (value is int) return value;
            if (value is double) return value;
            if (value is num) return value;
            if (value is List<int>) return value;
            throw const FormatException('Invalid payload value');
          }).toList();
          final placeholders = List.filled(
            schema.columns.length,
            '?',
          ).join(', ');
          final columns = schema.columns.join(', ');
          final updates = schema.columns
              .where((column) => column != 'id')
              .map((column) => '$column = excluded.$column')
              .join(', ');
          await _db.customStatement(
            'INSERT INTO ${schema.table} ($columns) VALUES ($placeholders) '
            'ON CONFLICT(id) DO UPDATE SET $updates',
            values,
          );
        }
      } finally {
        await _db.setSetting(AppDatabase.syncSuppressOutboxSettingKey, '0');
      }
    });
  }

  Future<List<Map<String, dynamic>>> _readClients() async {
    final raw = await _db.getSetting(_pairingKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveClients(List<Map<String, dynamic>> clients) =>
      _db.setSetting(_pairingKey, jsonEncode(clients));

  Future<Map<String, dynamic>> _readJson(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      if (bytes.length + chunk.length > _maxBodyBytes) throw _RequestTooLarge();
      bytes.addAll(chunk);
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>)
      throw const FormatException('Expected object');
    return decoded;
  }

  Future<void> _json(HttpRequest request, int status, Object body) async {
    request.response.statusCode = status;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  String _randomHex(int bytes) {
    final random = Random.secure();
    return List<int>.generate(
      bytes,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }
}

class _RequestTooLarge implements Exception {}
