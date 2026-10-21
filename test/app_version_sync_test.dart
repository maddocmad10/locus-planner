import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/data_export_service.dart';

void main() {
  test('fallback app version stays synchronized with pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml must declare a version.');
    expect(
      DataExportService.fallbackAppVersion,
      match!.group(1),
      reason: 'Update fallbackAppVersion when changing pubspec.yaml version.',
    );
  });
}
