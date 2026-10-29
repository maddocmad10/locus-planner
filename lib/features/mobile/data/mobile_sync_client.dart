import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../../../core/services/sync_change_applier.dart';
import '../../../core/services/sync_discovery.dart';
import '../../../core/services/sync_outbox_pruner.dart';
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

/// Looks for the desktop with the given pinned certificate fingerprint on the
/// local network. Tests substitute a fake.
typedef DesktopLocator =
    Future<DiscoveredDesktop?> Function(String fingerprint);

Future<DiscoveredDesktop?> _locateDesktop(String fingerprint) =>
    discoverDesktop(fingerprint: fingerprint);

/// Android-side client for the desktop LAN sync API. The bearer token is kept
/// in Android Keystore-backed secure storage; only non-secret settings/cursors
/// use SharedPreferences.
class MobileSyncClient {
  /// [locator] finds the desktop again when its address has changed; it
  /// defaults to a UDP broadcast on the local network (see [discoverDesktop]).
  MobileSyncClient(
    this._db, {
    this._tokenStore = const SecureSyncTokenStore(),
    this._locator = _locateDesktop,
  });

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
  // Keep requests comfortably below the desktop server's 1 MiB body limit.
  static const _maxBatchBytes = 512 * 1024;
  static const _needsRepairMessage =
      'Locus sync now uses a verified, encrypted connection. Pair this phone '
      'with the desktop again, scanning the QR code in desktop Settings.';
  final SyncTokenStore _tokenStore;
  final DesktopLocator _locator;

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

  /// Clears this phone's outbox while it has no desktop to send changes to.
  ///
  /// An unpaired phone has nowhere to push its changes, so keeping them only
  /// grows the database and retains deleted diary text. A paired phone is
  /// never pruned here: its outbox holds changes the desktop has not received.
  /// A phone paired with the old plain-HTTP version ([MobileSyncStatus
  /// .needsRepair]) still has its bearer token and unsent changes, so it is
  /// left alone until it pairs again (pairing resets its cursors and takes a
  /// snapshot).
  Future<void> pruneOutboxIfUnpaired() async {
    final current = await status();
    if (current.paired || current.needsRepair) return;
    await SyncOutboxPruner(_db).clearAll();
  }

  /// Syncs now. If the desktop cannot be reached, the phone asks the local
  /// network where the desktop with the pinned certificate went, and tries
  /// once more at its new address (see [_rediscoverDesktop]).
  Future<String> syncNow() async {
    try {
      return await _syncRecovering();
    } catch (error) {
      if (!_mayHaveMoved(error)) rethrow;
      final moved = await _rediscoverDesktop();
      if (moved == null) rethrow;
      final message = await _syncRecovering();
      return '$message The desktop is now at $moved; the saved address was '
          'updated.';
    }
  }

  /// Syncs only if the last sync is older than [minInterval] and the phone is
  /// paired; returns null when it did nothing. Meant for syncing in the
  /// background of normal use, such as when the app is opened.
  Future<String?> syncIfDue({
    Duration minInterval = const Duration(minutes: 1),
  }) async {
    final current = await status();
    if (!current.paired) return null;
    final last = current.lastSync;
    if (last != null && AppClock.now().difference(last) < minInterval) {
      return null;
    }
    return syncNow();
  }

  /// A desktop that does not answer, or answers with another certificate, may
  /// simply have a new address (and the old one may now belong to another
  /// device).
  bool _mayHaveMoved(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error is SyncCertificateMismatch;

  /// Asks the network for the desktop with the pinned fingerprint. If it is
  /// found somewhere other than the saved address, saves the new address and
  /// returns it; otherwise returns null. The connection that follows is still
  /// pinned to the same certificate, so a wrong answer cannot redirect the
  /// phone's data to another machine.
  Future<String?> _rediscoverDesktop() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    final hostText = prefs.getString(_hostKey);
    if (pin == null || hostText == null) return null;
    final found = await _locator(pin);
    if (found == null) return null;
    final current = _normalizeHost(hostText);
    if (found.host == current.host && found.port == current.port) return null;
    await prefs.setString(_hostKey, 'https://${found.host}:${found.port}');
    return '${found.host}:${found.port}';
  }

