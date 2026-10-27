import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../../../core/services/sync_change_applier.dart';
import '../../../core/services/sync_tls.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/providers/database_provider.dart';

final mobileSyncClientProvider = Provider<MobileSyncClient>((ref) {
  return MobileSyncClient(ref.watch(databaseProvider));
});

class MobileSyncStatus {
  const MobileSyncStatus({
    required this.paired,
    this.host,
    this.lastSync,
    this.needsRepair = false,
  });
  final bool paired;
  final String? host;
  final DateTime? lastSync;

  /// This phone paired with an earlier version that used plain HTTP. It has no
  /// pinned certificate, so it must pair again.
  final bool needsRepair;
}

/// Where the bearer token is kept. Production uses Keystore-backed secure
/// storage; tests substitute an in-memory store.
abstract interface class SyncTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureSyncTokenStore implements SyncTokenStore {
  const SecureSyncTokenStore();

  static const _tokenKey = 'locus.sync.bearer_token';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

/// The desktop's change history no longer matches this phone's cursors (it was
/// reset, replaced, or pruned past them), so incremental sync cannot continue.
class SyncResyncRequired implements Exception {
  const SyncResyncRequired(this.reason);

  final String reason;

  @override
  String toString() =>
      'The desktop data changed and could not be re-synced ($reason). '
      'Try again, or unpair and pair this phone again.';
}

/// The server answered with a certificate other than the one this phone pinned
/// when it paired, or is not a Locus desktop at all.
class SyncCertificateMismatch implements Exception {
  const SyncCertificateMismatch();

  @override
  String toString() =>
      'This is not the desktop this phone was paired with. If you reset Locus '
      'on the desktop, tap Forget pairing and pair again.';
}

/// Android-side client for the desktop LAN sync API. The bearer token is kept
/// in Android Keystore-backed secure storage; only non-secret settings/cursors
/// use SharedPreferences.
class MobileSyncClient {
  MobileSyncClient(
    this._db, {
    SyncTokenStore tokenStore = const SecureSyncTokenStore(),
  }) : _tokenStore = tokenStore;

  final AppDatabase _db;
  static const _hostKey = 'locus.sync.host';

  /// SHA-256 fingerprint of the desktop certificate pinned at pairing. It is
  /// public information, so it lives with the other non-secret settings.
  static const _pinKey = 'locus.sync.pin';
  static const _snapshotKey = 'locus.sync.snapshot_done';
  static const _remoteCursorKey = 'locus.sync.remote_cursor';
  static const _pushedCursorKey = 'locus.sync.pushed_cursor';
  static const _epochKey = 'locus.sync.server_epoch';
  static const _epochHeader = 'X-Locus-Epoch';
  static const _maxBatch = 100;
  static const _needsRepairMessage =
      'Locus sync now uses a verified, encrypted connection. Pair this phone '
      'with the desktop again, scanning the QR code in desktop Settings.';
  final SyncTokenStore _tokenStore;

  Future<MobileSyncStatus> status() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStore.read();
    final host = prefs.getString(_hostKey);
    final pin = prefs.getString(_pinKey);
    final last = prefs.getString('locus.sync.last_sync');
    final hasCredentials = token != null && token.isNotEmpty && host != null;
    return MobileSyncStatus(
      paired: hasCredentials && pin != null,
      needsRepair: hasCredentials && pin == null,
      host: host,
      lastSync: last == null ? null : DateTime.tryParse(last),
    );
  }

  /// Connects to the desktop and returns the fingerprint of the certificate it
  /// presents, without sending anything. Used by manual pairing: the user
  /// compares it with the fingerprint shown on the desktop before trusting it.
  Future<String> fetchDesktopFingerprint(String host) async {
    final base = _normalizeHost(host);
    try {
      return await fetchSyncFingerprint(base.host, base.port);
    } on TlsException {
      throw const FormatException(
        'That address did not answer with a secure connection. Update Locus '
        'on the desktop and check the address.',
      );
    }
  }

