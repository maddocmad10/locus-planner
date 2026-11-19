import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/security/database_file_inspector.dart';
import 'package:locus_planner/core/security/database_paths.dart';
import 'package:locus_planner/core/security/plaintext_artifact_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late DatabasePaths paths;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('locus-plaintext-');
    final data = Directory(p.join(directory.path, 'data'));
    await data.create(recursive: true);
    final legacy = File(p.join(directory.path, 'documents.db'));
    paths = DatabasePaths(
      dataDirectory: data,
      databaseFile: File(p.join(data.path, 'locus_planner.db')),
      legacyDocumentsFile: legacy,
    );
    await paths.databaseFile.writeAsBytes(<int>[
      ...DatabaseFileInspector.sqliteHeader.codeUnits,
      ...List.filled(64, 1),
    ], flush: true);
    await legacy.writeAsBytes(<int>[
      ...DatabaseFileInspector.sqliteHeader.codeUnits,
      ...List.filled(64, 2),
    ], flush: true);
    final backup = File(
      p.join(data.path, 'backups', 'pre-encryption', 'old.plaintext.bak'),
    );
    await backup.parent.create(recursive: true);
    await backup.writeAsBytes(<int>[
      ...DatabaseFileInspector.sqliteHeader.codeUnits,
      ...List.filled(64, 3),
    ], flush: true);
    final quarantined = File(
      p.join(data.path, 'quarantine', 'start-fresh-1', 'locus_planner.db'),
    );
    await quarantined.parent.create(recursive: true);
    await quarantined.writeAsBytes(<int>[
      ...DatabaseFileInspector.sqliteHeader.codeUnits,
      ...List.filled(64, 4),
    ], flush: true);
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('lists plaintext artifacts but never the live database', () async {
    final artifacts = await const PlaintextArtifactService().list(paths);
    expect(artifacts, hasLength(3));
    expect(
      artifacts.map((artifact) => artifact.label),
      containsAll(<String>[
        'Legacy plaintext database in Documents',
        'Pre-encryption plaintext backup',
        'Quarantined plaintext database',
      ]),
    );
    expect(
      artifacts.any((artifact) => artifact.path == paths.databaseFile.path),
      isFalse,
    );
  });

  test('deletes a reviewed copy and refuses the live database', () async {
    final artifacts = await const PlaintextArtifactService().list(paths);
    final legacy = artifacts.firstWhere(
      (artifact) => artifact.label.startsWith('Legacy'),
    );
    await const PlaintextArtifactService().delete(paths, legacy);
    expect((await const PlaintextArtifactService().list(paths)), hasLength(2));

    await expectLater(
      const PlaintextArtifactService().delete(
        paths,
        PlaintextArtifact(
          path: paths.databaseFile.path,
          label: 'live',
          bytes: 0,
          modifiedAt: DateTime.now(),
        ),
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await paths.databaseFile.exists(), isTrue);
  });
}
