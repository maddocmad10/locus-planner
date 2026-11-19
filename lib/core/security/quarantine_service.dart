import 'dart:io';

import 'package:path/path.dart' as p;

import 'database_paths.dart';

class QuarantineArtifact {
  const QuarantineArtifact({
    required this.path,
    required this.name,
    required this.bytes,
    required this.modifiedAt,
  });

  final String path;
  final String name;
  final int bytes;
  final DateTime modifiedAt;
}

/// Read and explicit-cleanup operations for quarantined recovery artifacts.
///
/// Nothing is deleted automatically. The user must review and confirm each
/// removal from the recovery card.
class QuarantineService {
  const QuarantineService();

  Future<List<QuarantineArtifact>> list(DatabasePaths paths) async {
    final root = paths.quarantineDirectory;
    if (!await root.exists()) return const [];
    final artifacts = <QuarantineArtifact>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory && entity is! File) continue;
      final stat = await entity.stat();
      artifacts.add(
        QuarantineArtifact(
          path: entity.path,
          name: p.basename(entity.path),
          bytes: await _size(entity),
          modifiedAt: stat.modified,
        ),
      );
    }
    artifacts.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    return artifacts;
  }

  Future<void> delete(DatabasePaths paths, String artifactPath) async {
    final root = paths.quarantineDirectory.absolute.path;
    final target = File(artifactPath).absolute.path;
    final parent = p.dirname(target);
    if (p.normalize(parent) != p.normalize(root)) {
      throw const FileSystemException(
        'Refusing to delete an artifact outside the quarantine directory.',
      );
    }
    final name = p.basename(target);
    if (name.isEmpty || name == '.' || name == '..') {
      throw const FileSystemException('Refusing to delete that path.');
    }
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(target).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await File(target).delete();
    }
  }

  static Future<int> _size(FileSystemEntity entity) async {
    if (entity is File) {
      try {
        return await entity.length();
      } on FileSystemException {
        return 0;
      }
    }
    if (entity is Directory) {
      var total = 0;
      await for (final child in entity.list(
        recursive: true,
        followLinks: false,
      )) {
        if (child is! File) continue;
        try {
          total += await child.length();
        } on FileSystemException {
          // A locked file is counted as zero.
        }
      }
      return total;
    }
    return 0;
  }
}
