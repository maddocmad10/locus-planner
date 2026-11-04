import 'dart:io';

import 'cipher_profile.dart';
import 'database_key_store.dart';

/// Process-wide configuration for the live-database encryption layer.
///
/// Encryption is **disabled by default** until the release gates pass. The
/// bundled SQLite3MC runtime is integrated and self-tested, but production
/// migration still waits for physical-device and recovery validation, so it
/// requires a separate migration switch.
class DatabaseSecurityOptions {
  const DatabaseSecurityOptions.plaintext({this.dataDirectory})
    : encryptLiveDatabase = false,
      allowAutomaticConversion = false,
      profile = CipherProfiles.active,
      keyStore = null,
      requireEncryptedAutomaticBackups = false;

  const DatabaseSecurityOptions.encrypted({
    this.profile = CipherProfiles.active,
    required this.keyStore,
    this.requireEncryptedAutomaticBackups = true,
    this.allowAutomaticConversion = false,
    this.dataDirectory,
  }) : encryptLiveDatabase = true;

  final bool encryptLiveDatabase;

  /// Whether an existing recognized plaintext database may be converted
  /// automatically at startup.
  ///
  /// Kept separate from [encryptLiveDatabase] so enabling the cipher in a build
  /// cannot silently migrate production data before the recovery gates pass.
  final bool allowAutomaticConversion;
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
  /// `LOCUS_DB_MIGRATION=1|true` additionally permits automatic conversion of an
  /// existing plaintext database. Encryption can therefore be enabled in a
  /// build without silently migrating data.
  static void configureFromEnvironment({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final flag = (env['LOCUS_DB_ENCRYPTION'] ?? '').toLowerCase();
    final migrationFlag = (env['LOCUS_DB_MIGRATION'] ?? '').toLowerCase();
    if (flag == '1' || flag == 'true') {
      configure(
        DatabaseSecurityOptions.encrypted(
          keyStore: createDefaultDatabaseKeyStore(),
          allowAutomaticConversion:
              migrationFlag == '1' || migrationFlag == 'true',
        ),
      );
    } else {
      reset();
    }
  }
}
