import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import 'sync_change_applier.dart';
import 'sync_discovery.dart';
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
  ///
  /// [discoveryPort] is the UDP port that answers a phone asking where the
  /// desktop is (see [SyncDiscoveryResponder]); pass 0 to pick a free one, or
  /// null to turn discovery off.
  LanSyncServer(
    this._db, {
    this._listenPort = port,
    this._identityLoader,
    this._discoveryPort = syncDiscoveryPort,
  });

  static const port = 43821;
  static const _pairingKey = AppDatabase.syncServerPairedClientsSettingKey;
  static const _maxBodyBytes = 1024 * 1024;
  static const _maxChanges = 200;
  static const _snapshotPageSize = 100;

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
  final int? _discoveryPort;
  SyncTlsIdentity? _identity;
  SyncDiscoveryResponder? _discovery;

  /// Fingerprint of the certificate being served, or null while stopped. It
  /// goes into the pairing QR code.
  String? get fingerprint => _identity?.fingerprint;

  /// The port actually bound, or null while stopped.
  int? get boundPort => _server?.port;

  /// The UDP discovery port actually bound, or null if discovery is off, could
  /// not start, or the server is stopped.
  int? get boundDiscoveryPort => _discovery?.boundPort;

  /// Called after a phone's changes are committed, so the app can react to data
  /// that bypassed its repositories (for example by re-arming event reminders).
  /// A failure here is logged and never fails the sync request.
  Future<void> Function(SyncApplyResult result)? onChangesApplied;
  HttpServer? _server;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  int _failedPairAttempts = 0;
  bool _pairingInProgress = false;

  /// Tail of the queue that serialises every read-modify-write of the paired
  /// clients list (see [_withClientsLock]).
  Future<void> _clientsQueue = Future<void>.value();

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
    final identity =
        await (_identityLoader?.call() ?? SyncTlsIdentity.loadOrCreate(_db));
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      _listenPort,
      identity.toSecurityContext(),
      shared: false,
    );
    _identity = identity;
    _server = server;
    regeneratePairingCode();
    await _startDiscovery(identity, server.port);
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
    _discovery?.stop();
    _discovery = null;
    await server?.close(force: true);
  }

  /// Starts answering phones that ask where this desktop is. This is a
  /// convenience: if it cannot start, sync still works by address.
  Future<void> _startDiscovery(SyncTlsIdentity identity, int httpsPort) async {
    final discoveryPort = _discoveryPort;
    if (discoveryPort == null) return;
    final responder = SyncDiscoveryResponder(
      fingerprint: identity.fingerprint,
      syncPort: httpsPort,
      port: discoveryPort,
    );
    if (await responder.start()) _discovery = responder;
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
    await _withClientsLock(() async {
      final clients = await _readClients();
      clients.removeWhere((client) => client['deviceId'] == deviceId);
      await _saveClients(clients);
    });
    await _pruneQuietly();
  }

  /// The paired clients live in one JSON setting, so every change reads the
  /// whole list, edits it and writes it back across awaits. Two overlapping
  /// changes (a phone acknowledging while another pairs, or the user revoking
  /// a device) would each start from the same old list, and the later write
  /// would silently undo the earlier one: a revoked phone could reappear, or a
  /// new pairing could vanish. Running those changes one at a time prevents
  /// that. [action] must not call [_withClientsLock] itself.
  Future<T> _withClientsLock<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final previous = _clientsQueue;
    _clientsQueue = result.future.then<void>((_) {}, onError: (Object _) {});
    unawaited(
      previous.then((_) async {
        try {
          result.complete(await action());
        } catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        }
      }),
    );
    return result.future;
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
        final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '0');
        final requestedCursor = request.uri.queryParameters['cursor'];
        final cursor = requestedCursor == null
            ? null
            : int.tryParse(requestedCursor);
        final limit = int.tryParse(
          request.uri.queryParameters['limit'] ?? '$_snapshotPageSize',
        );
        if (offset == null || offset < 0 ||
            (requestedCursor != null && (cursor == null || cursor < 0)) ||
            limit == null || limit < 1 || limit > _snapshotPageSize) {
          await _json(request, 400, {'error': 'invalid_snapshot_page'});
          return;
        }
        final snapshot = await _readInitialSnapshot(
          offset: offset,
          limit: limit,
          cursor: cursor,
        );
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
        final requesterDeviceId = client['deviceId'] as String? ?? '';
        // Read a bounded window first, then omit changes that originated on
        // this phone. The cursor still advances over omitted rows, otherwise a
        // page containing only the requester's own changes could loop forever.
        final visibleRows = rows.where(
          (row) => row.readNullable<String>('device_id') != requesterDeviceId,
        );
        final filtered = visibleRows
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
          'nextCursor': rows.isEmpty ? after : rows.last.read<int>('id'),
          'hasMore': rows.length == limit,
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
        final updated = await _withClientsLock(() async {
          // Read inside the lock: the list held by `client` may be stale, and
          // a device revoked in the meantime must not be written back.
          final clients = await _readClients();
          final index = clients.indexWhere(
            (entry) => entry['deviceId'] == deviceId,
          );
          if (index < 0) return false;
          final cursors =
              (clients[index]['cursors'] as Map<String, dynamic>?) ?? {};
          final old = cursors['desktop'] is int ? cursors['desktop'] as int : 0;
          if (cursor > old) cursors['desktop'] = cursor;
          clients[index]['cursors'] = cursors;
          await _saveClients(clients);
          return true;
        });
        if (updated) await _pruneQuietly();
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
        // The bearer token identifies the actual sender; do not trust a
        // deviceId supplied inside the JSON payload for origin filtering.
        final originDeviceId = client['deviceId'] as String?;
        final identifiedChanges = changes
            .map((change) => <String, dynamic>{
                  ...change,
                  'deviceId': originDeviceId,
                })
            .toList(growable: false);
        final result = await SyncChangeApplier(_db).apply(
          identifiedChanges,
          fanOutOriginDeviceId: originDeviceId,
        );
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
      developer.log(
        'LAN sync request failed',
        name: 'LanSyncServer',
        error: error,
        stackTrace: stackTrace,
      );
      // The cause is logged above; it is not sent to the network.
      await _json(request, 500, {'error': 'internal_error'});
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
      // The one-time code, which is only visible on the desktop, authorises
      // this pairing. A device that pairs again (after Forget pairing, a
      // reinstall, or the move to HTTPS) replaces its old entry and token.
      final token = _randomHex(32);
      await _withClientsLock(() async {
        final clients = await _readClients();
        clients.removeWhere((entry) => entry['deviceId'] == deviceId);
        clients.add({
          'deviceId': deviceId,
          'name': name.trim(),
          'pairedAt': AppClock.now().toUtc().toIso8601String(),
          'tokenHash': sha256.convert(utf8.encode(token)).toString(),
          'cursors': <String, dynamic>{},
        });
        await _saveClients(clients);
      });
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
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final token = authorization.substring(7).trim();
    if (token.isEmpty || token.length > 256) return null;
    final digest = sha256.convert(utf8.encode(token)).toString();
    final clients = await _readClients();
    for (final client in clients) {
      if (client['tokenHash'] == digest) return client;
    }
    return null;
  }

  /// Returns a bounded snapshot page. The first page captures the outbox
  /// cursor; later pages reuse it so all changes made during transfer are
  /// replayed by incremental sync after the snapshot is applied. Re-reading
  /// the state for each page is safe because row versions are compared on apply
  /// and any concurrent insert/update/delete is represented after [cursor].
  Future<Map<String, dynamic>> _readInitialSnapshot({
    required int offset,
    required int limit,
    int? cursor,
  }) async {
    return _db.transaction(() async {
      final epoch = await _db.ensureSyncEpoch();
      final snapshotCursor = cursor ?? await _db.outboxHead();
      final allChanges = await SyncChangeApplier.readFullState(_db);
      final end = min(offset + limit, allChanges.length);
      final page = offset >= allChanges.length
          ? <Map<String, dynamic>>[]
          : allChanges.sublist(offset, end);
      return {
        'apiVersion': 1,
        'epoch': epoch,
        'cursor': snapshotCursor,
        'offset': offset,
        'nextOffset': offset + page.length,
        'hasMore': offset + page.length < allChanges.length,
        'changes': page,
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
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected object');
    }
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
