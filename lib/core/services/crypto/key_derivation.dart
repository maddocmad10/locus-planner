import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/pbkdf2.dart';
import 'package:pointycastle/macs/hmac.dart';

/// Derives a key from a secret. Production passes [KeyDerivation.derive], which
/// runs off the UI isolate; tests may pass a synchronous wrapper.
typedef DeriveKey =
    Future<Uint8List> Function(String secret, Uint8List salt, int iterations);

/// Shared PBKDF2-HMAC-SHA256 implementation (U1).
///
/// The pure-Dart derivation is kept in [deriveSync] so it can run inside an
/// isolate. Only plain values (String, Uint8List, int) cross the boundary.
class KeyDerivation {
  const KeyDerivation._();

  /// Encryption iteration limits. Every encrypted file and PIN verifier uses
  /// these bounds, so a damaged header cannot ask for a cheap or absurd KDF.
  static const minIterations = 100000;
  static const maxIterations = 2000000;

  static bool iterationsInRange(int iterations) =>
      iterations >= minIterations && iterations <= maxIterations;

  static Uint8List deriveSync(
    String secret,
    Uint8List salt,
    int iterations, {
    int length = 32,
  }) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, length));
    return derivator.process(Uint8List.fromList(utf8.encode(secret)));
  }

  /// Runs [deriveSync] on a worker isolate so PBKDF2 never blocks the UI.
  static Future<Uint8List> derive(
    String secret,
    Uint8List salt,
    int iterations, {
    int length = 32,
  }) => Isolate.run(() => deriveSync(secret, salt, iterations, length: length));

  /// Compares two byte sequences without an early exit that could leak how many
  /// leading bytes matched.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static Uint8List randomBytes(int length, [Random? random]) {
    final source = random ?? Random.secure();
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = source.nextInt(256);
    }
    return bytes;
  }
}
