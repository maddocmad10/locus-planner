import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  late Directory temp;
  late DateTime Function() originalClock;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('locus-db-backup-test-');
    originalClock = AppClock.now;
    AppClock.now = () => DateTime.utc(2026, 10, 21, 7, 0);
  });

  tearDown(() async {
    AppClock.now = originalClock;
    await temp.delete(recursive: true);
  });

  test('backup target version controls the snapshot name and cutoff', () async {
    final database = File('${temp.path}${Platform.pathSeparator}legacy.db');
    final source = sqlite3.sqlite3.open(database.path);
    source.execute('CREATE TABLE example (id INTEGER PRIMARY KEY)');
    source.execute('INSERT INTO example (id) VALUES (1)');
    source.execute('PRAGMA user_version = 3');
    source.dispose();

    final backupDirectory = Directory('${temp.path}/backups');
    await backupDatabaseBeforeUpgrade(
      database,
      targetVersion: 4,
      backupDirectory: backupDirectory,
    );

    final backups = backupDirectory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('pre-migration-v4-'))
        .toList();
    expect(backups, hasLength(1));
    final snapshot = sqlite3.sqlite3.open(backups.single.path);
    addTearDown(snapshot.dispose);
    expect(snapshot.select('SELECT id FROM example').single['id'], 1);
  });

  test('current-version database does not create a migration backup', () async {
    final database = File('${temp.path}${Platform.pathSeparator}current.db');
    final source = sqlite3.sqlite3.open(database.path);
    source.execute('CREATE TABLE example (id INTEGER PRIMARY KEY)');
    source.execute('PRAGMA user_version = 4');
    source.dispose();

    final backupDirectory = Directory('${temp.path}/backups');
    await backupDatabaseBeforeUpgrade(
      database,
      targetVersion: 4,
      backupDirectory: backupDirectory,
    );
    expect(await backupDirectory.exists(), isFalse);
  });
}
