import 'dart:io';

import 'package:path/path.dart' as p;

import 'atomic_file.dart';
import 'database_file_inspector.dart';
import 'database_paths.dart';

class PlaintextArtifact {
  const PlaintextArtifact({
    required this.path,
    required this.label,
    required this.bytes,
    required this.modifiedAt,
  });

  final String path;
  final String label;
  final int bytes;
  final DateTime modifiedAt;
}

/// Enumerates leftover plaintext copies of the database.
///
/// Nothing here is removed automatically. D12 requires every artifact to be
/// labeled and deleted only after the user has verified the encrypted database
/// and explicitly confirmed the cleanup.
class PlaintextArtifactService {
  const PlaintextArtifactService();

  Future<List<PlaintextArtifact>> list(DatabasePaths paths) async {
    final live = paths.databaseFile.absolute.path;
    final seen = <String>{};
    final artifacts = <PlaintextArtifact>[];

    Future<void> add(File file, String label) async {
      final absolute = file.absolute.path;
      if (absolute == live || !seen.add(absolute)) return;
      if (!await file.exists()) return;
      artifacts.add(
        PlaintextArtifact(
          path: absolute,
          label: label,
          bytes: await file.length(),
          modifiedAt: (await file.stat()).modified,
        ),
      );
    }

    final legacy = paths.legacyDocumentsFile;
    if (legacy != null) {
      await add(legacy, 'Legacy plaintext database in Documents');
    }

    final backups = paths.backupsDirectory;
    if (await backups.exists()) {
      await for (final entity in backups.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        if (!p.basename(entity.path).contains('.plaintext.bak')) continue;
        if (await DatabaseFileInspector.classify(entity) !=
            DatabaseFileKind.plaintext) {
          continue;
        }
        await add(entity, 'Pre-encryption plaintext backup');
      }
    }

    final quarantine = paths.quarantineDirectory;
    if (await quarantine.exists()) {
      await for (final entity in quarantine.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name != DatabasePaths.databaseFileName && !name.endsWith('.bak')) {
          continue;
        }
        if (await DatabaseFileInspector.classify(entity) !=
            DatabaseFileKind.plaintext) {
          continue;
        }
        await add(entity, 'Quarantined plaintext database');
      }
    }

    artifacts.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return artifacts;
  }

  Future<void> delete(DatabasePaths paths, PlaintextArtifact artifact) async {
    final live = paths.databaseFile.absolute.path;
    final metadata = paths.metadataFile.absolute.path;
    final target = File(artifact.path).absolute.path;
    if (target == live || target == metadata) {
      throw const FileSystemException(
        'Refusing to delete the live database or its metadata.',
      );
    }
    final dataRoot = paths.dataDirectory.absolute.path;
    final legacy = paths.legacyDocumentsFile?.absolute.path;
    final withinData = p.isWithin(dataRoot, target);
    final isLegacy = legacy != null && target == legacy;
    if (!withinData && !isLegacy) {
      throw const FileSystemException(
        'Refusing to delete a file outside the managed data locations.',
      );
    }
    await AtomicFile.deleteIfExists(File(target));
  }
}
