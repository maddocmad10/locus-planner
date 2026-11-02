import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/app_clock.dart';
import 'crypto/key_derivation.dart';
import 'error_log_service.dart';

/// Where the app-lock PIN verifier lives.
///
/// Production uses the operating system's protected storage (Android Keystore,
/// Windows DPAPI), so copying the SQLite file does not copy the lock. Tests
/// substitute an in-memory store.
abstract interface class AppLockStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureAppLockStore implements AppLockStore {
  const SecureAppLockStore();

  static const _key = 'locus.app_lock.pin';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Public settings the lock UI needs.
class AppLockSettings {
  const AppLockSettings({
    required this.enabled,
    required this.autoLockSeconds,
    this.damaged = false,
  });

  final bool enabled;

  /// 0 means "lock as soon as the app is left". Default is one minute.
  final int autoLockSeconds;

  /// The stored verifier could not be read or understood. The lock is treated
  /// as off (fail open) and the UI should tell the user to set a new PIN.
  final bool damaged;
}

/// Result of a PIN check.
sealed class PinCheck {
  const PinCheck();
}

class PinAccepted extends PinCheck {
  const PinAccepted();
}

class PinWrong extends PinCheck {
  const PinWrong({this.triesBeforeWait, this.lockedUntil});

  /// How many attempts remain before a wait starts; null once waits have begun.
  final int? triesBeforeWait;

  /// Set on the attempt that starts a wait.
  final DateTime? lockedUntil;
}

class PinLockedOut extends PinCheck {
  const PinLockedOut(this.until);

  final DateTime until;
}

/// Thrown when a PIN change or removal is attempted with the wrong PIN.
class InvalidPinException implements Exception {
  const InvalidPinException();

  @override
  String toString() => 'That PIN is not correct.';
}

/// Stores a salted PBKDF2-HMAC-SHA256 verifier for the app-lock PIN.
///
/// The PIN itself is never written anywhere. It is deliberately not stored in
/// the database, so it is excluded from backups, LAN sync and the full JSON
/// export; restoring a backup on another machine does not silently add or
/// remove a lock there.
class AppLockService {
  AppLockService({
    this.store = const SecureAppLockStore(),
    this.derive = KeyDerivation.derive,
    this.iterations = defaultIterations,
    Random? random,
    DateTime Function()? clock,
  }) : _random = random ?? Random.secure(),
       _clock = clock ?? AppClock.now;

  static const defaultIterations = 120000;
  static const defaultAutoLockSeconds = 60;
  static const minPinLength = 4;
  static const maxPinLength = 8;
  static const failuresBeforeWait = 5;
  static const firstWaitSeconds = 30;
  static const maxWaitSeconds = 15 * 60;
  static const _formatVersion = 2;
  static const _legacyFormatVersion = 1;
  static const _defaultSaltLength = 16;
  static const _hashLength = 32;

  static const damagedNotice =
      'The app lock record was damaged and the lock was turned off. '
      'Set a new PIN.';

  final AppLockStore store;
  final DeriveKey derive;
  final int iterations;
  final Random _random;
  final DateTime Function() _clock;

  bool _damaged = false;

  /// Returns an explanation when [pin] is not a usable app-lock PIN.
  static String? validatePin(String pin) {
    if (!RegExp('^[0-9]{$minPinLength,$maxPinLength}\$').hasMatch(pin)) {
      return 'Use $minPinLength to $maxPinLength digits.';
    }
    return null;
  }

  Future<bool> isEnabled() async {
    final config = _readConfig(await _readRaw());
    return config != null;
  }

  Future<AppLockSettings> settings() async {
    _damaged = false;
    final config = _readConfig(await _readRaw());
    return AppLockSettings(
      enabled: config != null,
      autoLockSeconds: config?.autoLockSeconds ?? defaultAutoLockSeconds,
      damaged: _damaged,
    );
  }

