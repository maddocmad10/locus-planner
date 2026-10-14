import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

void main() {
  test('single instance guard allows the first acquisition', () async {
    if (!Platform.isWindows) {
      return;
    }

    try {
      expect(
  await SingleInstanceService.acquire(),
  true,
);
    } finally {
      SingleInstanceService.release();
    }
  });
}
