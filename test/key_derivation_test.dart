import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final salt = Uint8List.fromList(utf8.encode('salt'));

  test('PBKDF2-HMAC-SHA256 matches the published vectors', () {
    expect(
      _hex(KeyDerivation.deriveSync('password', salt, 1)),
      '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
    );
    expect(
      _hex(KeyDerivation.deriveSync('password', salt, 2)),
      'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
    );
    expect(
      _hex(KeyDerivation.deriveSync('password', salt, 4096)),
      'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
    );
  });

  test('derive runs off the UI isolate with the same result', () async {
    final sync = KeyDerivation.deriveSync('password', salt, 2);
    final async = await KeyDerivation.derive('password', salt, 2);
    expect(async, sync);
  });

  test('constantTimeEquals compares without throwing on length mismatch', () {
    expect(KeyDerivation.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    expect(KeyDerivation.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    expect(KeyDerivation.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    expect(KeyDerivation.constantTimeEquals(const [], const []), isTrue);
  });

  test('randomBytes returns the requested length and varies', () {
    final a = KeyDerivation.randomBytes(16);
    final b = KeyDerivation.randomBytes(16);
    expect(a, hasLength(16));
    expect(b, hasLength(16));
    expect(a, isNot(b));
  });
}
