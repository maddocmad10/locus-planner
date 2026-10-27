import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import 'sync_change_applier.dart';
import 'sync_tls.dart';

/// Versioned LAN sync host, served over HTTPS with a self-signed certificate
/// that phones pin when they pair (see [SyncTlsIdentity]). Pairing codes are
/// short-lived and exchanged once for a random bearer token; only its SHA-256
/// digest is persisted.
class LanSyncServer {
  /// [listenPort] exists so tests can bind an ephemeral port (0) instead of
  /// competing for the fixed one; the app always uses [port].
  /// [identityLoader] lets tests supply a fixed certificate; the app loads (or
  /// creates) the one stored with its database.
  LanSyncServer(
    this._db, {
    int listenPort = port,
    Future<SyncTlsIdentity> Function()? identityLoader,
  }) : _listenPort = listenPort,
       _identityLoader = identityLoader;

  static const port = 43821;
  static const _pairingKey = AppDatabase.syncServerPairedClientsSettingKey;
  static const _maxBodyBytes = 1024 * 1024;
  static const _maxChanges = 200;

  /// Header a paired phone sends with the desktop's epoch (see
  /// [AppDatabase.ensureSyncEpoch]) so a reset desktop is noticed immediately.
  static const epochHeader = 'x-locus-epoch';

  /// Outbox rows older than this are dropped even if a paired phone never
  /// acknowledged them, so a lost phone cannot make the outbox grow forever.
  /// That phone is told to re-sync from a snapshot the next time it connects.
  static const outboxRetention = Duration(days: 60);

  final AppDatabase _db;
  final int _listenPort;
  final Future<SyncTlsIdentity> Function()? _identityLoader;
  SyncTlsIdentity? _identity;

  /// Fingerprint of the certificate being served, or null while stopped. It
  /// goes into the pairing QR code.
  String? get fingerprint => _identity?.fingerprint;

  /// The port actually bound, or null while stopped.
  int? get boundPort => _server?.port;

  /// Called after a phone's changes are committed, so the app can react to data
  /// that bypassed its repositories (for example by re-arming event reminders).
  /// A failure here is logged and never fails the sync request.
  Future<void> Function(SyncApplyResult result)? onChangesApplied;
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
    final identity = await (_identityLoader?.call() ??
        SyncTlsIdentity.loadOrCreate(_db));
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      _listenPort,
      identity.toSecurityContext(),
      shared: false,
    );
    _identity = identity;
    _server = server;
    regeneratePairingCode();
    await _pruneQuietly();
    server.listen(
      (request) => unawaited(_handle(request)),
      onError: (Object error) {
        // A client that rejects the certificate, or speaks plain HTTP to this
        // port, fails its TLS handshake. That is expected and must not stop
        // the server or surface as an unhandled error.
      },
    );
  }

  /// Issues a fresh five-minute pairing code and clears the failed-attempt
  /// count, so a burst of wrong guesses on the network cannot lock pairing
  /// until the next restart. Does nothing while the server is stopped.
  void regeneratePairingCode() {
    if (_server == null) return;
    _pairingCode = _randomHex(4).toUpperCase();
    _pairingExpiresAt = AppClock.now().add(const Duration(minutes: 5));
    _failedPairAttempts = 0;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _pairingCode = null;
    _pairingExpiresAt = null;
    _identity = null;
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
    await _pruneQuietly();
  }

  /// Deletes outbox rows that every paired phone has already received. A phone
  /// that has not acknowledged anything holds everything back until
  /// [outboxRetention] passes. With no paired phones nothing needs to be kept,
  /// because a newly paired phone starts from a snapshot.
  Future<void> pruneOutbox() async {
    await _db.transaction(() async {
      final head = await _db.outboxHead();
      var through = head;
      for (final client in await _readClients()) {
        final cursors = client['cursors'];
        final acked = cursors is Map && cursors['desktop'] is int
            ? cursors['desktop'] as int
            : 0;
        if (acked < through) through = acked;
      }
      final cutoff = AppClock.now()
          .subtract(outboxRetention)
          .millisecondsSinceEpoch;
      final staleRow = await _db
          .customSelect(
            'SELECT COALESCE(MAX(id), 0) AS stale FROM sync_outbox '
            'WHERE created_at < ?',
            variables: [Variable.withInt(cutoff)],
          )
          .getSingle();
      final stale = staleRow.read<int>('stale');
      if (stale > through) through = stale;
      if (through > head) through = head;
      if (through <= await _db.outboxPrunedThrough()) return;
      await _db.customStatement('DELETE FROM sync_outbox WHERE id <= ?', [
        through,
      ]);
      await _db.setSetting(
        AppDatabase.syncOutboxPrunedThroughSettingKey,
        '$through',
      );
    });
  }

  Future<void> _notifyApplied(SyncApplyResult result) async {
    final callback = onChangesApplied;
    if (callback == null || result.changes.isEmpty) return;
    try {
      await callback(result);
    } catch (error) {
      // The changes are already committed; do not report the sync as failed.
      stderr.writeln('LAN sync: post-apply hook failed: $error');
    }
  }

  Future<void> _pruneQuietly() async {
    try {
      await pruneOutbox();
    } catch (error) {
      // Pruning is housekeeping; it must never break sync or startup.
      stderr.writeln('LAN sync: outbox pruning failed: $error');
    }
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
      final epoch = await _db.ensureSyncEpoch();
      final sentEpoch = request.headers.value(epochHeader);
      // The snapshot is how a phone recovers from a mismatch, so it is exempt.
      if (path != '/api/v1/snapshot' &&
          sentEpoch != null &&
          sentEpoch != epoch) {
        await _json(request, 409, {'error': 'epoch_mismatch', 'epoch': epoch});
        return;
      }
      if (request.method == 'GET' && path == '/api/v1/snapshot') {
        final snapshot = await _readInitialSnapshot();
        await _json(request, 200, snapshot);
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
        // A cursor beyond anything this database ever issued, or before the
        // pruned range, cannot be served incrementally.
        if (after > await _db.outboxHead()) {
          await _json(request, 409, {'error': 'cursor_ahead', 'epoch': epoch});
          return;
        }
        if (after < await _db.outboxPrunedThrough()) {
          await _json(request, 409, {
            'error': 'resync_required',
            'epoch': epoch,
          });
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
          'epoch': epoch,
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
          await _pruneQuietly();
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
        final result = await SyncChangeApplier(_db).apply(changes);
        await _notifyApplied(result);
        await _json(request, 200, {
          'accepted': changes.length,
          'applied': result.applied,
          'skipped': result.skipped,
        });
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
      // The one-time code, which is only visible on the desktop, authorises
      // this pairing. A device that pairs again (after Forget pairing, a
      // reinstall, or the move to HTTPS) replaces its old entry and token.
      clients.removeWhere((entry) => entry['deviceId'] == deviceId);
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
        'epoch': await _db.ensureSyncEpoch(),
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

  /// Initial state for newly paired clients. The snapshot and outbox cursor
  /// are read in one transaction so incremental sync can safely resume after it.
  Future<Map<String, dynamic>> _readInitialSnapshot() async {
    return _db.transaction(() async {
      return {
        'apiVersion': 1,
        'epoch': await _db.ensureSyncEpoch(),
        'changes': await SyncChangeApplier.readFullState(_db),
        'cursor': await _db.outboxHead(),
      };
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
