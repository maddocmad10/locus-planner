import 'dart:convert';
import 'dart:io';

import 'package:locus_planner/core/security/cipher_profile.dart';
import 'package:locus_planner/core/security/sqlite3mc.dart';

/// E0 proof helper: verifies the bundled SQLite3MC runtime on this machine.
///
/// Run from the project root:
///
/// ```text
/// dart run tool/sqlite3mc_e0.dart
/// ```
///
/// A non-zero exit code means live encryption must stay disabled.
Future<void> main(List<String> arguments) async {
  final profileId = arguments.isEmpty
      ? CipherProfiles.active.profileId
      : arguments.first;
  final profile = CipherProfiles.byId(profileId);
  if (profile == null) {
    stderr.writeln('Unknown cipher profile "$profileId".');
    exitCode = 2;
    return;
  }

  try {
    final report = await Sqlite3mcLoader.requireVerified(profile: profile);
    final output = <String, Object?>{
      'passed': report.passed,
      'platform': Platform.operatingSystem,
      'runtimeVersion': report.runtime.version,
      'libraryPath': report.runtime.libraryPath,
      'cipherPragmaAvailable': report.runtime.cipherPragmaAvailable,
      'profileId': report.profileId,
      'encryptedHeader': report.encryptedHeader,
      'reopenedWithKey': report.reopenedWithKey,
      'wrongKeyRejected': report.wrongKeyRejected,
      'tempStore': report.tempStore,
      'pageSize': report.pageSize,
      'rowCount': report.rowCount,
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
    };
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
    if (!report.passed) exitCode = 1;
  } catch (error) {
    stderr.writeln('E0 verification failed: $error');
    exitCode = 1;
  }
}
