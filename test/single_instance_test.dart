import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/services/single_instance_service.dart';

void main() {
  tearDown(() async {
    await SingleInstanceService.release();
  });

  test('single instance guard allows the first acquisition', () async {
    if (!Platform.isWindows) {
      return;
    }

    expect(
      await SingleInstanceService.acquire(),
      false,
    );
  });

  test('second acquisition fails while first instance owns lock', () async {
    if (!Platform.isWindows) {
      return;
    }

    expect(
      await SingleInstanceService.acquire(),
      false,
    );

    expect(
      await SingleInstanceService.acquire(),
      false,
    );
  });

  test('release allows acquisition again', () async {
    if (!Platform.isWindows) {
      return;
    }

    expect(
      await SingleInstanceService.acquire(),
      false,
    );

    await SingleInstanceService.release();

    expect(
      await SingleInstanceService.acquire(),
      false,
    );
  });
}
