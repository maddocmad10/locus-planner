import '../security/backup_passphrase_store.dart';

export '../security/backup_passphrase_store.dart'
    show
        BackupPassphraseStore,
        SecureBackupPassphraseStore,
        WindowsDpapiBackupPassphraseStore,
        MigratingBackupPassphraseStore,
        defaultBackupPassphraseStore;

/// Reads and writes the passphrase used for unattended backups.
class BackupEncryptionService {
  BackupEncryptionService({BackupPassphraseStore? store})
    : store = store ?? defaultBackupPassphraseStore();

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
