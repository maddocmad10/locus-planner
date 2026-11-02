import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../utils/app_clock.dart';
import 'key_derivation.dart';

/// Thrown when an encrypted backup cannot be opened.
class BackupDecryptionException extends FormatException {
  const BackupDecryptionException(super.message);
}

/// One JSON envelope for every encrypted Locus file.
///
/// Version 2 uses AES-256-GCM, PBKDF2-HMAC-SHA256 and NFC-normalized
/// passphrases. The authenticated data covers the format version, payload type,
/// iteration count and normalization, so editing any of those fields makes
/// decryption fail instead of silently changing the interpretation.
class EncryptedEnvelope {
  const EncryptedEnvelope._();

  static const format = 'locus.encrypted';
  static const version = 2;
  static const legacyFormat = 'locus.encrypted-diary';
  static const legacyVersion = 1;
  static const defaultIterations = 210000;
  static const payloadDiary = 'diary';
  static const payloadFullBackup = 'full-backup';
  static const _kdfName = 'PBKDF2-HMAC-SHA256';
  static const _cipherName = 'AES-256-GCM';
  static const _normalization = 'NFC';
  static const _legacyAad = 'locus.encrypted-diary:v1';

  static final _random = Random.secure();

  static String aad(String payloadType, int iterations) =>
      '$format|$version|$payloadType|$iterations|$_normalization';

  static Future<String> seal(
    String plaintext,
    String passphrase, {
    required String payloadType,
    DeriveKey derive = KeyDerivation.derive,
    int iterations = defaultIterations,
  }) async {
    if (passphrase.isEmpty) {
      throw const FormatException('Enter a passphrase for the backup.');
    }
    if (!KeyDerivation.iterationsInRange(iterations)) {
      throw const FormatException('Unsupported encryption settings.');
    }
    final salt = KeyDerivation.randomBytes(16, _random);
    final nonce = KeyDerivation.randomBytes(12, _random);
    final normalized = unorm.nfc(passphrase);
    final key = await derive(normalized, salt, iterations);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(aad(payloadType, iterations))),
        ),
      );
    final ciphertext = cipher.process(
      Uint8List.fromList(utf8.encode(plaintext)),
    );

    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'version': version,
      'payloadType': payloadType,
      'created_at': AppClock.now().toUtc().toIso8601String(),
      'kdf': {
        'algorithm': _kdfName,
        'iterations': iterations,
        'salt': base64Encode(salt),
        'passphraseNormalization': _normalization,
      },
      'cipher': _cipherName,
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(ciphertext),
    });
  }

  static bool looksEncrypted(String text) {
    final decoded = _tryDecode(text);
    if (decoded == null) return false;
    final value = decoded['format'];
    return value == format || value == legacyFormat;
  }

  static Future<({String plaintext, String payloadType})> open(
    String document,
    String passphrase, {
    DeriveKey derive = KeyDerivation.derive,
  }) async {
    final decoded = _tryDecode(document);
    if (decoded == null) {
      throw const BackupDecryptionException(
        'This is not an encrypted Locus backup.',
      );
    }

    final fileFormat = decoded['format'];
    final fileVersion = decoded['version'];
    final isLegacy = fileFormat == legacyFormat && fileVersion == legacyVersion;
    final isCurrent = fileFormat == format && fileVersion == version;
    if (!isLegacy && !isCurrent) {
      throw const BackupDecryptionException(
        'This is not an encrypted Locus backup.',
      );
    }
    if (decoded['cipher'] != _cipherName) {
      throw const BackupDecryptionException('Unsupported encryption settings.');
    }

    final kdf = decoded['kdf'];
    if (kdf is! Map<String, dynamic> || kdf['algorithm'] != _kdfName) {
      throw const BackupDecryptionException('Unsupported encryption settings.');
    }
    final iterations = kdf['iterations'];
    if (iterations is! int || !KeyDerivation.iterationsInRange(iterations)) {
      throw const BackupDecryptionException('Unsupported encryption settings.');
    }

    String payloadType;
    String associatedData;
    String normalizedPassphrase;
    if (isLegacy) {
      payloadType = payloadDiary;
      associatedData = _legacyAad;
      // Version 1 files were written before normalization existed.
      normalizedPassphrase = passphrase;
    } else {
      final rawType = decoded['payloadType'];
      if (rawType != payloadDiary && rawType != payloadFullBackup) {
        throw const BackupDecryptionException('Unsupported backup type.');
      }
      if (kdf['passphraseNormalization'] != _normalization) {
        throw const BackupDecryptionException(
          'Unsupported encryption settings.',
        );
      }
      payloadType = rawType as String;
      associatedData = aad(payloadType, iterations);
      normalizedPassphrase = unorm.nfc(passphrase);
    }

    final salt = _decodeBase64(kdf['salt']);
    final nonce = _decodeBase64(decoded['nonce']);
    final ciphertext = _decodeBase64(decoded['ciphertext']);
    if (salt.length < 16 || nonce.length != 12 || ciphertext.length <= 16) {
      throw const BackupDecryptionException(
        'The encrypted backup is incomplete.',
      );
    }

    final key = await derive(normalizedPassphrase, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(associatedData)),
        ),
      );

    final Uint8List plaintext;
    try {
      plaintext = cipher.process(ciphertext);
    } on InvalidCipherTextException {
      throw const BackupDecryptionException(
        'The passphrase is wrong, or the backup is damaged.',
      );
    }

    try {
      return (plaintext: utf8.decode(plaintext), payloadType: payloadType);
    } on FormatException {
      throw const BackupDecryptionException('The backup is damaged.');
    }
  }

  static Map<String, dynamic>? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on FormatException {
      return null;
    }
  }

  static Uint8List _decodeBase64(Object? value) {
    if (value is! String) {
      throw const BackupDecryptionException(
        'The encrypted backup is incomplete.',
      );
    }
    try {
      return base64Decode(value);
    } on FormatException {
      throw const BackupDecryptionException(
        'The encrypted backup is incomplete.',
      );
    }
  }
}
