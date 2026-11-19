import 'dart:io';

import 'package:archive/archive.dart';

/// Release gate for the bundled SQLite3MultipleCiphers libraries.
///
/// Windows:
///   dart run tool/verify_release_bundle.dart --platform=windows \
///     --path=build/windows/x64/runner/Release
///
/// Android:
///   dart run tool/verify_release_bundle.dart --platform=android \
///     --path=build/app/outputs/flutter-apk/app-release.apk
void main(List<String> arguments) {
  final options = _parse(arguments);
  final platform = options['platform'];
  final path = options['path'];
  final database = options['database'];
  if (database != null) {
    _verifyDatabaseHeader(database);
  }
  if (platform == null || path == null) {
    if (database == null) {
      stderr.writeln(
        'Usage: dart run tool/verify_release_bundle.dart '
        '--platform=windows|android --path=<bundle-or-apk>\n'
        '   or: --database=<path-to-locus_planner.db>',
      );
      exitCode = 2;
    }
    return;
  }

  switch (platform) {
    case 'windows':
      _verifyWindows(path);
    case 'android':
      _verifyAndroid(path);
    default:
      stderr.writeln('Unknown platform "$platform".');
      exitCode = 2;
  }
}

Map<String, String> _parse(List<String> arguments) {
  final options = <String, String>{};
  for (final argument in arguments) {
    if (!argument.startsWith('--')) continue;
    final separator = argument.indexOf('=');
    if (separator < 0) continue;
    options[argument.substring(2, separator)] = argument.substring(
      separator + 1,
    );
  }
  return options;
}

void _verifyDatabaseHeader(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail('Database does not exist: $path');
    exitCode = 1;
    return;
  }
  final handle = file.openSync();
  final List<int> bytes;
  try {
    bytes = handle.readSync(16);
  } finally {
    handle.closeSync();
  }
  final isPlainSqlite =
      bytes.length >= 16 &&
      String.fromCharCodes(bytes) == 'SQLite format 3\u0000';
  if (isPlainSqlite) {
    _fail(
      'Database header is plain SQLite. A release build with encryption '
      'enabled must not produce this file.',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('Database header is not plain SQLite.');
}

void _verifyWindows(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    _fail('Windows bundle directory does not exist: $path');
    return;
  }
  final required = <String>[
    'locus_planner.exe',
    'sqlite3.dll',
    'sqlite3mc_x64.dll',
  ];
  var failures = 0;
  for (final name in required) {
    final file = File('${directory.path}${Platform.pathSeparator}$name');
    if (!file.existsSync() || file.lengthSync() == 0) {
      _fail('Missing or empty release file: $name');
      failures++;
    }
  }
  if (failures > 0) {
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Windows release bundle contains the executable and both SQLite libraries.',
  );
}

void _verifyAndroid(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail('Android APK does not exist: $path');
    exitCode = 1;
    return;
  }
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(file.readAsBytesSync(), verify: true);
  } catch (error) {
    _fail('Could not read the APK as a ZIP: $error');
    exitCode = 1;
    return;
  }
  final names = {for (final entry in archive.files) entry.name};
  // Derive the shipped ABIs from the Flutter engine payload. APKs use
  // `lib/<abi>/libapp.so`; AABs use `base/lib/<abi>/libapp.so`.
  final engineEntry = RegExp(r'(?:^|/)lib/([^/]+)/libapp\.so$');
  final abis = <String>{
    for (final name in names)
      if (engineEntry.firstMatch(name) != null)
        engineEntry.firstMatch(name)!.group(1)!,
  }..removeWhere((abi) => abi.isEmpty);
  var failures = 0;
  if (abis.isEmpty) {
    _fail('Archive has no lib/<abi>/libapp.so entries.');
    failures++;
  }
  if (!abis.contains('arm64-v8a')) {
    _fail('Archive does not ship the arm64-v8a ABI.');
    failures++;
  }
  for (final abi in abis) {
    final matches = archive.files.where(
      (entry) =>
          entry.name == 'lib/$abi/libsqliteX.so' ||
          entry.name == 'base/lib/$abi/libsqliteX.so',
    );
    if (matches.isEmpty || matches.first.size == 0) {
      _fail('Archive is missing lib/$abi/libsqliteX.so');
      failures++;
    }
  }
  // A live database must never be packaged inside an APK by accident.
  for (final name in names) {
    if (name.endsWith('.db') || name.endsWith('.db-wal')) {
      _fail('APK unexpectedly contains a database file: $name');
      failures++;
    }
  }
  if (failures > 0) {
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Android archive contains libsqliteX.so for every shipped ABI '
    '(${abis.toList()..sort()}).',
  );
}

void _fail(String message) {
  stderr.writeln('Release bundle gate: $message');
}
