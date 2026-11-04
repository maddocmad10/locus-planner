/// Compile-time switches used by release builds.
///
/// Flutter release builds on Android cannot read arbitrary process environment
/// variables, so deployment switches must be compiled in. Pass them explicitly:
///
/// ```text
/// flutter build windows --release \
///   --dart-define=LOCUS_DB_ENCRYPTION=true \
///   --dart-define=LOCUS_DB_MIGRATION=true
/// ```
///
/// Both default to `false` so a plain `flutter build` never enables encryption
/// or converts an existing plaintext database by accident.
abstract final class BuildConfig {
  static const bool encryptDatabase = bool.fromEnvironment(
    'LOCUS_DB_ENCRYPTION',
  );

  /// Allows startup to convert a recognized plaintext database. This is
  /// intentionally separate from [encryptDatabase].
  static const bool allowAutomaticDatabaseMigration = bool.fromEnvironment(
    'LOCUS_DB_MIGRATION',
  );
}