  Future<void> enable(
    String pin, {
    int autoLockSeconds = defaultAutoLockSeconds,
  }) async {
    final problem = validatePin(pin);
    if (problem != null) throw FormatException(problem);
    final salt = KeyDerivation.randomBytes(_defaultSaltLength, _random);
    final derived = await derive(pin, salt, iterations);
    final now = _clock().millisecondsSinceEpoch;
    _damaged = false;
    await _write(
      _PinConfig(
        version: _formatVersion,
        iterations: iterations,
        salt: salt,
        hash: derived,
        autoLockSeconds: _validAutoLock(autoLockSeconds),
        failures: 0,
        lockedUntilMs: null,
        lastSeenMs: now,
      ),
    );
  }

  /// Checks [pin], applying the persisted attempt limit. A lock-out is returned
  /// without deriving a key, so guessing cannot burn through attempts.
  Future<PinCheck> verify(String pin) async {
    final config = _readConfig(await _readRaw());
    if (config == null) return const PinWrong();
    if (validatePin(pin) != null) return const PinWrong();

    final nowMs = _nowMs(config.lastSeenMs);
    final lockedUntilMs = config.lockedUntilMs;
    if (lockedUntilMs != null && nowMs < lockedUntilMs) {
      return PinLockedOut(DateTime.fromMillisecondsSinceEpoch(lockedUntilMs));
    }

    final derived = await derive(pin, config.salt, config.iterations);
    if (KeyDerivation.constantTimeEquals(derived, config.hash)) {
      // A legacy record, a cleared counter and the moved clock are all
      // rewritten on success, upgrading v1 records in place.
      await _write(
        _PinConfig(
          version: _formatVersion,
          iterations: config.iterations,
          salt: config.salt,
          hash: config.hash,
          autoLockSeconds: config.autoLockSeconds,
          failures: 0,
          lockedUntilMs: null,
          lastSeenMs: nowMs,
        ),
      );
      return const PinAccepted();
    }

    final failures = config.failures + 1;
    int? nextLockedUntil;
    if (failures >= failuresBeforeWait) {
      final exponent = (failures - failuresBeforeWait).clamp(0, 10);
      final multiplier = 1 << exponent;
      final seconds = min(firstWaitSeconds * multiplier, maxWaitSeconds);
      nextLockedUntil = nowMs + seconds * 1000;
    }
    // Persist before returning so killing the app cannot reset the count.
    await _write(
      _PinConfig(
        version: _formatVersion,
        iterations: config.iterations,
        salt: config.salt,
        hash: config.hash,
        autoLockSeconds: config.autoLockSeconds,
        failures: failures,
        lockedUntilMs: nextLockedUntil,
        lastSeenMs: nowMs,
      ),
    );
    return PinWrong(
      triesBeforeWait: failures < failuresBeforeWait
          ? failuresBeforeWait - failures
          : null,
      lockedUntil: nextLockedUntil == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextLockedUntil),
    );
  }

  /// Removes the lock. Throws [InvalidPinException] when [pin] is wrong or the
  /// lock is currently rate limited.
  Future<void> disable(String pin) async {
    if (await verify(pin) is! PinAccepted) {
      throw const InvalidPinException();
    }
    await store.delete();
  }

  Future<void> changePin(String currentPin, String newPin) async {
    final problem = validatePin(newPin);
    if (problem != null) throw FormatException(problem);
    final config = _readConfig(await _readRaw());
    if (config == null) throw const InvalidPinException();
    if (await verify(currentPin) is! PinAccepted) {
      throw const InvalidPinException();
    }
    final salt = KeyDerivation.randomBytes(_defaultSaltLength, _random);
    final derived = await derive(newPin, salt, iterations);
    await _write(
      _PinConfig(
        version: _formatVersion,
        iterations: iterations,
        salt: salt,
        hash: derived,
        autoLockSeconds: config.autoLockSeconds,
        failures: 0,
        lockedUntilMs: null,
        lastSeenMs: _clock().millisecondsSinceEpoch,
      ),
    );
  }

