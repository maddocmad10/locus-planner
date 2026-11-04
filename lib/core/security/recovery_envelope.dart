import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../services/crypto/key_derivation.dart';
import '../utils/app_clock.dart';
import 'database_metadata.dart';
import 'database_security_errors.dart';

class RecoveryEntry {
  const RecoveryEntry({
    required this.purpose,
    required this.iterations,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
  });

  final String purpose;
  final int iterations;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List ciphertext;
  final Uint8List tag;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'purpose': purpose,
    'kdf': <String, dynamic>{
      'algorithm': RecoveryEnvelopeService.kdfName,
      'iterations': iterations,
      'salt': base64Encode(salt),
      'passphraseNormalization': RecoveryEnvelopeService.normalization,
    },
    'cipher': RecoveryEnvelopeService.cipherName,
    'nonce': base64Encode(nonce),
    'ciphertext': base64Encode(ciphertext),
    'tag': base64Encode(tag),
  };

  static RecoveryEntry decode(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'A recovery entry must be an object.',
      );
    }
    final purpose = value['purpose'];
    final kdf = value['kdf'];
    if (purpose is! String || kdf is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'A recovery entry is incomplete.',
      );
    }
    if (value['cipher'] != RecoveryEnvelopeService.cipherName ||
        kdf['algorithm'] != RecoveryEnvelopeService.kdfName ||
        kdf['passphraseNormalization'] !=
            RecoveryEnvelopeService.normalization) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'Unsupported recovery entry settings.',
      );
    }
    final iterations = kdf['iterations'];
    if (iterations is! int || !KeyDerivation.iterationsInRange(iterations)) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'Unsupported recovery KDF settings.',
      );
    }
    return RecoveryEntry(
      purpose: purpose,
      iterations: iterations,
      salt: _decode(kdf['salt']),
      nonce: _decode(value['nonce']),
      ciphertext: _decode(value['ciphertext']),
      tag: _decode(value['tag']),
    );
  }

  static Uint8List _decode(Object? value) {
    if (value is! String) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'A recovery entry is incomplete.',
      );
    }
    try {
      return base64Decode(value);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'A recovery entry is damaged.',
        cause: error,
      );
    }
  }
}

class RecoveryBundle {
  const RecoveryBundle({
    required this.databaseId,
    required this.keyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    required this.createdAt,
    required this.entries,
  });

  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final DateTime createdAt;
  final List<RecoveryEntry> entries;

  RecoveryEntry? entryFor(String purpose) {
    for (final entry in entries) {
      if (entry.purpose == purpose) return entry;
    }
    return null;
  }

  /// Whether this bundle still describes the active database key.
  ///
  /// After a DEK rotation an older bundle remains valid material for the
  /// pre-rotation database, but it must not be presented as current recovery
  /// material for the live database.
  bool isCurrentFor(DatabaseMetadata metadata) =>
      databaseId == metadata.databaseId &&
      keyId == metadata.activeKeyId &&
      keyGeneration == metadata.keyGeneration &&
      cipherProfileId == metadata.cipherProfileId;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': RecoveryEnvelopeService.format,
    'formatVersion': RecoveryEnvelopeService.formatVersion,
    'databaseId': databaseId,
    'keyId': keyId,
    'keyGeneration': keyGeneration,
    'cipherProfileId': cipherProfileId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static RecoveryBundle decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != RecoveryEnvelopeService.format ||
        decoded['formatVersion'] != RecoveryEnvelopeService.formatVersion) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'This is not a supported Locus recovery bundle.',
      );
    }
    final entries = decoded['entries'];
    if (entries is! List || entries.isEmpty) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle has no entries.',
      );
    }
    final createdAt = decoded['createdAt'];
    final databaseId = decoded['databaseId'];
    final keyId = decoded['keyId'];
    final keyGeneration = decoded['keyGeneration'];
    final cipherProfileId = decoded['cipherProfileId'];
    if (databaseId is! String ||
        keyId is! String ||
        keyGeneration is! int ||
        cipherProfileId is! String ||
        createdAt is! String) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle is incomplete.',
      );
    }
    final created = DateTime.tryParse(createdAt);
    if (created == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle has an invalid creation time.',
      );
    }
    return RecoveryBundle(
      databaseId: databaseId,
      keyId: keyId,
      keyGeneration: keyGeneration,
      cipherProfileId: cipherProfileId,
      createdAt: created,
      entries: entries.map(RecoveryEntry.decode).toList(),
    );
  }
}

