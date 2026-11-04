/// Stable, user-visible error taxonomy for the database security layer.
///
/// The codes are intentionally coarse: they are safe to log and to show in the
/// recovery UI.  Keys, passphrases, salts used as secrets and raw envelopes
/// must never be attached to an instance of this exception.
enum DatabaseSecurityErrorCode {
  /// The database cannot be opened without user action (missing key, missing
  /// metadata, quarantine present, ...).
  recoveryRequired,

  /// A recovery credential was supplied but did not unlock the envelope.
  unlockFailed,

  /// The encrypted file failed an integrity or authentication check.
  databaseDamaged,

  /// A conversion or rotation was interrupted and can be resumed or rolled
  /// back from the durable journal.
  migrationInterrupted,

  /// The file was written with a cipher profile this build does not support.
  unsupportedEncryption,

  /// The secure store could not be read or decrypted.  Evidence is preserved.
  keyStoreCorrupt,

  /// The external metadata and the encrypted database disagree about identity.
  identityMismatch,

  /// A plaintext SQLite file exists where an encrypted database is expected.
  plaintextUnderEncryptedIdentity,

  /// SQLite3MultipleCiphers is not compiled into the loaded native library.
  encryptionExtensionUnavailable,

  /// The active key slot is missing.
  keyMissing,

  /// The external metadata is unreadable or has an unsupported version.
  metadataCorrupt,

  /// Metadata says a database exists but the file is gone.
  databaseMissing,

  /// A zero-length database file was found.
  zeroLengthDatabase,

  /// The supplied key did not decrypt the database.
  wrongKey,
}

class DatabaseSecurityException implements Exception {
  const DatabaseSecurityException(
    this.code,
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final DatabaseSecurityErrorCode code;
  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// A short identifier for logs and diagnostics.  It never contains secret
  /// material.
  String get codeName => switch (code) {
    DatabaseSecurityErrorCode.recoveryRequired => 'RECOVERY_REQUIRED',
    DatabaseSecurityErrorCode.unlockFailed => 'UNLOCK_FAILED',
    DatabaseSecurityErrorCode.databaseDamaged => 'DATABASE_DAMAGED',
    DatabaseSecurityErrorCode.migrationInterrupted => 'MIGRATION_INTERRUPTED',
    DatabaseSecurityErrorCode.unsupportedEncryption => 'UNSUPPORTED_ENCRYPTION',
    DatabaseSecurityErrorCode.keyStoreCorrupt => 'KEY_STORE_CORRUPT',
    DatabaseSecurityErrorCode.identityMismatch => 'IDENTITY_MISMATCH',
    DatabaseSecurityErrorCode.plaintextUnderEncryptedIdentity =>
      'PLAINTEXT_UNDER_ENCRYPTED_IDENTITY',
    DatabaseSecurityErrorCode.encryptionExtensionUnavailable =>
      'ENCRYPTION_EXTENSION_UNAVAILABLE',
    DatabaseSecurityErrorCode.keyMissing => 'KEY_MISSING',
    DatabaseSecurityErrorCode.metadataCorrupt => 'METADATA_CORRUPT',
    DatabaseSecurityErrorCode.databaseMissing => 'DATABASE_MISSING',
    DatabaseSecurityErrorCode.zeroLengthDatabase => 'ZERO_LENGTH_DATABASE',
    DatabaseSecurityErrorCode.wrongKey => 'WRONG_KEY',
  };

  @override
  String toString() => '[$codeName] $message';
}
