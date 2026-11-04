import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';

enum MigrationStage {
  notStarted,
  precheckOk,
  snapshotCreated,
  keyCreated,
  tempCreated,
  encryptionApplied,
  encryptedDatabaseVerified,
  databaseReplaced,
  metadataCommitted,
  migrationComplete,
}

/// Durable record of a plaintext-to-encrypted conversion or a key rotation.
///
/// Startup uses the journal, file existence, file header, key availability and
/// checksums together; no single signal is enough to guess what happened.
class MigrationJournal {
  const MigrationJournal({
    required this.databaseId,
    required this.stage,
    required this.sourcePath,
    required this.sourceSidecars,
    required this.newKeyId,
    required this.newKeyGeneration,
    required this.cipherProfileId,
    required this.startedAt,
    required this.updatedAt,
    this.oldKeyId,
    this.backupPath,
    this.tempPath,
    this.quarantinePath,
    this.sourceChecksum,
    this.tempChecksum,
    this.pid,
  });

  static const formatVersion = 1;

  final String databaseId;
  final MigrationStage stage;
  final String sourcePath;
  final List<String> sourceSidecars;
  final String? backupPath;
  final String? tempPath;
  final String? quarantinePath;
  final String? oldKeyId;
  final String newKeyId;
  final int newKeyGeneration;
  final String cipherProfileId;
  final String? sourceChecksum;
  final String? tempChecksum;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int? pid;

  bool get isComplete => stage == MigrationStage.migrationComplete;

  bool reached(MigrationStage other) => stage.index >= other.index;

  MigrationJournal advance(MigrationStage next, {DateTime? at}) =>
      MigrationJournal(
        databaseId: databaseId,
        stage: next,
        sourcePath: sourcePath,
        sourceSidecars: sourceSidecars,
        backupPath: backupPath,
        tempPath: tempPath,
        quarantinePath: quarantinePath,
        oldKeyId: oldKeyId,
        newKeyId: newKeyId,
        newKeyGeneration: newKeyGeneration,
        cipherProfileId: cipherProfileId,
        sourceChecksum: sourceChecksum,
        tempChecksum: tempChecksum,
        startedAt: startedAt,
        updatedAt: at ?? AppClock.now().toUtc(),
        pid: pid,
      );

  MigrationJournal copyWith({
    String? backupPath,
    String? tempPath,
    String? quarantinePath,
    String? oldKeyId,
    String? sourceChecksum,
    String? tempChecksum,
  }) => MigrationJournal(
    databaseId: databaseId,
    stage: stage,
    sourcePath: sourcePath,
    sourceSidecars: sourceSidecars,
    backupPath: backupPath ?? this.backupPath,
    tempPath: tempPath ?? this.tempPath,
    quarantinePath: quarantinePath ?? this.quarantinePath,
    oldKeyId: oldKeyId ?? this.oldKeyId,
    newKeyId: newKeyId,
    newKeyGeneration: newKeyGeneration,
    cipherProfileId: cipherProfileId,
    sourceChecksum: sourceChecksum ?? this.sourceChecksum,
    tempChecksum: tempChecksum ?? this.tempChecksum,
    startedAt: startedAt,
    updatedAt: AppClock.now().toUtc(),
    pid: pid,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'formatVersion': formatVersion,
    'databaseId': databaseId,
    'stage': stage.name,
    'sourcePath': sourcePath,
    'sourceSidecars': sourceSidecars,
    'backupPath': backupPath,
    'tempPath': tempPath,
    'quarantinePath': quarantinePath,
    'oldKeyId': oldKeyId,
    'newKeyId': newKeyId,
    'newKeyGeneration': newKeyGeneration,
    'cipherProfileId': cipherProfileId,
    'sourceChecksum': sourceChecksum,
    'tempChecksum': tempChecksum,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'pid': pid,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static MigrationJournal decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The migration journal is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The migration journal must be a JSON object.',
      );
    }
    final stageName = decoded['stage'];
    MigrationStage? stage;
    for (final value in MigrationStage.values) {
      if (value.name == stageName) {
        stage = value;
        break;
      }
    }
    final format = decoded['formatVersion'];
    if (format != formatVersion || stage == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The migration journal has an unsupported format or stage.',
      );
    }
    final startedAt = DateTime.tryParse('${decoded['startedAt']}');
    final updatedAt = DateTime.tryParse('${decoded['updatedAt']}');
    if (startedAt == null || updatedAt == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The migration journal has invalid timestamps.',
      );
    }
    final sidecars = decoded['sourceSidecars'];
    return MigrationJournal(
      databaseId: '${decoded['databaseId']}',
      stage: stage,
      sourcePath: '${decoded['sourcePath']}',
      sourceSidecars: sidecars is List
          ? sidecars.whereType<String>().toList()
          : const <String>[],
      backupPath: decoded['backupPath'] as String?,
      tempPath: decoded['tempPath'] as String?,
      quarantinePath: decoded['quarantinePath'] as String?,
      oldKeyId: decoded['oldKeyId'] as String?,
      newKeyId: '${decoded['newKeyId']}',
      newKeyGeneration: decoded['newKeyGeneration'] is int
          ? decoded['newKeyGeneration'] as int
          : 0,
      cipherProfileId: '${decoded['cipherProfileId']}',
      sourceChecksum: decoded['sourceChecksum'] as String?,
      tempChecksum: decoded['tempChecksum'] as String?,
      startedAt: startedAt,
      updatedAt: updatedAt,
      pid: decoded['pid'] as int?,
    );
  }
}

class MigrationJournalStore {
  MigrationJournalStore(this.file);

  final File file;

  Future<bool> get exists => file.exists();

  Future<MigrationJournal?> read() async {
    if (!await file.exists()) return null;
    return MigrationJournal.decode(await file.readAsString());
  }

  Future<void> write(MigrationJournal journal) =>
      AtomicFile.writeString(file, journal.encode());

  Future<void> clear() => AtomicFile.deleteIfExists(file);
}
