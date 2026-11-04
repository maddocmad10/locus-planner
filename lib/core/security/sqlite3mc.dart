import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart' as sqlite_open;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
// The public package:sqlite3 API caches one global library per isolate. A
// separate binding instance lets the security layer use the verified
// SQLite3MC library even when another consumer already opened stock SQLite.
// ignore: implementation_imports
import 'package:sqlite3/src/ffi/implementation.dart' show FfiSqlite3;

import '../services/crypto/key_derivation.dart';
import 'cipher_profile.dart';
import 'database_security_errors.dart';

/// Database handles used by the database-security layer.
///
/// When encryption is configured this returns bindings backed by the verified
/// SQLite3MC library; otherwise it stays on the stock library. Using explicit
/// bindings avoids relying on being the first `sqlite3` user in the isolate.
abstract final class SqliteRuntime {
  static sqlite3.Sqlite3? _bindings;

  static bool get usesSqlite3mc => Sqlite3mcLoader.isConfigured;

  static sqlite3.Sqlite3 get bindings {
    if (!Sqlite3mcLoader.isConfigured) return sqlite3.sqlite3;
    return _bindings ??= FfiSqlite3(Sqlite3mcLoader._libraryHandle());
  }

  static sqlite3.Database open(
    String path, {
    sqlite3.OpenMode mode = sqlite3.OpenMode.readWriteCreate,
  }) => bindings.open(path, mode: mode);

  static sqlite3.Database openInMemory() => bindings.openInMemory();
}

/// Result of the runtime E0 probe.
class Sqlite3mcRuntimeInfo {
  const Sqlite3mcRuntimeInfo({
    required this.version,
    required this.libraryPath,
    required this.cipherPragmaAvailable,
  });

  final String version;
  final String libraryPath;
  final bool cipherPragmaAvailable;
}

/// Report produced by the full encrypted round-trip self-test.
class Sqlite3mcSelfTestReport {
  const Sqlite3mcSelfTestReport({
    required this.runtime,
    required this.profileId,
    required this.encryptedHeader,
    required this.reopenedWithKey,
    required this.wrongKeyRejected,
    required this.tempStore,
    required this.pageSize,
    required this.rowCount,
  });

  final Sqlite3mcRuntimeInfo runtime;
  final String profileId;
  final bool encryptedHeader;
  final bool reopenedWithKey;
  final bool wrongKeyRejected;
  final int tempStore;
  final int pageSize;
  final int rowCount;

  bool get passed =>
      encryptedHeader &&
      reopenedWithKey &&
      wrongKeyRejected &&
      tempStore == 2 &&
      pageSize == 4096 &&
      rowCount == 2;
}

/// Loads the bundled SQLite3MultipleCiphers library instead of stock SQLite.
///
/// The override is per isolate: `package:sqlite3` caches the first opened
/// library, so [ensureConfigured] must run before any `sqlite3` access in an
/// isolate. Drift's background isolate is covered by `isolateSetup`.
///
/// Encryption-disabled builds do not call this loader at all and keep using the
/// stock library supplied by `sqlite3_flutter_libs`.
abstract final class Sqlite3mcLoader {
  /// Minimum SQLite3MC runtime accepted by this build.
  static const minimumVersion = '2.6.1';

  static const windowsFileName = 'sqlite3mc_x64.dll';
  static const androidFileName = 'libsqliteX.so';

  static bool _configured = false;
  static String? _resolvedLibraryPath;
  static ffi.DynamicLibrary? _library;
  static Future<Sqlite3mcSelfTestReport>? _verification;

  /// True once [ensureConfigured] has installed the platform loader for this
  /// isolate.
  static bool get isConfigured => _configured;

  static String? get resolvedLibraryPath => _resolvedLibraryPath;

