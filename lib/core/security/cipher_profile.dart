import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Immutable description of the on-disk SQLite cipher format.
///
/// A raw 32-byte key is *not* a cipher specification.  SQLite3MultipleCiphers
/// also needs a scheme, a key mode, exact key encoding and a fixed PRAGMA
/// order.  E0 freezes one profile; the profile identifier is stored both in the
/// external metadata and inside the encrypted database.
class CipherProfile {
  const CipherProfile({
    required this.profileId,
    required this.cipher,
    required this.legacy,
    required this.keyMode,
    required this.pageSize,
    required this.tempStore,
    required this.memorySecurity,
    required this.verificationQuery,
  });

  /// Stable identifier persisted with the database.
  final String profileId;

  /// SQLite3MC cipher scheme (`sqlcipher`, `chacha20`, ...).
  final String cipher;

  /// SQLCipher legacy parameter set. `0` means "non-legacy".
  final int legacy;

  /// Only `raw-256` is supported by this implementation.  A passphrase-KDF
  /// profile would need a separately frozen set of KDF parameters.
  final String keyMode;

  final int pageSize;

  /// `MEMORY` avoids plaintext temporary spill; E0 must still prove that the
  /// selected SQLite3MC build encrypts any temp file it does use.
  final String tempStore;

  /// SQLite3MC memory cleaning mode (`FILL`, `OFF`). Ignored by builds that do
  /// not provide the pragma.
  final String memorySecurity;

  /// A real read executed after `PRAGMA key`. A wrong key would otherwise look
  /// like a successful open because `PRAGMA key` itself returns `ok`.
  final String verificationQuery;

  bool get usesRawKey => keyMode == 'raw-256';

  /// The documented raw-key literal for the selected cipher.
  String rawKeyLiteral(String lowerCaseHex) {
    if (!usesRawKey) {
      throw StateError('Profile $profileId does not use a raw key.');
    }
    return switch (cipher) {
      'sqlcipher' => "x'$lowerCaseHex'",
      'chacha20' => 'raw:$lowerCaseHex',
      _ => throw StateError('Unsupported cipher "$cipher" in $profileId.'),
    };
  }

  /// Cipher parameters. They must be applied *before* `PRAGMA key` and outside
  /// a transaction.
  List<String> configurationStatements() => <String>[
    "PRAGMA cipher = '$cipher'",
    if (legacy > 0) 'PRAGMA legacy = $legacy',
    'PRAGMA page_size = $pageSize',
    'PRAGMA temp_store = $tempStore',
    if (memorySecurity.isNotEmpty) 'PRAGMA memory_security = $memorySecurity',
  ];

  /// Complete, ordered statement list that opens a database with [dek].
  List<String> keyStatements(Uint8List dek) {
    final hex = _hex(dek);
    return <String>[
      ...configurationStatements(),
      'PRAGMA key = "${rawKeyLiteral(hex)}"',
    ];
  }

  /// Same ordered parameters, but rekeys an open (plaintext or keyed)
  /// database to [dek]. `PRAGMA rekey` is not a rollbackable transaction.
  List<String> rekeyStatements(Uint8List dek) {
    final hex = _hex(dek);
    return <String>[
      ...configurationStatements(),
      'PRAGMA rekey = "${rawKeyLiteral(hex)}"',
    ];
  }

  /// Rekeys a connection that already has an active key and cipher profile.
  ///
  /// Re-applying `PRAGMA cipher` after a key has been set is not valid on every
  /// SQLite3MC build, so rotation uses this single statement instead.
  String rekeyOnlyStatement(Uint8List dek) {
    final hex = _hex(dek);
    return 'PRAGMA rekey = "${rawKeyLiteral(hex)}"';
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

/// Profiles known to this build.
///
/// [sqlCipher4RawV1] is the E0-selected production profile; it is versioned and
/// must not change without a tested migration or rekey. [sqleetRawV1] is kept
/// only as an alternative tested by the rejection path and must not be used for
/// new databases without its own E0 decision.
abstract final class CipherProfiles {
  static const sqlCipher4RawV1 = CipherProfile(
    profileId: 'locus-sqlcipher4-raw-v1',
    cipher: 'sqlcipher',
    legacy: 4,
    keyMode: 'raw-256',
    pageSize: 4096,
    tempStore: 'MEMORY',
    memorySecurity: 'FILL',
    verificationQuery: 'SELECT count(*) FROM sqlite_master',
  );

  static const sqleetRawV1 = CipherProfile(
    profileId: 'locus-sqleet-raw-v1',
    cipher: 'chacha20',
    legacy: 0,
    keyMode: 'raw-256',
    pageSize: 4096,
    tempStore: 'MEMORY',
    memorySecurity: 'FILL',
    verificationQuery: 'SELECT count(*) FROM sqlite_master',
  );

  static const active = sqlCipher4RawV1;

  static const all = <CipherProfile>[sqlCipher4RawV1, sqleetRawV1];

  static CipherProfile? byId(String profileId) {
    for (final profile in all) {
      if (profile.profileId == profileId) return profile;
    }
    return null;
  }
}

/// Runtime proof that the loaded native library really is SQLite3MC.
///
/// Plain SQLite silently ignores unknown pragmas, so applying a cipher profile
/// to a plain library would "succeed" and then write plaintext.  Every keyed
/// open must pass this check first.
abstract final class SqliteCipherRuntime {
  /// SQLite3MC exposes `PRAGMA cipher` (query form) and a version function.
  /// Either signal is accepted; neither is present in a stock SQLite build.
  static bool isAvailable(sqlite3.Database db) {
    try {
      final pragma = db.select('PRAGMA cipher');
      if (pragma.isNotEmpty) return true;
    } catch (_) {
      // Fall through to the function probe.
    }
    try {
      final version = db.select('SELECT sqlite3mc_version() AS version');
      return version.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Applies the cipher profile and key, then performs a real read so a wrong
  /// key is detected while the connection is still private to this helper.
  static void applyKey(
    sqlite3.Database db,
    CipherProfile profile,
    Uint8List dek,
  ) {
    if (!isAvailable(db)) {
      throw StateError(
        'SQLite3MultipleCiphers is not available in the loaded SQLite build.',
      );
    }
    for (final statement in profile.keyStatements(dek)) {
      db.execute(statement);
    }
    db.select(profile.verificationQuery);
  }

  /// Rekeys an already-open database to [dek]. The caller is responsible for
  /// closing and reopening to verify the result.
  static void applyRekey(
    sqlite3.Database db,
    CipherProfile profile,
    Uint8List dek,
  ) {
    if (!isAvailable(db)) {
      throw StateError(
        'SQLite3MultipleCiphers is not available in the loaded SQLite build.',
      );
    }
    for (final statement in profile.rekeyStatements(dek)) {
      db.execute(statement);
    }
  }

  /// Rekeys a connection whose cipher profile and old key are already active.
  static void applyRekeyOnly(
    sqlite3.Database db,
    CipherProfile profile,
    Uint8List dek,
  ) {
    if (!isAvailable(db)) {
      throw StateError(
        'SQLite3MultipleCiphers is not available in the loaded SQLite build.',
      );
    }
    db.execute(profile.rekeyOnlyStatement(dek));
  }
}
