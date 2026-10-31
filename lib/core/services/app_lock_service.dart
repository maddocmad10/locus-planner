import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

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
    this.iterations = defaultIterations,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const defaultIterations = 120000;
  static const minPinLength = 4;
  static const maxPinLength = 8;
  static const _formatVersion = 1;

  final AppLockStore store;
  final int iterations;
  final Random _random;

  /// Returns an explanation when [pin] is not a usable app-lock PIN.
  static String? validatePin(String pin) {
    if (!RegExp('^[0-9]{$minPinLength,$maxPinLength}\$').hasMatch(pin)) {
      return 'Use $minPinLength to $maxPinLength digits.';
    }
    return null;
  }

  Future<bool> isEnabled() async {
    final config = _readConfig(await store.read());
    return config != null;
  }

  Future<void> enable(String pin) async {
    final problem = validatePin(pin);
    if (problem != null) throw FormatException(problem);
    final salt = _randomBytes(16);
    final derived = _derive(pin, salt, iterations);
    await store.write(
      jsonEncode({
        'version': _formatVersion,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'hash': base64Encode(derived),
      }),
    );
  }

  Future<bool> verify(String pin) async {
    final config = _readConfig(await store.read());
    if (config == null) return false;
    if (validatePin(pin) != null) return false;
    final derived = _derive(pin, config.salt, config.iterations);
    return _constantTimeEquals(derived, config.hash);
  }

  /// Removes the lock. Throws [InvalidPinException] when [pin] is wrong, so a
  /// caller cannot accidentally turn the lock off after a failed prompt.
  Future<void> disable(String pin) async {
    if (!await verify(pin)) throw const InvalidPinException();
    await store.delete();
  }

  Future<void> changePin(String currentPin, String newPin) async {
    if (!await verify(currentPin)) throw const InvalidPinException();
    await enable(newPin);
  }

  _PinConfig? _readConfig(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != _formatVersion) return null;
      final iterations = decoded['iterations'];
      final salt = decoded['salt'];
      final hash = decoded['hash'];
      if (iterations is! int ||
          iterations < 1000 ||
          iterations > 1000000 ||
          salt is! String ||
          hash is! String) {
        return null;
      }
      final saltBytes = base64Decode(salt);
      final hashBytes = base64Decode(hash);
      if (saltBytes.length < 16 || hashBytes.length != 32) return null;
      return _PinConfig(
        iterations: iterations,
        salt: Uint8List.fromList(saltBytes),
        hash: Uint8List.fromList(hashBytes),
      );
    } catch (_) {
      // A damaged verifier cannot be checked. Treat the lock as absent rather
      // than locking the owner out forever; the next enable() rewrites it.
      return null;
    }
  }

  Uint8List _derive(String pin, Uint8List salt, int rounds) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, rounds, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(pin)));
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

class _PinConfig {
  const _PinConfig({
    required this.iterations,
    required this.salt,
    required this.hash,
  });

  final int iterations;
  final Uint8List salt;
  final Uint8List hash;
}
