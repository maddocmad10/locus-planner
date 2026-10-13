import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

void main() {
  test('single instance guard allows the first acquisition', () {
    if (!Platform.isWindows) {
      return;
    }

    try {
      expect(SingleInstanceService.acquire(), isTrue);
    } finally {
      SingleInstanceService.release();
    }
  });
}