  Future<String> _syncRecovering() async {
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
      // Capture this phone's own data before applying the desktop snapshot.
      // If transfer is interrupted, _snapshotKey remains false and replaying
      // pages is safe because sync versions make applying the same row twice
      // idempotent.
      final localState = await SyncChangeApplier.readFullState(_db);
      var offset = 0;
      // Resume token from the previous page. It names the last row sent, so a
      // row deleted earlier in the transfer cannot shift an unsent row past a
      // page boundary. Older desktops do not return one; then paging falls
      // back to offsets exactly as before.
      String? after;
      int? snapshotCursor;
      Object? snapshotEpoch;
      while (true) {
        final requestedAfter = after;
        final query = <String, String>{
          'limit': '100',
          'after': ?requestedAfter,
          if (requestedAfter == null) 'offset': '$offset',
          if (snapshotCursor != null) 'cursor': '$snapshotCursor',
        };
        final snapshot = await _request(
          'GET',
          host.resolve('/api/v1/snapshot').replace(queryParameters: query),
        );
        final raw = snapshot['changes'];
        final cursor = snapshot['cursor'];
        final nextOffset = snapshot['nextOffset'];
        if (raw is! List ||
            cursor is! int ||
            nextOffset is! int ||
            nextOffset < 0 ||
            snapshot['hasMore'] is! bool) {
          throw const FormatException('Invalid initial sync snapshot page.');
        }
        if (snapshotCursor == null) {
          snapshotCursor = cursor;
          snapshotEpoch = snapshot['epoch'];
          await _storeEpoch(prefs, snapshotEpoch);
        } else if (cursor != snapshotCursor ||
            snapshot['epoch'] != snapshotEpoch) {
          throw const FormatException(
            'The desktop snapshot changed during transfer.',
          );
        }
        final page = raw.cast<Map<String, dynamic>>();
        if (page.isNotEmpty) await _applyChanges(page);
        if (snapshot['hasMore'] != true) break;
        final nextAfter = snapshot['nextAfter'];
        if (nextAfter is String && nextAfter.isNotEmpty) {
          if (nextAfter == requestedAfter) {
            throw const FormatException(
              'The desktop returned the same snapshot page twice.',
            );
          }
          after = nextAfter;
        } else if (requestedAfter == null &&
            page.isNotEmpty &&
            nextOffset > offset) {
          // A desktop that predates resume tokens.
          offset = nextOffset;
        } else {
          throw const FormatException(
            'The desktop returned an empty snapshot page.',
          );
        }
      }
      // Restore rows that existed only on the phone (for example after the
      // desktop was reset). Both sides compare row versions, so this is safe
      // to repeat if a later request fails before the snapshot is committed.
      for (final batch in _splitIntoBatches(localState)) {
        await _request(
          'POST',
          host.resolve('/api/v1/changes/apply'),
          body: {'changes': batch},
        );
      }
      await prefs.setInt(_remoteCursorKey, snapshotCursor);
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
      var offset = 0;
      for (final batch in _splitIntoBatches(changes)) {
        await _request(
          'POST',
          host.resolve('/api/v1/changes/apply'),
          body: {'changes': batch},
        );
        // Advance only through rows accepted by the desktop. If a later batch
        // fails, the next sync resumes at that batch instead of losing it.
        pushed = rows[offset + batch.length - 1].read<int>('id');
        await prefs.setInt(_pushedCursorKey, pushed);
        pushedCount += batch.length;
        offset += batch.length;
      }
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
      if (response['hasMore'] != true) break;
    }

    await prefs.setString(
      'locus.sync.last_sync',
      AppClock.now().toIso8601String(),
    );
    return 'Sync complete: $pushedCount sent, $pulledCount received.';
  }

  /// Splits changes by both row count and encoded request size. The size
  /// calculation includes the JSON envelope sent to the server.
  List<List<Map<String, dynamic>>> _splitIntoBatches(
    List<Map<String, dynamic>> changes,
  ) {
    final batches = <List<Map<String, dynamic>>>[];
    var current = <Map<String, dynamic>>[];

    for (final change in changes) {
      final candidate = [...current, change];
      final encodedSize = utf8
          .encode(jsonEncode({'changes': candidate}))
          .length;
      if (encodedSize > _maxBatchBytes || candidate.length > _maxBatch) {
        if (current.isEmpty) {
          throw StateError(
            'A single sync change is too large to send safely. Shorten or '
            'remove the oversized record, then try syncing again.',
          );
        }
        batches.add(current);
        current = <Map<String, dynamic>>[];
        final singleSize = utf8
            .encode(
              jsonEncode({
                'changes': [change],
              }),
            )
            .length;
        if (singleSize > _maxBatchBytes) {
          throw StateError(
            'A single sync change is too large to send safely. Shorten or '
            'remove the oversized record, then try syncing again.',
          );
        }
        current.add(change);
      } else {
        current.add(change);
      }
    }

    if (current.isNotEmpty) batches.add(current);
    return batches;
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
        if (token == null || token.isEmpty) {
          throw StateError('Phone is not paired.');
        }
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
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid JSON response from desktop.');
      }
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
    if (value.isEmpty) {
      throw const FormatException('Enter the desktop IP address.');
    }
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
