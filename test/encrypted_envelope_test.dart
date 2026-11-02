import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/crypto/encrypted_envelope.dart';
import 'package:locus_planner/core/services/crypto/key_derivation.dart';

Future<Uint8List> _derive(
  String secret,
  Uint8List salt,
  int iterations,
) async => KeyDerivation.deriveSync(secret, salt, iterations);

void main() {
  final derive = _derive;

  test('round-trips both payload types', () async {
    for (final type in const [
      EncryptedEnvelope.payloadDiary,
      EncryptedEnvelope.payloadFullBackup,
    ]) {
      final document = await EncryptedEnvelope.seal(
        '{"hello":"$type"}',
        'correct horse battery',
        payloadType: type,
        derive: derive,
      );
      expect(EncryptedEnvelope.looksEncrypted(document), isTrue);
      final opened = await EncryptedEnvelope.open(
        document,
        'correct horse battery',
        derive: derive,
      );
      expect(opened.plaintext, '{"hello":"$type"}');
      expect(opened.payloadType, type);
    }
  });

  test('a wrong passphrase cannot open the envelope', () async {
    final document = await EncryptedEnvelope.seal(
      'secret',
      'correct horse battery',
      payloadType: EncryptedEnvelope.payloadFullBackup,
      derive: derive,
    );
    await expectLater(
      EncryptedEnvelope.open(document, 'wrong horse battery', derive: derive),
      throwsA(
        isA<BackupDecryptionException>().having(
          (error) => error.message,
          'message',
          contains('passphrase is wrong'),
        ),
      ),
    );
  });

  test('tampering with the ciphertext is detected', () async {
    final document = await EncryptedEnvelope.seal(
      'secret',
      'correct horse battery',
      payloadType: EncryptedEnvelope.payloadFullBackup,
      derive: derive,
    );
    final envelope = jsonDecode(document) as Map<String, dynamic>;
    final bytes = base64Decode(envelope['ciphertext'] as String);
    bytes[0] ^= 1;
    envelope['ciphertext'] = base64Encode(bytes);

    await expectLater(
      EncryptedEnvelope.open(
        jsonEncode(envelope),
        'correct horse battery',
        derive: derive,
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test('tampering with the header fails authentication', () async {
    final document = await EncryptedEnvelope.seal(
      'secret',
      'correct horse battery',
      payloadType: EncryptedEnvelope.payloadFullBackup,
      derive: derive,
    );
    final envelope = jsonDecode(document) as Map<String, dynamic>;
    envelope['payloadType'] = EncryptedEnvelope.payloadDiary;

    await expectLater(
      EncryptedEnvelope.open(
        jsonEncode(envelope),
        'correct horse battery',
        derive: derive,
      ),
      throwsA(isA<BackupDecryptionException>()),
    );

    final second = jsonDecode(document) as Map<String, dynamic>;
    (second['kdf'] as Map<String, dynamic>)['iterations'] = 210001;
    await expectLater(
      EncryptedEnvelope.open(
        jsonEncode(second),
        'correct horse battery',
        derive: derive,
      ),
      throwsA(isA<BackupDecryptionException>()),
    );
  });

  test(
    'NFC normalization accepts composed and decomposed passphrases',
    () async {
      final document = await EncryptedEnvelope.seal(
        'secret',
        'café au lait',
        payloadType: EncryptedEnvelope.payloadDiary,
        derive: derive,
      );
      final opened = await EncryptedEnvelope.open(
        document,
        'cafe\u0301 au lait',
        derive: derive,
      );
      expect(opened.plaintext, 'secret');
    },
  );

  test('a version 1 diary file made before the rewrite still opens', () async {
    final document = File(
      'test/fixtures/encrypted/v1_diary.locusdiary',
    ).readAsStringSync();
    final opened = await EncryptedEnvelope.open(
      document,
      'legacy pass',
      derive: derive,
    );
    expect(opened.payloadType, EncryptedEnvelope.payloadDiary);
    final payload = jsonDecode(opened.plaintext) as Map<String, dynamic>;
    expect(payload['format'], 'locus.diary-backup');
    expect(
      (payload['entries'] as List).single['content'],
      'A legacy encrypted diary entry',
    );
  });

  test('opens a file produced independently with Node cryptography', () async {
    final document = File(
      'test/fixtures/encrypted/v2_fullbackup.locusbackup',
    ).readAsStringSync();
    final opened = await EncryptedEnvelope.open(
      document,
      'independent pass',
      derive: derive,
    );
    expect(opened.payloadType, EncryptedEnvelope.payloadFullBackup);
    final payload = jsonDecode(opened.plaintext) as Map<String, dynamic>;
    expect(payload['format_version'], 2);
    expect(payload['note'], 'made independently');
  });

  test('rejects a plain JSON backup', () {
    expect(EncryptedEnvelope.looksEncrypted('{"format_version":2}'), isFalse);
  });
}