  /// Pairs with a desktop whose certificate has [fingerprint]. The fingerprint
  /// comes from the desktop's QR code, or from [fetchDesktopFingerprint] after
  /// the user has confirmed it matches. Nothing, including the pairing code, is
  /// sent to a server that presents any other certificate.
  Future<void> pair({
    required String host,
    required String code,
    required String fingerprint,
  }) async {
    final base = _normalizeHost(host);
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty || normalizedCode.length > 32) {
      throw const FormatException('Enter the pairing code shown on desktop.');
    }
    final pin = normalizeFingerprint(fingerprint);
    if (pin == null) {
      throw const FormatException(
        'The desktop fingerprint is not valid. Scan the QR code again.',
      );
    }
    final deviceId = await _db.ensureDeviceIdentity();
    final result = await _request(
      'POST',
      base.resolve('/api/v1/pairing/exchange'),
      body: {
        'code': normalizedCode,
        'deviceId': deviceId,
        'name': 'Locus Android',
      },
      authenticated: false,
      pin: pin,
    );
    final token = result['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException(
        'The desktop returned an invalid pairing response.',
      );
    }
    await _tokenStore.write(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _hostKey,
      base.toString().replaceFirst(RegExp(r'/$'), ''),
    );
    await prefs.setString(_pinKey, pin);
    await prefs.remove(_snapshotKey);
    await prefs.remove(_remoteCursorKey);
    await prefs.setInt(_pushedCursorKey, 0);
    await _storeEpoch(prefs, result['epoch']);
  }

  Future<void> unpair() async {
    await _tokenStore.delete();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hostKey);
    await prefs.remove(_pinKey);
    await prefs.remove(_snapshotKey);
    await prefs.remove(_remoteCursorKey);
    await prefs.remove(_pushedCursorKey);
    await prefs.remove(_epochKey);
  }

  Future<String> syncNow() async {
    try {
      return await _syncOnce();
    } on SyncResyncRequired {
      // The desktop was reset or pruned past this phone's position. Forget the
      // old position and start over from a snapshot; local changes are pushed
      // back, so nothing on the phone is lost. One retry only.
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_snapshotKey);
      await prefs.remove(_remoteCursorKey);
      await prefs.remove(_epochKey);
      final message = await _syncOnce();
      return '$message The desktop data was reset or replaced, so everything '
          'was re-synced.';
    }
  }

  Future<void> _storeEpoch(SharedPreferences prefs, Object? epoch) async {
    if (epoch is String && epoch.isNotEmpty) {
      await prefs.setString(_epochKey, epoch);
    } else {
      await prefs.remove(_epochKey);
    }
  }

  Future<String> _syncOnce() async {
    final prefs = await SharedPreferences.getInstance();
    final token = await _tokenStore.read();
    final hostText = prefs.getString(_hostKey);
    if (token == null || token.isEmpty || hostText == null) {
      throw StateError('Pair this phone with Locus on desktop first.');
    }
    if (prefs.getString(_pinKey) == null) {
      throw StateError(_needsRepairMessage);
    }
    final host = _normalizeHost(hostText);

    // Existing desktop data predates outbox tracking, so take one initial
    // snapshot before exchanging incremental changes.
    if (!(prefs.getBool(_snapshotKey) ?? false)) {
      final snapshot = await _request('GET', host.resolve('/api/v1/snapshot'));
      final raw = snapshot['changes'];
      final cursor = snapshot['cursor'];
      if (raw is! List || cursor is! int) {
        throw const FormatException('Invalid initial sync snapshot.');
      }
      // Capture this phone's own data first. After the snapshot is applied it
      // is sent to the desktop, so rows only the phone has (for example after
      // the desktop was reset) are restored there. Both sides compare row
      // versions, so the newer edit wins either way.
      final localState = await SyncChangeApplier.readFullState(_db);
      await _applyChanges(raw.cast<Map<String, dynamic>>());
      await _storeEpoch(prefs, snapshot['epoch']);
      for (var i = 0; i < localState.length; i += _maxBatch) {
        final end = i + _maxBatch < localState.length
            ? i + _maxBatch
            : localState.length;
        await _request(
          'POST',
          host.resolve('/api/v1/changes/apply'),
          body: {'changes': localState.sublist(i, end)},
        );
      }
      await prefs.setInt(_remoteCursorKey, cursor);
      await prefs.setBool(_snapshotKey, true);
    }

    var pushed = prefs.getInt(_pushedCursorKey) ?? 0;
    var pushedCount = 0;
    while (true) {
      final rows = await _db
          .customSelect(
            'SELECT id, entity_type, entity_id, operation, payload, device_id, created_at '
            'FROM sync_outbox WHERE id > ? ORDER BY id LIMIT ?',
            variables: [Variable.withInt(pushed), Variable.withInt(_maxBatch)],
          )
          .get();
      if (rows.isEmpty) break;
      final changes = rows
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
      await _request(
        'POST',
        host.resolve('/api/v1/changes/apply'),
        body: {'changes': changes},
      );
      pushed = rows.last.read<int>('id');
      await prefs.setInt(_pushedCursorKey, pushed);
      pushedCount += rows.length;
    }
    if (pushed > 0) {
      // Everything up to the pushed cursor is on the desktop; keep the phone's
      // outbox from growing forever.
      await _db.customStatement('DELETE FROM sync_outbox WHERE id <= ?', [
        pushed,
      ]);
    }

    var remoteCursor = prefs.getInt(_remoteCursorKey) ?? 0;
    var pulledCount = 0;
    for (var page = 0; page < 20; page++) {
      final response = await _request(
        'GET',
        host.resolve('/api/v1/changes?after=$remoteCursor&limit=$_maxBatch'),
      );
      final raw = response['changes'];
      final next = response['nextCursor'];
      if (raw is! List || next is! int) {
        throw const FormatException('Invalid changes response from desktop.');
      }
      if (prefs.getString(_epochKey) == null) {
        await _storeEpoch(prefs, response['epoch']);
      }
      final changes = raw.cast<Map<String, dynamic>>();
      if (changes.isNotEmpty) {
        await _applyChanges(changes);
        pulledCount += changes.length;
      }
      remoteCursor = next;
      await prefs.setInt(_remoteCursorKey, remoteCursor);
      await _request(
        'POST',
        host.resolve('/api/v1/changes/ack'),
        body: {'cursor': remoteCursor},
      );
      if (response['hasMore'] != true || changes.isEmpty) break;
    }

    await prefs.setString(
      'locus.sync.last_sync',
      AppClock.now().toIso8601String(),
    );
    return 'Sync complete: $pushedCount sent, $pulledCount received.';
  }

  /// Conflict rules live in [SyncChangeApplier], shared with the desktop
  /// server, so both sides pick the same winner for a row.
  Future<void> _applyChanges(List<Map<String, dynamic>> changes) async {
    await SyncChangeApplier(_db).apply(changes);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? pin,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final pinned = pin ?? prefs.getString(_pinKey);
    if (pinned == null) throw StateError(_needsRepairMessage);
    final client = pinnedSyncHttpClient(pinned);
    try {
      final request = await client
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 12));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) request.headers.contentType = ContentType.json;
      if (authenticated) {
        final token = await _tokenStore.read();
        if (token == null || token.isEmpty)
          throw StateError('Phone is not paired.');
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        // The snapshot is how a mismatch is repaired, so it never sends one.
        if (!uri.path.endsWith('/snapshot')) {
          final epoch = prefs.getString(_epochKey);
          if (epoch != null) request.headers.set(_epochHeader, epoch);
        }
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final text = await utf8.decoder.bind(response).join();
      final decoded = text.isEmpty ? <String, dynamic>{} : jsonDecode(text);
      if (response.statusCode == HttpStatus.conflict &&
          decoded is Map &&
          const {
            'epoch_mismatch',
            'cursor_ahead',
            'resync_required',
          }.contains(decoded['error'])) {
        throw SyncResyncRequired('${decoded['error']}');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['error'] ?? decoded['details']
            : null;
        throw HttpException(
          'Locus sync HTTP ${response.statusCode}${message == null ? '' : ': $message'}',
          uri: uri,
        );
      }
      if (decoded is! Map<String, dynamic>)
        throw const FormatException('Invalid JSON response from desktop.');
      return decoded;
    } on TlsException {
      // The pinned certificate was not presented. Nothing was sent.
      throw const SyncCertificateMismatch();
    } finally {
      client.close(force: true);
    }
  }

  Uri _normalizeHost(String input) {
    var value = input.trim();
    if (value.isEmpty)
      throw const FormatException('Enter the desktop IP address.');
    if (!value.contains('://')) value = 'https://$value';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException(
        'Enter a valid desktop address, e.g. 192.168.1.20:43821.',
      );
    }
    final port = uri.hasPort ? uri.port : 43821;
    if (port < 1 ||
        port > 65535 ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException('Enter a desktop address with a valid port.');
    }
    // Always HTTPS: an http:// address from older instructions is upgraded.
    return Uri(scheme: 'https', host: uri.host, port: port);
  }
}
