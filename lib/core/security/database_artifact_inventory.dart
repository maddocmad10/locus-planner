import 'dart:io';

import 'package:path/path.dart' as p;

import 'database_file_inspector.dart';
import 'database_paths.dart';

/// Discovered lifecycle artifacts next to the live database.
///
/// Filenames alone never decide which file is the active database. This
/// inventory exists so startup can reason about leftovers explicitly instead of
/// silently ignoring or deleting them:
///
/// * conversion and rotation candidates (`.encrypting-*`, `.rotating-*`)
///   without a journal are a recovery situation;
/// * atomic-write temporaries (`.tmp-*`, `.copy-*`, `.move-*.tmp`) are safe to
///   remove only after a successful classification and only when no journal is
///   still being recovered;
/// * quarantine directories are retained evidence, never cleaned automatically;
/// * sidecars are part of the same lifecycle as the main file.
class DatabaseArtifactInventory {
  const DatabaseArtifactInventory({
    required this.conversionCandidates,
    required this.atomicTemporaries,
    required this.quarantineDirectories,
    required this.sidecars,
    required this.hasJournal,
  });

  final List<File> conversionCandidates;
  final List<File> atomicTemporaries;
  final List<Directory> quarantineDirectories;
  final List<File> sidecars;

  /// A migration, restore or rotation journal still exists.
  final bool hasJournal;

  bool get hasUnjournaledConversionCandidate =>
      conversionCandidates.isNotEmpty && !hasJournal;

  static Future<DatabaseArtifactInventory> scan(DatabasePaths paths) async {
    final directory = paths.dataDirectory;
    final databaseBase = p.basename(paths.databaseFile.path);
    final sidecars = <File>[
      for (final file in DatabaseFileInspector.sidecars(paths.databaseFile))
        if (file.existsSync()) file,
    ];

    final candidates = <File>[];
    final temporaries = <File>[];
    if (await directory.exists()) {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('$databaseBase.')) continue;
        if (name.startsWith('$databaseBase.encrypting-') ||
            name.startsWith('$databaseBase.rotating-')) {
          candidates.add(entity);
        } else if (name.contains('.tmp-') ||
            name.contains('.copy-') ||
            (name.contains('.move-') && name.endsWith('.tmp'))) {
          temporaries.add(entity);
        }
      }
    }
    candidates.sort((a, b) => a.path.compareTo(b.path));
    temporaries.sort((a, b) => a.path.compareTo(b.path));

    final quarantine = <Directory>[];
    if (await paths.quarantineDirectory.exists()) {
      await for (final entity in paths.quarantineDirectory.list(
        followLinks: false,
      )) {
        if (entity is Directory) quarantine.add(entity);
      }
    }
    quarantine.sort((a, b) => a.path.compareTo(b.path));

    return DatabaseArtifactInventory(
      conversionCandidates: candidates,
      atomicTemporaries: temporaries,
      quarantineDirectories: quarantine,
      sidecars: sidecars,
      hasJournal:
          await paths.migrationJournalFile.exists() ||
          await paths.restoreJournalFile.exists() ||
          await paths.rotationJournalFile.exists(),
    );
  }

  /// Removes abandoned atomic-write siblings.
  ///
  /// Conversion candidates and quarantine evidence are deliberately preserved:
  /// they are inputs to recovery, not garbage. No file is removed while any
  /// journal still exists, because recovery may need every artifact.
  Future<int> cleanupAtomicTemporaries() async {
    if (hasJournal) return 0;
    var removed = 0;
    for (final file in atomicTemporaries) {
      try {
        if (await file.exists()) {
          await file.delete();
          removed++;
        }
      } on FileSystemException {
        // Another process may have removed it; leaving it is harmless.
      }
    }
    return removed;
  }
}