  Future<void> updateAutoLockSeconds(int seconds) async {
    final config = _readConfig(await _readRaw());
    if (config == null) throw const InvalidPinException();
    await _write(
      _PinConfig(
        version: _formatVersion,
        iterations: config.iterations,
        salt: config.salt,
        hash: config.hash,
        autoLockSeconds: _validAutoLock(seconds),
        failures: config.failures,
        lockedUntilMs: config.lockedUntilMs,
        lastSeenMs: config.lastSeenMs,
      ),
    );
  }

  static int _validAutoLock(int seconds) {
    if (seconds <= 0) return 0;
    return seconds.clamp(0, 24 * 60 * 60);
  }

  int _nowMs(int? lastSeenMs) {
    final now = _clock().millisecondsSinceEpoch;
    if (lastSeenMs == null) return now;
    // Moving the system clock backwards must not shorten a lock-out.
    return max(now, lastSeenMs);
  }

  Future<String?> _readRaw() async {
    try {
      return await store.read();
    } catch (error, stack) {
      _damaged = true;
      await ErrorLogService.log(error, stack);
      return null;
    }
  }

  Future<void> _write(_PinConfig config) =>
      store.write(jsonEncode(config.toJson()));

  _PinConfig? _readConfig(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('App lock record is not an object.');
      }
      final version = decoded['version'];
      if (version is! int ||
          (version != _formatVersion && version != _legacyFormatVersion)) {
        throw FormatException('Unsupported app lock record version $version.');
      }
      final iterations = decoded['iterations'];
      final salt = decoded['salt'];
      final hash = decoded['hash'];
      if (iterations is! int ||
          iterations < 1000 ||
          iterations > 1000000 ||
          salt is! String ||
          hash is! String) {
        throw const FormatException('App lock record is incomplete.');
      }
      final saltBytes = base64Decode(salt);
      final hashBytes = base64Decode(hash);
      if (saltBytes.length < _defaultSaltLength ||
          hashBytes.length != _hashLength) {
        throw const FormatException('App lock verifier has the wrong size.');
      }
      final autoLockSeconds = decoded['autoLockSeconds'];
      final failures = decoded['failures'];
      final lockedUntilMs = decoded['lockedUntilMs'];
      final lastSeenMs = decoded['lastSeenMs'];
      return _PinConfig(
        version: version,
        iterations: iterations,
        salt: Uint8List.fromList(saltBytes),
        hash: Uint8List.fromList(hashBytes),
        autoLockSeconds: autoLockSeconds is int
            ? _validAutoLock(autoLockSeconds)
            : defaultAutoLockSeconds,
        failures: failures is int && failures >= 0 ? failures : 0,
        lockedUntilMs: lockedUntilMs is int ? lockedUntilMs : null,
        lastSeenMs: lastSeenMs is int ? lastSeenMs : null,
      );
    } catch (error, stack) {
      _damaged = true;
      unawaited(
        ErrorLogService.log(
          StateError('The app lock record could not be read: $error'),
          stack,
        ),
      );
      // A damaged verifier cannot be checked. Treat the lock as absent rather
      // than locking the owner out forever; the next enable() rewrites it.
      return null;
    }
  }
}

class _PinConfig {
  const _PinConfig({
    required this.version,
    required this.iterations,
    required this.salt,
    required this.hash,
    required this.autoLockSeconds,
    required this.failures,
    required this.lockedUntilMs,
    required this.lastSeenMs,
  });

  final int version;
  final int iterations;
  final Uint8List salt;
  final Uint8List hash;
  final int autoLockSeconds;
  final int failures;
  final int? lockedUntilMs;
  final int? lastSeenMs;

  Map<String, dynamic> toJson() => {
    'version': version,
    'iterations': iterations,
    'salt': base64Encode(salt),
    'hash': base64Encode(hash),
    'autoLockSeconds': autoLockSeconds,
    'failures': failures,
    'lockedUntilMs': lockedUntilMs,
    'lastSeenMs': lastSeenMs,
  };
}
