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
  final supportEmail = options['support-email'];
  final privacyUrl = options['privacy-url'];
  if (supportEmail != null &&
      (supportEmail.isEmpty ||
          supportEmail.contains('example.invalid') ||
          !supportEmail.contains('@'))) {
    _fail('LOCUS_SUPPORT_EMAIL is missing or still a placeholder.');
    exitCode = 1;
  }
  if (privacyUrl != null &&
      (!privacyUrl.startsWith('https://') ||
          privacyUrl.contains('example.invalid'))) {
    _fail('LOCUS_PRIVACY_URL must be a published HTTPS URL.');
    exitCode = 1;
  }
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
    for (final library in const [
      'libsqliteX.so',
      'libapp.so',
      'libflutter.so',
    ]) {
      final matches = archive.files.where(
        (entry) =>
            entry.name == 'lib/$abi/$library' ||
            entry.name == 'base/lib/$abi/$library',
      );
      if (matches.isEmpty || matches.first.size == 0) {
        _fail('Archive is missing lib/$abi/$library');
        failures++;
      }
    }
  }
  // Every shipped 64-bit shared object must have every PT_LOAD segment aligned
  // to at least 16 KB. Malformed or unreadable objects fail closed.
  var checkedObjects = 0;
  for (final entry in archive.files) {
    if (!entry.name.endsWith('.so')) continue;
    if (!entry.name.contains('/arm64-v8a/') &&
        !entry.name.contains('/x86_64/')) {
      continue;
    }
    checkedObjects++;
    final alignmentError = _elfAlignmentError(entry);
    if (alignmentError != null) {
      _fail('${entry.name}: $alignmentError');
      failures++;
    }
  }
  if (checkedObjects == 0) {
    _fail('No 64-bit shared objects were found to verify.');
    failures++;
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

/// Returns null when every PT_LOAD segment is 16 KB-aligned; otherwise a
/// human-readable reason. Unreadable or truncated objects fail closed.
String? _elfAlignmentError(ArchiveFile entry) {
  return verifyElfAlignmentBytes(entry.content);
}

/// Public fixture-friendly gate for an ELF64 image.
String? verifyElfAlignmentBytes(List<int> data) {
  if (data.length < 64) return 'ELF header is truncated';
  int u16(int offset) => data[offset] | (data[offset + 1] << 8);
  int u32(int offset) =>
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
  int u64(int offset) {
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }

  if (data[0] != 0x7f ||
      data[1] != 0x45 ||
      data[2] != 0x4c ||
      data[3] != 0x46) {
    return 'not an ELF file';
  }
  if (data[4] != 2) return 'not an ELF64 object';
  final phoff = u64(32);
  final phentsize = u16(54);
  final phnum = u16(56);
  if (phentsize < 56 || phnum == 0) return 'missing program headers';
  var loadSegments = 0;
  for (var index = 0; index < phnum; index++) {
    final offset = phoff + index * phentsize;
    if (offset < 0 || offset + 56 > data.length) {
      return 'program header table is truncated';
    }
    if (u32(offset) != 1) continue; // PT_LOAD
    loadSegments++;
    final align = u64(offset + 48);
    if (align < 16384) {
      return 'PT_LOAD segment $index aligns to $align bytes, need 16384';
    }
  }
  if (loadSegments == 0) return 'no PT_LOAD segments';
  return null;
}
