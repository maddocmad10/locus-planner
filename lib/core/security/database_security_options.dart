import 'dart:io';

import 'cipher_profile.dart';
import 'database_key_store.dart';

/// Process-wide configuration for the live-database encryption layer.
///
/// Encryption is **disabled by default** until E0 has proven the native
/// SQLite3MC path on real Windows and Android release artifacts.  The gate is
/// deliberately explicit: an unproven cipher must never silently produce a
/// plaintext database while the app claims encryption is on.
class DatabaseSecurityOptions {
  const DatabaseSecurityOptions.plaintext({this.dataDirectory})
    : encryptLiveDatabase = false,
      profile = CipherProfiles.active,
      keyStore = null,
      requireEncryptedAutomaticBackups = false;

  const DatabaseSecurityOptions.encrypted({
    this.profile = CipherProfiles.active,
    required this.keyStore,
    this.requireEncryptedAutomaticBackups = true,
    this.dataDirectory,
  }) : encryptLiveDatabase = true;

  final bool encryptLiveDatabase;
  final CipherProfile profile;

  /// Required when [encryptLiveDatabase] is true.
  final DatabaseKeyStore? keyStore;

  /// Keep the backup policy fail-closed even if live encryption is temporarily
  /// disabled (for example during a migration rollback).
  final bool requireEncryptedAutomaticBackups;

  /// Test/portable override for the sensitive-state directory.
  final Directory? dataDirectory;
}

abstract final class DatabaseSecurity {
  static DatabaseSecurityOptions options =
      const DatabaseSecurityOptions.plaintext();

  static DatabaseSecurityOptions get current => options;

  static bool get liveEncryptionEnabled => options.encryptLiveDatabase;

  static bool get backupsMustBeEncrypted =>
      options.encryptLiveDatabase || options.requireEncryptedAutomaticBackups;

  static CipherProfile get profile => options.profile;

  static DatabaseKeyStore? get keyStore => options.keyStore;

  static void configure(DatabaseSecurityOptions value) => options = value;

  static void reset() => options = const DatabaseSecurityOptions.plaintext();

  /// Enables the layer from `LOCUS_DB_ENCRYPTION=1|true`.
  ///
  /// The environment switch is the E0 gate: once the native library is proven,
  /// the release build can enable it without changing application code.
  static void configureFromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final flag = (env['LOCUS_DB_ENCRYPTION'] ?? '').toLowerCase();
    if (flag == '1' || flag == 'true') {
      configure(
        DatabaseSecurityOptions.encrypted(
          keyStore: createDefaultDatabaseKeyStore(),
        ),
      );
    } else {
      reset();
    }
  }
}
