import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('planning intelligence has no network or hosted-service dependency', () {
    final dirs = [
      Directory('lib/features/planning_intelligence'),
      Directory('lib/core/planning'),
    ];
    final network = RegExp(
      r"package:(http|dio|web_socket_channel|grpc)/"
      r'|HttpClient|WebSocket|Socket\.connect|https?://',
    );
    final offenders = <String>[];
    for (final dir in dirs) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        if (network.hasMatch(source)) offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Planning content must stay local. Remove network code from: '
          '${offenders.join(', ')}',
    );
  });
}
