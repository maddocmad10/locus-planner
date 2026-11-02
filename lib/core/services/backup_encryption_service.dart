import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the optional automatic-backup passphrase lives.
///
/// It is kept in the OS credential store so scheduled backups can run without
/// the user present. Restoring still requires the user to type it.
abstract interface class BackupPassphraseStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureBackupPassphraseStore implements BackupPassphraseStore {
  const SecureBackupPassphraseStore();

  static const _key = 'locus.backup.passphrase';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// Reads and writes the passphrase used for unattended backups.
class BackupEncryptionService {
  BackupEncryptionService({this.store = const SecureBackupPassphraseStore()});

  static const minPassphraseLength = 10;

  final BackupPassphraseStore store;

  Future<String?> read() async {
    final value = await store.read();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  Future<bool> get isEnabled async => (await read()) != null;

  Future<void> setPassphrase(String passphrase) async {
    if (passphrase.trim().length < minPassphraseLength) {
      throw FormatException(
        'Use at least $minPassphraseLength characters for the passphrase.',
      );
    }
    await store.write(passphrase);
  }

  Future<void> clear() => store.delete();
}
