import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/db/app_database.dart';
import '../../../core/services/attachments/attachment_images.dart';
import '../../../core/services/attachments/attachment_store.dart';
import '../../../core/services/attachments/attachment_types.dart';
import '../../../core/services/lan_sync_server.dart';
import '../../../core/services/sync_change_applier.dart';
import '../../../core/services/sync_discovery.dart';
import '../../../core/services/sync_outbox_pruner.dart';
import '../../../core/services/sync_receipt_store.dart';
import '../../../core/services/sync_tls.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';

final mobileSyncClientProvider = Provider<MobileSyncClient>((ref) {
  return MobileSyncClient(
    ref.watch(databaseProvider),
    storeLoader: () => ref.read(attachmentStoreProvider.future),
  );
});

class _PushReceipt {
  const _PushReceipt({
    required this.outcome,
    this.reason,
    this.revision,
    this.counter,
    this.operation,
  });

  final String outcome;
  final String? reason;
  final int? revision;
  final int? counter;
  final String? operation;
}

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
    this.storeLoader,
  });

  final AppDatabase _db;
  final Future<AttachmentStore> Function()? storeLoader;
  static const _hostKey = 'locus.sync.host';

  /// SHA-256 fingerprint of the desktop certificate pinned at pairing. It is
  /// public information, so it lives with the other non-secret settings.
  static const _pinKey = 'locus.sync.pin';
  static const _snapshotKey = 'locus.sync.snapshot_done';
  static const _remoteCursorKey = 'locus.sync.remote_cursor';
  static const _pushedCursorKey = 'locus.sync.pushed_cursor';
  static const _epochKey = 'locus.sync.server_epoch';
  static const _tokenExpiryKey = 'locus.sync.token_expires';
  static const _peerIdKey = 'locus.sync.peer_device_id';
  static const _epochHeader = 'X-Locus-Epoch';
  static const _maxBatch = 100;
  // Keep requests comfortably below the desktop server's 1 MiB body limit.
  static const _maxBatchBytes = 512 * 1024;
  final _skewSamples = <int>[];
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
    if (result['serverDeviceId'] is String) {
      await prefs.setString(_peerIdKey, result['serverDeviceId'] as String);
    }
    final expires = result['tokenExpiresAt'];
    if (expires is String) {
      await prefs.setString(_tokenExpiryKey, expires);
    }
    await _db.setSetting(AppDatabase.syncRebaseRequiredSettingKey, '0');
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
    await prefs.remove(_peerIdKey);
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
    if (await _db.getSetting(AppDatabase.syncRebaseRequiredSettingKey) == '1') {
      await unpair();
      return 'This database was restored. Pair this phone with the desktop '
          'again using the QR code in desktop Settings.';
    }
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

  Future<void> _maybeRotateToken(Uri host, SharedPreferences prefs) async {
    final raw = prefs.getString(_tokenExpiryKey);
    final expiry = raw == null ? null : DateTime.tryParse(raw);
    if (expiry == null) return;
    final remaining = expiry.difference(AppClock.now().toUtc());
    if (remaining > const Duration(days: 14)) return;
    try {
      final result = await _request(
        'POST',
        host.resolve('/api/v1/token/rotate'),
      );
      final token = result['token'];
      if (token is String && token.isNotEmpty) {
        await _tokenStore.write(token);
      }
      final next = result['tokenExpiresAt'];
      if (next is String) await prefs.setString(_tokenExpiryKey, next);
    } catch (_) {
      // An older desktop has no rotation endpoint. Keep the current token.
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
    await _maybeRotateToken(host, prefs);

    final status = await _serverStatus(host);
    final deviceId = await _db.ensureDeviceIdentity();
    final receiptStore = SyncReceiptStore(_db);
    var epoch =
        (status?['epoch'] as String?) ?? prefs.getString(_epochKey) ?? '';
    final peerId =
        (status?['serverDeviceId'] as String?) ??
        prefs.getString(_peerIdKey) ??
        host.authority;
    final pairedPeer = prefs.getString(_peerIdKey);
    if (pairedPeer != null &&
        status?['serverDeviceId'] is String &&
        pairedPeer != status!['serverDeviceId']) {
      throw StateError(
        'The desktop identity at this address changed. Re-pair this phone '
        'before syncing; local work is kept.',
      );
    }

    // Existing desktop data predates outbox tracking, so take one initial
    // snapshot before exchanging incremental changes. The capture is staged in
    // SQLite under a stable snapshot id and resumes after a process kill.
    if (!(prefs.getBool(_snapshotKey) ?? false)) {
      var session = await receiptStore.latestSnapshotSession(
        peerId: peerId,
        epoch: epoch,
      );
      if (session == null) {
        final localState = await SyncChangeApplier.readFullState(_db);
        final snapshotId = 'snap_${AppClock.now().microsecondsSinceEpoch}';
        await receiptStore.createSnapshotSession(
          snapshotId: snapshotId,
          peerId: peerId,
          epoch: epoch,
          // A new bootstrap has no trusted pre-deletion checkpoint on the
          // phone, so phone-only rows must be reviewed rather than uploaded.
          trustedBaselineServerMs: null,
        );
        final captured =
            <({String changeId, int ordinal, String payloadJson})>[];
        for (var index = 0; index < localState.length; index++) {
          final change = localState[index];
          final type = change['entityType'];
          final id = change['entityId'];
          final operation = change['operation'];
          final payload = change['payload'];
          final versionKey = type is String
              ? SyncChangeApplier.versionKeyFor(type)
              : null;
          final revision = payload is Map && versionKey != null
              ? payload[versionKey]
              : null;
          final counter = payload is Map && payload['hlc_counter'] is int
              ? payload['hlc_counter'] as int
              : 0;
          final changeId =
              'snapshot:$snapshotId:$type:$id:$operation:$revision:$counter';
          captured.add((
            changeId: changeId,
            ordinal: index,
            payloadJson: jsonEncode({...change, 'changeId': changeId}),
          ));
        }
        await receiptStore.saveSnapshotItems(snapshotId, captured);
        session = await receiptStore.latestSnapshotSession(
          peerId: peerId,
          epoch: epoch,
        );
        if (session == null) {
          throw StateError('Could not stage the initial sync snapshot.');
        }
      }

      final snapshotId = session['snapshot_id'] as String;
      var sessionEpoch = '${session['epoch']}';
      var snapshotCursor = session['remote_cursor'] is int
          ? session['remote_cursor'] as int
          : null;
      var after = session['resume_token'] as String?;
      var offset = 0;
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
        if (sessionEpoch.isEmpty &&
            snapshot['epoch'] is String &&
            (snapshot['epoch'] as String).isNotEmpty) {
          sessionEpoch = snapshot['epoch'] as String;
          epoch = sessionEpoch;
        } else if (snapshot['epoch'] != sessionEpoch) {
          await receiptStore.updateSnapshotSession(
            snapshotId: snapshotId,
            phase: 'stale',
          );
          throw const FormatException(
            'The desktop snapshot epoch changed; local work was kept.',
          );
        }
        snapshotCursor = cursor;
        await _storeEpoch(prefs, sessionEpoch);
        final page = raw.cast<Map<String, dynamic>>();
        final pageKeys = <String>{};
        for (final change in page) {
          final type = change['entityType'];
          final id = change['entityId'];
          if (type is String && id is String) pageKeys.add('$type:$id');
        }
        if (pageKeys.isNotEmpty) {
          await receiptStore.markSnapshotItemsOnDesktop(snapshotId, pageKeys);
        }
        if (page.isNotEmpty) {
          await _applyChanges(
            page,
            peerId: peerId,
            epoch: sessionEpoch,
            direction: 'pull',
          );
        }
        await receiptStore.updateSnapshotSession(
          snapshotId: snapshotId,
          remoteCursor: snapshotCursor,
        );
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
          offset = nextOffset;
        } else {
          throw const FormatException(
            'The desktop returned an empty snapshot page.',
          );
        }
        await receiptStore.updateSnapshotSession(
          snapshotId: snapshotId,
          resumeToken: after,
        );
      }
      await receiptStore.updateSnapshotSession(
        snapshotId: snapshotId,
        phase: 'upload',
      );

      final baseline = session['trusted_baseline_server_ms'];
      final horizon = status?['tombstoneHorizonMs'] is int
          ? status!['tombstoneHorizonMs'] as int
          : null;
      final ambiguousHistory =
          horizon != null &&
          horizon > 0 &&
          (baseline is! int || baseline < horizon);
      if (ambiguousHistory) {
        final capturedItems = await receiptStore.snapshotItems(snapshotId);
        for (final item in capturedItems) {
          if (item['disposition'] != 'pending') continue;
          final decoded = jsonDecode(item['payload_json'] as String);
          if (decoded is! Map<String, dynamic>) continue;
          final type = decoded['entityType'];
          final id = decoded['entityId'];
          if (type is String &&
              id is String &&
              (item['desktop_present'] as int? ?? 0) == 0) {
            await receiptStore.markSnapshotItem(
              snapshotId: snapshotId,
              changeId: item['change_id'] as String,
              disposition: 'review',
              reason: 'phone_only_after_reset',
            );
          }
        }
      }

      // Upload the frozen capture, consuming an exact receipt per row. Only a
      // pending row keeps the session open.
      final items = await receiptStore.snapshotItems(snapshotId);
      final pending = [
        for (final item in items)
          if (item['disposition'] == 'pending') item,
      ];
      final changes = <Map<String, dynamic>>[];
      for (final item in pending) {
        final decoded = jsonDecode(item['payload_json'] as String);
        if (decoded is Map<String, dynamic>) changes.add(decoded);
      }
      var allAccounted = true;
      for (final batch in _splitIntoBatches(changes)) {
        final response = await _request(
          'POST',
          host.resolve('/api/v1/changes/apply'),
          body: {'changes': batch},
        );
        final outcomes = _readReceipts(response, batch);
        final needsAttention = outcomes.values.any(
          (outcome) =>
              outcome.outcome == 'rejected' || outcome.outcome == 'unsupported',
        );
        await _recordPushReceipts(
          receiptStore,
          peerId: peerId,
          epoch: sessionEpoch,
          changes: batch,
          outcomes: outcomes,
          clean: !needsAttention,
          cursor: null,
        );
        for (final change in batch) {
          final changeId = change['changeId'] as String?;
          if (changeId == null) continue;
          final outcome = outcomes[changeId];
          if (outcome == null) {
            allAccounted = false;
            continue;
          }
          await receiptStore.markSnapshotItem(
            snapshotId: snapshotId,
            changeId: changeId,
            disposition: outcome.outcome,
            reason: outcome.reason,
          );
        }
      }
      if (!allAccounted) {
        throw StateError(
          'The snapshot upload was interrupted; the captured rows will '
          'resume on the next sync.',
        );
      }
      final reviewCount = items
          .where((item) => item['disposition'] == 'review')
          .length;
      if (reviewCount > 0) {
        throw StateError(
          '$reviewCount local-only item'
          '${reviewCount == 1 ? '' : 's'} need reconciliation before the '
          'snapshot can finish.',
        );
      }
      await receiptStore.completeSnapshotSession(snapshotId);
      await prefs.setInt(_remoteCursorKey, snapshotCursor);
      await prefs.setBool(_snapshotKey, true);
    }

    final store = await _storeOrNull();
    var uploadedCount = 0;
    if (status != null && store != null) {
      uploadedCount = await _uploadLocalBlobs(host, status, store);
    }

    await receiptStore.recoverLegacyCursors(
      peerId: peerId,
      epoch: epoch,
      pushCursor: prefs.getInt(_pushedCursorKey) ?? 0,
      pullCursor: prefs.getInt(_remoteCursorKey) ?? 0,
    );

    var pushed = prefs.getInt(_pushedCursorKey) ?? 0;
    var pushedCount = 0;
    pushLoop:
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
            final outboxId = data['id'] as int;
            return <String, dynamic>{
              'id': outboxId,
              'changeId': '$deviceId/$outboxId',
              'entityType': data['entity_type'],
              'entityId': data['entity_id'],
              'operation': data['operation'],
              'payload': jsonDecode(data['payload'] as String),
              'deviceId': data['device_id'],
              'originDeviceId': data['device_id'],
              'createdAt': data['created_at'],
            };
          })
          .toList(growable: false);
      for (final batch in _splitIntoBatches(changes)) {
        final response = await _request(
          'POST',
          host.resolve('/api/v1/changes/apply'),
          body: {'changes': batch},
        );
        final outcomes = _readReceipts(response, batch);
        await _db.setSetting(
          AppDatabase.syncPeerUpdateNeededSettingKey,
          response['receipts'] is List ? '0' : '1',
        );
        final expectedIds = [
          for (final change in batch)
            if (change['changeId'] is String) change['changeId'] as String,
        ];
        final answeredPrefix = <Map<String, dynamic>>[];
        for (final change in batch) {
          final changeId = change['changeId'] as String?;
          if (changeId == null || !outcomes.containsKey(changeId)) break;
          answeredPrefix.add(change);
        }
        final rejected = outcomes.values.any(
          (outcome) => outcome.outcome == 'rejected',
        );
        final prefixCursor = answeredPrefix.isEmpty
            ? null
            : answeredPrefix.last['id'] as int?;
        await _recordPushReceipts(
          receiptStore,
          peerId: peerId,
          epoch: epoch,
          changes: batch,
          outcomes: outcomes,
          clean: !rejected,
          cursor: prefixCursor,
        );
        // A confirmed outcome is durable even when it was rejected: the repair
        // record keeps the original revision for review.
        final confirmed = <int>{
          for (final change in batch)
            if (outcomes.containsKey(change['changeId'] as String? ?? ''))
              change['id'] as int,
        };
        if (confirmed.isNotEmpty) {
          final placeholders = List.filled(confirmed.length, '?').join(', ');
          await _db.customStatement(
            'DELETE FROM sync_outbox WHERE id IN ($placeholders)',
            confirmed.toList(growable: false),
          );
        }
        if (answeredPrefix.length != expectedIds.length) {
          // Keep the cursor before the first unanswered change so a retry
          // sends it again instead of silently skipping it.
          if (prefixCursor != null) {
            pushed = prefixCursor;
            await prefs.setInt(_pushedCursorKey, pushed);
          }
          pushedCount += answeredPrefix.length;
          break pushLoop;
        }
        pushed = prefixCursor!;
        await prefs.setInt(_pushedCursorKey, pushed);
        pushedCount += answeredPrefix.length;
      }
    }

    // Retry durable repairs with the exact original envelope. A missing
    // parent often arrives in this same exchange, so this runs after the
    // normal outbox push.
    await _retryPushRepairs(
      host: host,
      peerId: peerId,
      epoch: epoch,
      receiptStore: receiptStore,
    );

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
      final pageEpoch = prefs.getString(_epochKey) ?? '';
      final changes = _prepareChanges(
        raw.cast<Map<String, dynamic>>(),
        peerId: peerId,
        epoch: pageEpoch,
      );
      var pageClean = true;
      if (changes.isNotEmpty) {
        final result = await SyncChangeApplier(_db).apply(
          changes,
          receiptContext: SyncReceiptContext(
            peerId: peerId,
            epoch: pageEpoch,
            direction: 'pull',
          ),
        );
        pageClean = !result.receipts.any(
          (receipt) => receipt.outcome == 'rejected',
        );
        pulledCount += changes.length;
      }
      remoteCursor = next;
      if (response['serverTimeMs'] is int) {
        await receiptStore.noteTrustedServerTime(
          peerId: peerId,
          epoch: pageEpoch,
          serverTimeMs: response['serverTimeMs'] as int,
        );
      }
      // Persist the cursor before acknowledging it to the desktop.
      await receiptStore.noteExchange(
        peerId: peerId,
        epoch: pageEpoch,
        direction: 'pull',
        cursor: remoteCursor,
        clean: pageClean,
        errorCode: pageClean ? null : 'changes_need_attention',
      );
      await prefs.setInt(_remoteCursorKey, remoteCursor);
      await _request(
        'POST',
        host.resolve('/api/v1/changes/ack'),
        body: {'cursor': remoteCursor},
      );
      if (response['hasMore'] != true) break;
    }

    var downloadedCount = 0;
    if (status != null && store != null) {
      downloadedCount = await _downloadReferencedBlobs(host, status, store);
    }

    await prefs.setString(
      'locus.sync.last_sync',
      AppClock.now().toIso8601String(),
    );
    final attachmentNote = uploadedCount == 0 && downloadedCount == 0
        ? ''
        : ', $uploadedCount files uploaded, $downloadedCount downloaded';
    return 'Sync complete: $pushedCount sent, $pulledCount received'
        '$attachmentNote.';
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
  Future<void> _applyChanges(
    List<Map<String, dynamic>> changes, {
    String? peerId,
    String? epoch,
    String direction = 'pull',
  }) async {
    if (peerId == null || epoch == null) {
      await SyncChangeApplier(_db).apply(changes);
      return;
    }
    await SyncChangeApplier(_db).apply(
      _prepareChanges(changes, peerId: peerId, epoch: epoch),
      receiptContext: SyncReceiptContext(
        peerId: peerId,
        epoch: epoch,
        direction: direction,
      ),
    );
  }

  /// Gives every change a repeatable receipt key. Incremental rows use the
  /// origin stream and outbox id; snapshot rows use the tuple from §3.
  List<Map<String, dynamic>> _prepareChanges(
    List<Map<String, dynamic>> changes, {
    required String peerId,
    required String epoch,
  }) {
    return [
      for (final change in changes)
        if (change['changeId'] is String)
          change
        else
          <String, dynamic>{
            ...change,
            'changeId': _changeKey(change, peerId: peerId, epoch: epoch),
          },
    ];
  }

  String _changeKey(
    Map<String, dynamic> change, {
    required String peerId,
    required String epoch,
  }) {
    final id = change['id'];
    if (id is int) return '$peerId/$id';
    final type = change['entityType'];
    final entityId = change['entityId'];
    final payload = change['payload'];
    var version = '';
    var counter = 0;
    if (payload is Map) {
      final versionKey = type is String
          ? SyncChangeApplier.versionKeyFor(type)
          : null;
      if (versionKey != null && payload[versionKey] is int) {
        version = '${payload[versionKey]}';
      }
      if (payload['hlc_counter'] is int) {
        counter = payload['hlc_counter'] as int;
      }
    }
    return 'snapshot:$epoch:$type:$entityId:$version:$counter';
  }

  Map<String, _PushReceipt> _readReceipts(
    Map<String, dynamic> response,
    List<Map<String, dynamic>> batch,
  ) {
    final raw = response['receipts'];
    final outcomes = <String, _PushReceipt>{};
    if (raw is List) {
      for (final item in raw.whereType<Map>()) {
        final changeId = item['changeId'];
        final outcome = item['outcome'];
        if (changeId is! String || outcome is! String) continue;
        final receipt = _PushReceipt(
          outcome: outcome,
          reason: item['reason'] is String ? item['reason'] as String : null,
          revision: item['revision'] is int ? item['revision'] as int : null,
          counter: item['counter'] is int ? item['counter'] as int : null,
          operation: item['operation'] is String
              ? item['operation'] as String
              : null,
        );
        final prior = outcomes[changeId];
        if (prior != null &&
            (prior.outcome != receipt.outcome ||
                prior.reason != receipt.reason)) {
          // Duplicate contradictory receipts acknowledge nothing.
          outcomes.remove(changeId);
          continue;
        }
        outcomes[changeId] = receipt;
      }
      // A receipt bound to another revision or operation is not this request.
      for (final change in batch) {
        final changeId = change['changeId'] as String?;
        final receipt = changeId == null ? null : outcomes[changeId];
        if (receipt == null) continue;
        final payload = change['payload'];
        final type = change['entityType'];
        final versionKey = type is String
            ? SyncChangeApplier.versionKeyFor(type)
            : null;
        final revision = payload is Map && versionKey != null
            ? payload[versionKey]
            : null;
        final counter = payload is Map && payload['hlc_counter'] is int
            ? payload['hlc_counter'] as int
            : 0;
        if ((receipt.revision != null &&
                revision is int &&
                receipt.revision != revision) ||
            (receipt.counter != null && receipt.counter != counter) ||
            (receipt.operation != null &&
                receipt.operation != change['operation'])) {
          outcomes.remove(changeId);
        }
      }
      return outcomes;
    }

    // Older desktops do not echo receipts. Match any returned rejection by
    // entity conservatively: when two edits to the same entity cannot be told
    // apart, keep both for reconciliation instead of guessing one.
    final rejected = response['rejected'];
    final rejectedTypes = <String, Set<String>>{};
    if (rejected is List) {
      for (final item in rejected.whereType<Map>()) {
        final type = item['entityType'];
        final id = item['entityId'];
        final reason = item['reason'];
        if (type is String && id is String) {
          rejectedTypes.putIfAbsent(type, () => <String>{}).add(id);
          outcomes['legacy:$type:$id'] = _PushReceipt(
            outcome: 'rejected',
            reason: reason is String ? reason : 'rejected',
          );
        }
      }
    }
    for (final change in batch) {
      final changeId = change['changeId'] as String?;
      if (changeId == null) continue;
      final type = change['entityType'];
      final id = change['entityId'];
      final ambiguous =
          rejectedTypes[type]?.contains(id) == true &&
          batch
                  .where((c) => c['entityType'] == type && c['entityId'] == id)
                  .length >
              1;
      final rejection = rejectedTypes[type]?.contains(id) == true;
      if (rejection || ambiguous) {
        outcomes[changeId] = const _PushReceipt(
          outcome: 'rejected',
          reason: 'rejected_by_peer',
        );
      }
      // No per-change receipt means the request is unanswered. It stays in the
      // outbox and the UI asks the user to update the peer.
    }
    return outcomes;
  }

  Future<void> _retryPushRepairs({
    required Uri host,
    required String peerId,
    required String epoch,
    required SyncReceiptStore receiptStore,
  }) async {
    final repairs = await receiptStore.openRepairPayloads(
      peerId: peerId,
      epoch: epoch,
      direction: 'push',
    );
    if (repairs.isEmpty) return;
    for (final batch in _splitIntoBatches(repairs)) {
      final response = await _request(
        'POST',
        host.resolve('/api/v1/changes/apply'),
        body: {'changes': batch},
      );
      final outcomes = _readReceipts(response, batch);
      final now = AppClock.now().millisecondsSinceEpoch;
      for (final change in batch) {
        final changeId = change['changeId'] as String?;
        if (changeId == null) continue;
        final outcome = outcomes[changeId];
        if (outcome == null) continue;
        final needsAttention =
            outcome.outcome == 'rejected' || outcome.outcome == 'unsupported';
        if (needsAttention) {
          await _db.customStatement(
            'UPDATE sync_rejected_changes SET attempts = attempts + 1, '
            'last_seen_ms = ?, last_attempt_ms = ?, reason_code = ? '
            'WHERE peer_id = ? AND epoch = ? AND direction = ? '
            'AND change_id = ? AND resolved_ms IS NULL',
            [
              now,
              now,
              outcome.reason ?? 'rejected',
              peerId,
              epoch,
              'push',
              changeId,
            ],
          );
        } else {
          await _db.customStatement(
            'UPDATE sync_rejected_changes SET resolved_ms = ?, '
            'resolution_kind = ?, last_attempt_ms = ? '
            'WHERE peer_id = ? AND epoch = ? AND direction = ? '
            'AND change_id = ? AND resolved_ms IS NULL',
            [now, outcome.outcome, now, peerId, epoch, 'push', changeId],
          );
        }
      }
    }
  }

  Future<void> _recordPushReceipts(
    SyncReceiptStore store, {
    required String peerId,
    required String epoch,
    required List<Map<String, dynamic>> changes,
    required Map<String, _PushReceipt> outcomes,
    required bool clean,
    required int? cursor,
  }) async {
    final now = AppClock.now().millisecondsSinceEpoch;
    for (final change in changes) {
      final changeId = change['changeId'] as String?;
      if (changeId == null) continue;
      final outcome = outcomes[changeId];
      if (outcome == null) continue;
      final needsAttention =
          outcome.outcome == 'rejected' || outcome.outcome == 'unsupported';
      final payloadSha256 = sha256
          .convert(utf8.encode(jsonEncode(change['payload'])))
          .toString();
      await _db.customStatement(
        'INSERT INTO sync_change_receipts '
        '(peer_id, epoch, direction, change_id, payload_sha256, revision, '
        'counter, operation, outcome, reason, first_seen_ms, last_seen_ms) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(peer_id, epoch, direction, change_id) DO UPDATE SET '
        'outcome = excluded.outcome, reason = excluded.reason, '
        'last_seen_ms = excluded.last_seen_ms',
        [
          peerId,
          epoch,
          'push',
          changeId,
          payloadSha256,
          outcome.revision,
          outcome.counter,
          outcome.operation,
          outcome.outcome,
          outcome.reason,
          now,
          now,
        ],
      );
      if (!needsAttention) {
        await _db.customStatement(
          'UPDATE sync_rejected_changes SET resolved_ms = ?, '
          'resolution_kind = ?, last_attempt_ms = ? '
          'WHERE peer_id = ? AND epoch = ? AND direction = ? '
          'AND change_id = ? AND resolved_ms IS NULL',
          [now, outcome.outcome, now, peerId, epoch, 'push', changeId],
        );
        continue;
      }
      await _db.customStatement(
        'INSERT INTO sync_rejected_changes '
        '(peer_id, epoch, direction, change_id, entity_type, entity_id, '
        'operation, payload_json, reason_code, attempts, first_seen_ms, '
        'last_seen_ms, resolved_ms, last_attempt_ms, payload_sha256) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL, ?, ?) '
        'ON CONFLICT(peer_id, epoch, direction, change_id) DO UPDATE SET '
        'attempts = sync_rejected_changes.attempts + 1, '
        'last_seen_ms = excluded.last_seen_ms, '
        'last_attempt_ms = excluded.last_attempt_ms, '
        'reason_code = excluded.reason_code, '
        'resolved_ms = NULL',
        [
          peerId,
          epoch,
          'push',
          changeId,
          change['entityType'],
          change['entityId'],
          change['operation'],
          jsonEncode(change),
          outcome.reason ?? 'rejected',
          now,
          now,
          now,
          payloadSha256,
        ],
      );
    }
    await store.noteExchange(
      peerId: peerId,
      epoch: epoch,
      direction: 'push',
      cursor: cursor,
      clean: clean,
      errorCode: clean ? null : 'changes_need_attention',
    );
  }

  /// Downloads one missing attachment from the paired desktop. Exposed for
  /// the placeholder tile's Download action; returns false when offline or
  /// when the desktop does not advertise attachments.
  Future<bool> downloadAttachment(
    String sha256Hex, {
    required String kind,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final hostText = prefs.getString(_hostKey);
    if (hostText == null || prefs.getString(_pinKey) == null) return false;
    final store = await _storeOrNull();
    if (store == null) return false;
    if (await store.hasBlob(sha256Hex)) return true;
    final status = await _serverStatus(_normalizeHost(hostText));
    if (status == null || !_supportsAttachments(status)) return false;
    return _downloadBlob(_normalizeHost(hostText), store, sha256Hex, kind);
  }

  /// Pins a blob so the phone cache eviction pass keeps it.
  Future<void> pinAttachment(String sha256Hex, bool pinned) async {
    await _db.customStatement(
      'INSERT INTO attachment_blobs (sha256, size_bytes, state, pinned) '
      "VALUES (?, 0, 'missing', ?) "
      'ON CONFLICT(sha256) DO UPDATE SET pinned = excluded.pinned',
      [sha256Hex, pinned ? 1 : 0],
    );
  }

  Future<AttachmentStore?> _storeOrNull() async {
    final loader = storeLoader;
    if (loader == null) return null;
    try {
      final store = await loader();
      await store.ensureLayout();
      return store;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _serverStatus(Uri host) async {
    try {
      return await _request('GET', host.resolve('/api/v1/status'));
    } on HttpException {
      // An older desktop has no status route; metadata-only sync still works.
      return null;
    }
  }

  bool _supportsAttachments(Map<String, dynamic> status) {
    final features = status['features'];
    return features is List &&
        features.contains(LanSyncServer.featureAttachments) &&
        status['blobsAvailable'] == true;
  }

  Future<int> _uploadLocalBlobs(
    Uri host,
    Map<String, dynamic> status,
    AttachmentStore store,
  ) async {
    if (!_supportsAttachments(status)) return 0;
    final maxBlob = status['maxBlobBytes'] is int
        ? status['maxBlobBytes'] as int
        : LanSyncServer.maxBlobBytes;
    final rows = await _db
        .customSelect('SELECT DISTINCT sha256 FROM attachments')
        .get();
    final hashes = <String>[];
    for (final row in rows) {
      final hash = row.read<String>('sha256');
      if (await store.hasBlob(hash)) hashes.add(hash);
    }
    var uploaded = 0;
    for (var start = 0; start < hashes.length; start += 200) {
      final end = (start + 200).clamp(0, hashes.length);
      final batch = hashes.sublist(start, end);
      final response = await _request(
        'POST',
        host.resolve('/api/v1/blobs/missing'),
        body: {'hashes': batch},
      );
      final missing = response['missing'];
      if (missing is! List) continue;
      for (final hash in missing.whereType<String>()) {
        final bytes = await store.readBytes(hash);
        if (bytes.length > maxBlob) continue;
        await _putBlob(host, hash, bytes);
        uploaded++;
      }
    }
    return uploaded;
  }

  Future<void> _putBlob(Uri host, String hash, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    final token = await _tokenStore.read();
    if (pin == null || token == null || token.isEmpty) {
      throw StateError('Phone is not paired.');
    }
    final client = pinnedSyncHttpClient(pin);
    try {
      final request = await client
          .openUrl('PUT', host.resolve('/api/v1/blobs/$hash'))
          .timeout(const Duration(seconds: 12));
      request.headers
        ..contentType = ContentType.binary
        ..contentLength = bytes.length
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final epoch = prefs.getString(_epochKey);
      if (epoch != null) request.headers.set(_epochHeader, epoch);
      request.add(bytes);
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      await response.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Blob upload failed with HTTP ${response.statusCode}',
          uri: request.uri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _downloadReferencedBlobs(
    Uri host,
    Map<String, dynamic> status,
    AttachmentStore store,
  ) async {
    if (!_supportsAttachments(status)) return 0;
    final policy = await _downloadPolicy();
    if (policy == AttachmentRules.downloadPolicyManual) return 0;
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT sha256, kind, size_bytes FROM attachments',
        )
        .get();
    var downloaded = 0;
    for (final row in rows) {
      final hash = row.read<String>('sha256');
      if (await store.hasBlob(hash)) {
        await _touchBlob(hash);
        continue;
      }
      final kind = row.read<String>('kind');
      final size = row.read<int>('size_bytes');
      if (policy == AttachmentRules.downloadPolicyAuto &&
          kind == 'image' &&
          size > AttachmentRules.autoDownloadMaxImageBytes) {
        continue;
      }
      if (await _downloadBlob(host, store, hash, kind)) downloaded++;
    }
    await _evictCache(store);
    return downloaded;
  }

  Future<String> _downloadPolicy() async {
    final value = await _db.getSetting(
      AttachmentRules.downloadPolicySettingKey,
    );
    if (value == AttachmentRules.downloadPolicyAll ||
        value == AttachmentRules.downloadPolicyManual ||
        value == AttachmentRules.downloadPolicyAuto) {
      return value!;
    }
    return AttachmentRules.downloadPolicyAuto;
  }

  Future<bool> _downloadBlob(
    Uri host,
    AttachmentStore store,
    String hash,
    String kind,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    final token = await _tokenStore.read();
    if (pin == null || token == null || token.isEmpty) return false;
    final temporary = await store.partialDownloadFile(hash);
    for (var attempt = 0; attempt < 2; attempt++) {
      HttpClient? client;
      try {
        final existing = await temporary.exists()
            ? await temporary.length()
            : 0;
        client = pinnedSyncHttpClient(pin);
        final request = await client
            .openUrl('GET', host.resolve('/api/v1/blobs/$hash'))
            .timeout(const Duration(seconds: 12));
        request.headers
          ..set(HttpHeaders.authorizationHeader, 'Bearer $token')
          ..set(HttpHeaders.acceptHeader, 'application/octet-stream');
        final epoch = prefs.getString(_epochKey);
        if (epoch != null) request.headers.set(_epochHeader, epoch);
        if (existing > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$existing-');
        }
        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );
        if (response.statusCode == HttpStatus.ok) {
          if (existing > 0) await temporary.writeAsBytes(const []);
        } else if (response.statusCode == HttpStatus.partialContent) {
          if (existing == 0) await temporary.writeAsBytes(const []);
        } else if (response.statusCode !=
            HttpStatus.requestedRangeNotSatisfiable) {
          throw HttpException(
            'Blob download failed with HTTP ${response.statusCode}',
            uri: request.uri,
          );
        }
        if (response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
          final sink = temporary.openWrite(mode: FileMode.append);
          try {
            await for (final chunk in response.timeout(
              const Duration(seconds: 30),
            )) {
              sink.add(chunk);
            }
          } finally {
            await sink.flush();
            await sink.close();
          }
        }
        final bytes = await temporary.readAsBytes();
        if (bytes.isEmpty || sha256.convert(bytes).toString() != hash) {
          throw const FormatException('Downloaded attachment hash mismatch.');
        }
        await store.putBytes(bytes);
        final hasThumb = kind == 'image'
            ? await _makeThumbnail(store, hash, bytes)
            : false;
        await _recordBlobPresent(hash, bytes.length, hasThumb: hasThumb);
        await temporary.delete();
        return true;
      } catch (_) {
        if (attempt == 1) {
          await _recordBlobFailure(hash);
          return false;
        }
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      } finally {
        client?.close(force: true);
      }
    }
    return false;
  }

  Future<bool> _makeThumbnail(
    AttachmentStore store,
    String hash,
    Uint8List bytes,
  ) async {
    try {
      final processed = await processImageBytes(bytes, keepOriginal: true);
      if (processed.isSuccess && processed.thumbnail != null) {
        await store.putThumb(hash, processed.thumbnail!);
        return true;
      }
    } catch (_) {
      // A missing thumbnail still leaves the full image usable.
    }
    return false;
  }

  Future<void> _recordBlobPresent(
    String hash,
    int size, {
    required bool hasThumb,
  }) async {
    await _db
        .into(_db.attachmentBlobs)
        .insertOnConflictUpdate(
          AttachmentBlobsCompanion.insert(
            sha256: hash,
            sizeBytes: size,
            state: const Value('present'),
            hasThumb: Value(hasThumb),
            lastAccessedAt: Value(AppClock.now()),
            orphanedAt: const Value(null),
            failCount: const Value(0),
          ),
        );
  }

  Future<void> _recordBlobFailure(String hash) async {
    await _db.customStatement(
      'INSERT INTO attachment_blobs '
      '(sha256, size_bytes, state, has_thumb, pinned, fail_count) '
      "VALUES (?, 0, 'failed', 0, 0, 1) "
      'ON CONFLICT(sha256) DO UPDATE SET '
      "fail_count = fail_count + 1, "
      "state = CASE WHEN fail_count + 1 >= 3 THEN 'failed' ELSE 'missing' END",
      [hash],
    );
  }

  Future<void> _touchBlob(String hash) async {
    await _db.customStatement(
      'UPDATE attachment_blobs SET last_accessed_at = ? '
      'WHERE sha256 = ? AND orphaned_at IS NULL',
      [AppClock.now().millisecondsSinceEpoch, hash],
    );
  }

  Future<void> _evictCache(AttachmentStore store) async {
    if (await store.totalBlobBytes() <= AttachmentRules.phoneCacheCapBytes) {
      return;
    }
    final rows = await _db
        .customSelect(
          'SELECT sha256 FROM attachment_blobs '
          'WHERE pinned = 0 ORDER BY '
          'COALESCE(last_accessed_at, 0) ASC',
        )
        .get();
    var total = await store.totalBlobBytes();
    for (final row in rows) {
      if (total <= AttachmentRules.phoneCacheCapBytes) break;
      final hash = row.read<String>('sha256');
      final length = await store.blobLength(hash);
      await store.deleteBlob(hash);
      await _db.customStatement(
        "UPDATE attachment_blobs SET state = 'missing', has_thumb = 0 "
        'WHERE sha256 = ?',
        [hash],
      );
      if (length != null) total -= length;
    }
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
      await _recordServerTime(decoded);
      return decoded;
    } on TlsException {
      // The pinned certificate was not presented. Nothing was sent.
      throw const SyncCertificateMismatch();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _recordServerTime(Map<String, dynamic> response) async {
    final server = response['serverTimeMs'];
    if (server is! int) return;
    final sample = server - AppClock.now().millisecondsSinceEpoch;
    _skewSamples.add(sample);
    if (_skewSamples.length > 5) _skewSamples.removeAt(0);
    final sorted = [..._skewSamples]..sort();
    final median = sorted[sorted.length ~/ 2];
    // A pinned desktop is trusted, but do not let a bad sample shift local
    // edits by an implausible amount.
    final bounded = median.clamp(-3600000, 3600000);
    await _db.setSetting(AppDatabase.syncClockSkewMsSettingKey, '$bounded');
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