class OpenedRecoveryBundle {
  const OpenedRecoveryBundle({
    required this.dek,
    required this.databaseId,
    required this.keyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    this.backupPassphrase,
  });

  final Uint8List dek;
  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final String? backupPassphrase;
}

/// Versioned recovery bundle with per-purpose AES-256-GCM entries.
///
/// The recovery passphrase is never stored.  The bundle wraps the DEK and,
/// optionally, the automatic-backup passphrase.  Every identifying field is
/// bound as associated data, so an edited or swapped bundle fails
/// authentication instead of silently opening a different database.
abstract final class RecoveryEnvelopeService {
  static const format = 'locus.db.recovery';
  static const formatVersion = 2;
  static const purposeDek = 'database-dek';
  static const purposeBackupCredential = 'backup-credential';
  static const kdfName = 'PBKDF2-HMAC-SHA256';
  static const cipherName = 'AES-256-GCM';
  static const normalization = 'NFC';

  /// Benchmarked default. Never lower than the existing backup floor of
  /// 210,000 iterations; tests may inject a smaller documented value.
  static const defaultIterations = 600000;

  static String aad({
    required String purpose,
    required String databaseId,
    required String keyId,
    required int keyGeneration,
    required String cipherProfileId,
    int? backupFormatVersion,
  }) {
    final parts = <String>[
      format,
      formatVersion.toString(),
      purpose,
      databaseId,
      keyId,
      keyGeneration.toString(),
      cipherProfileId,
      if (backupFormatVersion != null) 'backup-format:$backupFormatVersion',
    ];
    return parts.join('|');
  }

  static Future<RecoveryBundle> seal({
    required Uint8List dek,
    required String databaseId,
    required String keyId,
    required int keyGeneration,
    required String cipherProfileId,
    required String passphrase,
    String? backupPassphrase,
    int? backupFormatVersion,
    int iterations = defaultIterations,
    DeriveKey derive = KeyDerivation.derive,
    DateTime? createdAt,
  }) async {
    if (dek.length != 32) {
      throw const FormatException('A database key must be 32 bytes.');
    }
    if (passphrase.isEmpty) {
      throw const FormatException('Enter a recovery passphrase.');
    }
    final entries = <RecoveryEntry>[
      await _sealEntry(
        purpose: purposeDek,
        plaintext: dek,
        passphrase: passphrase,
        aad: aad(
          purpose: purposeDek,
          databaseId: databaseId,
          keyId: keyId,
          keyGeneration: keyGeneration,
          cipherProfileId: cipherProfileId,
        ),
        iterations: iterations,
        derive: derive,
      ),
    ];
    if (backupPassphrase != null && backupPassphrase.isNotEmpty) {
      entries.add(
        await _sealEntry(
          purpose: purposeBackupCredential,
          plaintext: Uint8List.fromList(utf8.encode(backupPassphrase)),
          passphrase: passphrase,
          aad: aad(
            purpose: purposeBackupCredential,
            databaseId: databaseId,
            keyId: keyId,
            keyGeneration: keyGeneration,
            cipherProfileId: cipherProfileId,
            backupFormatVersion: backupFormatVersion,
          ),
          iterations: iterations,
          derive: derive,
        ),
      );
    }
    return RecoveryBundle(
      databaseId: databaseId,
      keyId: keyId,
      keyGeneration: keyGeneration,
      cipherProfileId: cipherProfileId,
      createdAt: createdAt ?? AppClock.now().toUtc(),
      entries: entries,
    );
  }

