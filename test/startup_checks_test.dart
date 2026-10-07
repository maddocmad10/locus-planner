// A broken database must be detected at startup, before optional work runs.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/db/startup_checks.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('locus_startup_'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('a healthy database passes', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await verifyDatabaseReady(db);
    await db.close();
  });

  test('a corrupt database file is reported instead of failing later', () async {
    final file = File('${dir.path}${Platform.pathSeparator}corrupt.db');
    file.writeAsBytesSync(List<int>.generate(4096, (i) => (i * 31 + 7) & 0xff));

    final db = AppDatabase.forTesting(NativeDatabase(file));
    await expectLater(verifyDatabaseReady(db), throwsA(anything));
    await closeQuietly(db);
  });

  test('closeQuietly accepts null and already-closed databases', () async {
    await closeQuietly(null);

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.close();
    await closeQuietly(db);
  });
}
