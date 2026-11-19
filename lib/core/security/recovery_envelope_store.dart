import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/attachments/attachment_key_store.dart';
import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';
import 'recovery_envelope.dart';

/// Versioned recovery envelopes kept under the app data directory.
///
/// Each write creates a new file. Older files are renamed with a `retired-`
/// prefix instead of being overwritten, so a passphrase change or DEK rotation
/// never destroys the previous recovery material.
class RecoveryEnvelopeStore {
  RecoveryEnvelopeStore(this.directory);

  final Directory directory;

  static const _activePrefix = 'envelope-';
  static const _retiredPrefix = 'retired-envelope-';

  Future<List<File>> list() async {
    if (!await directory.exists()) return const [];
    final files = await directory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<RecoveryBundle?> current() async {
    for (final file in await list()) {
      if (!p.basename(file.path).startsWith(_activePrefix)) continue;
      return RecoveryBundle.decode(await file.readAsString());
    }
    return null;
  }

  Future<File> write(
    RecoveryBundle bundle, {
    bool retireExisting = false,
  }) async {
    await directory.create(recursive: true);
    if (retireExisting) await retireAll();
    final stamp = AppClock.now().microsecondsSinceEpoch;
    final key = bundle.keyId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(p.join(directory.path, '$_activePrefix$stamp-$key.json'));
    await AtomicFile.writeString(file, bundle.encode());
    return file;
  }

  Future<void> retireAll() async {
    if (!await directory.exists()) return;
    for (final file in await list()) {
      final name = p.basename(file.path);
      if (!name.startsWith(_activePrefix)) continue;
      final target = File(
        p.join(
          directory.path,
          '$_retiredPrefix${name.substring(_activePrefix.length)}',
        ),
      );
      if (await target.exists()) await AtomicFile.deleteIfExists(target);
      await file.rename(target.path);
    }
  }

  /// Rewraps the current envelope's DEK under a new passphrase.
  ///
  /// The database is not rotated: the same DEK is resealed into a new envelope
  /// version, and the old envelope is retained with a `retired-` prefix.
  Future<File> changePassphrase({
    required String oldPassphrase,
    required String newPassphrase,
    required AttachmentKeyStore attachmentKeyStore,
  }) async {
    if (newPassphrase.trim().length < minPassphraseLength) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.unlockFailed,
        'Use a new passphrase of at least $minPassphraseLength characters.',
      );
    }
    final existing = await current();
    if (existing == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.recoveryRequired,
        'No managed recovery key was found. Create a recovery key first.',
      );
    }
    final opened = await RecoveryEnvelopeService.open(existing, oldPassphrase);
    final bundle = await RecoveryEnvelopeService.seal(
      dek: opened.dek,
      databaseId: existing.databaseId,
      keyId: existing.keyId,
      keyGeneration: existing.keyGeneration,
      cipherProfileId: existing.cipherProfileId,
      passphrase: newPassphrase,
      backupPassphrase: opened.backupPassphrase,
      attachmentKey: opened.attachmentKey ?? await attachmentKeyStore.read(),
    );
    await RecoveryEnvelopeService.verify(
      bundle: bundle,
      passphrase: newPassphrase,
      expectedDek: opened.dek,
    );
    return write(bundle, retireExisting: true);
  }

  static const minPassphraseLength = 10;
}