  /// Unwraps the DEK and, when present, the backup credential.
  ///
  /// A wrong passphrase or an edited AAD surfaces as
  /// [DatabaseSecurityErrorCode.unlockFailed]; the caller must not fall back to
  /// "try another credential".
  static Future<OpenedRecoveryBundle> open(
    RecoveryBundle bundle,
    String passphrase, {
    int? backupFormatVersion,
    DeriveKey derive = KeyDerivation.derive,
  }) async {
    final dekEntry = bundle.entryFor(purposeDek);
    if (dekEntry == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle does not contain a database key.',
      );
    }
    final dek = await _openEntry(
      dekEntry,
      passphrase,
      aad(
        purpose: purposeDek,
        databaseId: bundle.databaseId,
        keyId: bundle.keyId,
        keyGeneration: bundle.keyGeneration,
        cipherProfileId: bundle.cipherProfileId,
      ),
      derive,
    );
    if (dek.length != 32) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovered database key has the wrong length.',
      );
    }

    String? backupPassphrase;
    final backupEntry = bundle.entryFor(purposeBackupCredential);
    if (backupEntry != null) {
      final bytes = await _openEntry(
        backupEntry,
        passphrase,
        aad(
          purpose: purposeBackupCredential,
          databaseId: bundle.databaseId,
          keyId: bundle.keyId,
          keyGeneration: bundle.keyGeneration,
          cipherProfileId: bundle.cipherProfileId,
          backupFormatVersion: backupFormatVersion,
        ),
        derive,
      );
      try {
        backupPassphrase = utf8.decode(bytes);
      } on FormatException catch (error) {
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.unlockFailed,
          'The recovered backup credential is damaged.',
          cause: error,
        );
      }
    }

    return OpenedRecoveryBundle(
      dek: dek,
      databaseId: bundle.databaseId,
      keyId: bundle.keyId,
      keyGeneration: bundle.keyGeneration,
      cipherProfileId: bundle.cipherProfileId,
      backupPassphrase: backupPassphrase,
    );
  }

  /// Verifies that a freshly-created bundle unwraps to [expectedDek] before
  /// the user is told recovery is configured.
  static Future<void> verify({
    required RecoveryBundle bundle,
    required String passphrase,
    required Uint8List expectedDek,
    int? backupFormatVersion,
    DeriveKey derive = KeyDerivation.derive,
  }) async {
    final opened = await open(
      bundle,
      passphrase,
      backupFormatVersion: backupFormatVersion,
      derive: derive,
    );
    if (!KeyDerivation.constantTimeEquals(opened.dek, expectedDek)) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery bundle did not reproduce the active database key.',
      );
    }
  }

  static Future<RecoveryEntry> _sealEntry({
    required String purpose,
    required Uint8List plaintext,
    required String passphrase,
    required String aad,
    required int iterations,
    required DeriveKey derive,
  }) async {
    if (!KeyDerivation.iterationsInRange(iterations)) {
      throw const FormatException('Unsupported encryption settings.');
    }
    final salt = KeyDerivation.randomBytes(16);
    final nonce = KeyDerivation.randomBytes(12);
    final normalized = unorm.nfc(passphrase);
    final key = await derive(normalized, salt, iterations);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(utf8.encode(aad)),
        ),
      );
    final output = cipher.process(plaintext);
    if (output.length < 16) {
      throw StateError('AES-GCM produced an invalid payload.');
    }
    final split = output.length - 16;
    return RecoveryEntry(
      purpose: purpose,
      iterations: iterations,
      salt: salt,
      nonce: nonce,
      ciphertext: Uint8List.sublistView(output, 0, split),
      tag: Uint8List.sublistView(output, split),
    );
  }

  static Future<Uint8List> _openEntry(
    RecoveryEntry entry,
    String passphrase,
    String aad,
    DeriveKey derive,
  ) async {
    if (entry.salt.length < 16 ||
        entry.nonce.length != 12 ||
        entry.tag.length != 16) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery entry is incomplete.',
      );
    }
    final normalized = unorm.nfc(passphrase);
    final key = await derive(normalized, entry.salt, entry.iterations);
    final combined = Uint8List(entry.ciphertext.length + entry.tag.length)
      ..setAll(0, entry.ciphertext)
      ..setAll(entry.ciphertext.length, entry.tag);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          entry.nonce,
          Uint8List.fromList(utf8.encode(aad)),
        ),
      );
    try {
      return cipher.process(combined);
    } on InvalidCipherTextException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'The recovery passphrase is wrong, or the bundle is damaged.',
        cause: error,
      );
    }
  }
}