  static void ensureConfigured() {
    if (_configured) return;
    if (Platform.isWindows) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.windows,
        _openOnWindows,
      );
      _configured = true;
    } else if (Platform.isAndroid) {
      sqlite_open.open.overrideFor(
        sqlite_open.OperatingSystem.android,
        _openOnAndroid,
      );
      _configured = true;
    } else {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'SQLite3MultipleCiphers integration is only defined for Windows and '
        'Android.',
      );
    }
  }

  /// Loads the library and confirms the runtime version.
  static Sqlite3mcRuntimeInfo requireAvailable() {
    ensureConfigured();
    sqlite3.Database? db;
    try {
      db = SqliteRuntime.openInMemory();
      final rows = db.select('SELECT sqlite3mc_version() AS version');
      if (rows.isEmpty) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
          'The loaded SQLite library does not report a SQLite3MC version.',
        );
      }
      final version = '${rows.first['version']}';
      if (!_atLeast(version, minimumVersion)) {
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
          'SQLite3MC $version is older than the required $minimumVersion.',
        );
      }

      var cipherPragma = false;
      try {
        cipherPragma = db.select('PRAGMA cipher').isNotEmpty;
      } catch (_) {
        // Report as unsupported below.
      }
      if (!cipherPragma) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
          'The loaded SQLite3MC build does not expose the cipher pragma.',
        );
      }

      return Sqlite3mcRuntimeInfo(
        version: version,
        libraryPath: _resolvedLibraryPath ?? androidFileName,
        cipherPragmaAvailable: true,
      );
    } on DatabaseSecurityException {
      rethrow;
    } catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'SQLite3MultipleCiphers could not be loaded.',
        cause: error,
      );
    } finally {
      db?.dispose();
    }
  }

  /// Runs a complete create → reopen → wrong-key-reject probe once per process.
  ///
  /// A version string alone does not prove that the cipher is active. A stock
  /// SQLite build ignores `PRAGMA key` and would otherwise write plaintext.
  static Future<Sqlite3mcSelfTestReport> requireVerified({
    CipherProfile? profile,
  }) {
    final existing = _verification;
    if (existing != null) return existing;
    final future = _runSelfTest(profile ?? CipherProfiles.active);
    _verification = future;
    return future;
  }

  /// Test hook: forget the cached self-test result.
  static void resetVerificationForTesting() {
    _verification = null;
  }

  static Future<Sqlite3mcSelfTestReport> _runSelfTest(
    CipherProfile profile,
  ) async {
    final runtime = requireAvailable();
    final directory = await Directory.systemTemp.createTemp('locus-e0-');
    final file = File(p.join(directory.path, 'e0.db'));
    final key = KeyDerivation.randomBytes(32);
    final wrongKey = KeyDerivation.randomBytes(32);
    try {
      final created = SqliteRuntime.open(file.path);
      try {
        SqliteCipherRuntime.applyKey(created, profile, key);
        created.execute(
          'CREATE TABLE probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL)',
        );
        created.execute("INSERT INTO probe (value) VALUES ('locus')");
        created.execute("INSERT INTO probe (value) VALUES ('planner')");
      } finally {
        created.dispose();
      }

      final header = (await file.readAsBytes()).take(16).toList();
      final headerText = String.fromCharCodes(header);
      final encryptedHeader =
          header.length == 16 && headerText != 'SQLite format 3\u0000';

      var reopened = false;
      var rowCount = 0;
      final reader = SqliteRuntime.open(file.path);
      try {
        SqliteCipherRuntime.applyKey(reader, profile, key);
        final rows = reader.select('SELECT value FROM probe ORDER BY id');
        rowCount = rows.length;
        reopened = rowCount == 2;
      } finally {
        reader.dispose();
      }

      var wrongRejected = false;
      final probe = SqliteRuntime.open(file.path);
      try {
        SqliteCipherRuntime.applyKey(probe, profile, wrongKey);
      } catch (_) {
        wrongRejected = true;
      } finally {
        probe.dispose();
      }

      var tempStore = -1;
      var pageSize = -1;
      final pragma = SqliteRuntime.open(file.path);
      try {
        SqliteCipherRuntime.applyKey(pragma, profile, key);
        tempStore =
            pragma.select('PRAGMA temp_store').first['temp_store'] as int;
        pageSize = pragma.select('PRAGMA page_size').first['page_size'] as int;
      } finally {
        pragma.dispose();
      }

      final report = Sqlite3mcSelfTestReport(
        runtime: runtime,
        profileId: profile.profileId,
        encryptedHeader: encryptedHeader,
        reopenedWithKey: reopened,
        wrongKeyRejected: wrongRejected,
        tempStore: tempStore,
        pageSize: pageSize,
        rowCount: rowCount,
      );
      if (!report.passed) {
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
          'The SQLite3MC runtime did not pass the encrypted round-trip test '
          '(encryptedHeader=${report.encryptedHeader}, '
          'reopenedWithKey=${report.reopenedWithKey}, '
          'wrongKeyRejected=${report.wrongKeyRejected}, '
          'tempStore=${report.tempStore}, pageSize=${report.pageSize}, '
          'rowCount=${report.rowCount}).',
        );
      }
      return report;
    } finally {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        // Evidence is non-sensitive and the OS can clean it up later.
      }
    }
  }

  static ffi.DynamicLibrary _libraryHandle() {
    return _library ??= Platform.isWindows
        ? _openOnWindows()
        : _openOnAndroid();
  }

  static ffi.DynamicLibrary _openOnWindows() {
    for (final candidate in _windowsCandidates()) {
      if (candidate.isNotEmpty && File(candidate).existsSync()) {
        _resolvedLibraryPath = candidate;
        return ffi.DynamicLibrary.open(candidate);
      }
    }
    // Last resort: let the Windows loader search the process search path.
    try {
      final library = ffi.DynamicLibrary.open(windowsFileName);
      _resolvedLibraryPath = windowsFileName;
      return library;
    } on ArgumentError catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
        'Bundled SQLite3MC was not found next to the executable. Checked: '
        '${_windowsCandidates().join(', ')}.',
        cause: error,
      );
    }
  }

  static List<String> _windowsCandidates() {
    final fromEnvironment = Platform.environment['LOCUS_SQLITE3MC_DLL'];
    final executable = p.dirname(Platform.resolvedExecutable);
    return <String>[
      if (fromEnvironment != null && fromEnvironment.isNotEmpty)
        fromEnvironment,
      p.join(executable, windowsFileName),
      p.join(executable, 'data', windowsFileName),
      p.join(
        Directory.current.path,
        'third_party',
        'sqlite3mc',
        'windows',
        windowsFileName,
      ),
    ];
  }

  static ffi.DynamicLibrary _openOnAndroid() {
    try {
      _resolvedLibraryPath = androidFileName;
      return ffi.DynamicLibrary.open(androidFileName);
    } on ArgumentError {
      // Older Android loaders cannot resolve libraries shipped inside the APK
      // by name. Locate the app-private copy explicitly.
      try {
        final appIdBytes = File('/proc/self/cmdline').readAsBytesSync();
        final end = appIdBytes.indexOf(0);
        final appId = String.fromCharCodes(
          appIdBytes.sublist(0, end < 0 ? appIdBytes.length : end),
        );
        final path = '/data/data/$appId/lib/$androidFileName';
        _resolvedLibraryPath = path;
        return ffi.DynamicLibrary.open(path);
      } catch (error) {
        throw DatabaseSecurityException(
          DatabaseSecurityErrorCode.encryptionExtensionUnavailable,
          'Bundled SQLite3MC ($androidFileName) could not be loaded.',
          cause: error,
        );
      }
    }
  }

  static bool _atLeast(String version, String minimum) {
    final actual = _parts(version);
    final required = _parts(minimum);
    for (var index = 0; index < 3; index++) {
      if (actual[index] != required[index]) {
        return actual[index] > required[index];
      }
    }
    return true;
  }

  static List<int> _parts(String version) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(version);
    if (match == null) return const <int>[0, 0, 0];
    return <int>[
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }
}
