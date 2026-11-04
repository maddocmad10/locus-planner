import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import 'atomic_file.dart';
import 'database_paths.dart';
import 'windows_dpapi_store.dart';

/// Where the optional automatic-backup passphrase lives.
///
/// It is kept in an OS-protected store so scheduled backups can run without the
/// user present. Restoring still requires the user to type it.
abstract interface class BackupPassphraseStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Credential-store implementation used on Android and as the legacy Windows
/// location.
///
/// `flutter_secure_storage_windows` keeps its data in a roaming JSON file and
/// deletes that file when decryption fails. The database key store no longer
/// uses it; the Windows backup passphrase is migrated to
/// [WindowsDpapiBackupPassphraseStore] but this class remains for reading the
/// value written by older builds.
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

/// Windows store that keeps the passphrase in a DPAPI-protected file under
/// `%LOCALAPPDATA%`, next to the database keys.
///
/// DPAPI binds the blob to the current Windows account, which is the same
/// protection the credential store relies on, but without a plugin that
/// removes its only copy when a decrypt fails. A damaged file is left in place:
/// re-entering the passphrase overwrites it, and evidence survives until then.
class WindowsDpapiBackupPassphraseStore implements BackupPassphraseStore {
  WindowsDpapiBackupPassphraseStore({
    this.directory,
    Future<Directory> Function()? directoryResolver,
  }) : _directoryResolver =
           directoryResolver ?? DatabasePathsResolver.secureDataDirectory;

  static const fileName = 'backup_passphrase.dat';
  static const _version = 1;

  final Directory? directory;
  final Future<Directory> Function() _directoryResolver;

  Future<File> _file() async {
    final directory = this.directory ?? await _directoryResolver();
    return File(p.join(directory.path, fileName));
  }

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final String plaintext;
    try {
      plaintext = WindowsDpapiStore.unprotect(await file.readAsBytes());
    } catch (error) {
      throw FormatException(
        'The saved backup passphrase could not be unlocked. Re-enter it in '
        'Settings; the protected file has been kept for diagnosis.',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(plaintext);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != _version ||
        decoded['passphrase'] is! String) {
      throw const FormatException(
        'The saved backup passphrase is damaged. Re-enter it in Settings.',
      );
    }
    final passphrase = decoded['passphrase'] as String;
    return passphrase.isEmpty ? null : passphrase;
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    final payload = jsonEncode(<String, Object>{
      'version': _version,
      'passphrase': value,
    });
    await AtomicFile.writeBytes(file, WindowsDpapiStore.protect(payload));
  }

  @override
  Future<void> delete() async {
    await AtomicFile.deleteIfExists(await _file());
  }
}

/// Reads the new location first and migrates a legacy credential-store value
/// on the first successful read.
///
/// The legacy value is only removed after the new store has accepted the
/// write. If the primary store fails to read, the error is propagated instead
/// of silently resurrecting an older passphrase from the legacy location.
class MigratingBackupPassphraseStore implements BackupPassphraseStore {
  const MigratingBackupPassphraseStore({
    required this.primary,
    required this.legacy,
  });

  final BackupPassphraseStore primary;
  final BackupPassphraseStore legacy;

  @override
  Future<String?> read() async {
    final current = await primary.read();
    if (current != null) return current;

    final old = await legacy.read();
    if (old == null || old.isEmpty) return null;
    try {
      await primary.write(old);
    } catch (_) {
      // Keep working from the legacy store; the next read retries migration.
      return old;
    }
    try {
      await legacy.delete();
    } catch (_) {
      // The primary copy is authoritative now; a stale legacy value is inert.
    }
    return old;
  }

  @override
  Future<void> write(String value) async {
    await primary.write(value);
    try {
      await legacy.delete();
    } catch (_) {
      // Leaving a stale legacy copy does not affect reads.
    }
  }

  @override
  Future<void> delete() async {
    Object? firstError;
    try {
      await primary.delete();
    } catch (error) {
      firstError = error;
    }
    try {
      await legacy.delete();
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) throw firstError;
  }
}

/// The store used by [BackupEncryptionService] when none is injected.
BackupPassphraseStore defaultBackupPassphraseStore() {
  if (Platform.isWindows) {
    return MigratingBackupPassphraseStore(
      primary: WindowsDpapiBackupPassphraseStore(),
      legacy: const SecureBackupPassphraseStore(),
    );
  }
  return const SecureBackupPassphraseStore();
}
