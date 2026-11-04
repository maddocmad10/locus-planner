import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';

/// Durable stages of a database conversion or key rotation.
///
/// Every irreversible file operation must be preceded by a journal write, and
/// the next stage must only be recorded after the previous operation is known
/// to have completed.
enum MigrationStage {
  planned,
  precheckOk,
  backupCreated,
  backupVerified,
  keyCreated,
  quarantinePlanned,
  originalQuarantined,
  conversionStarted,
  conversionCompleted,
  destinationVerified,
  replacementStarted,
  replacementCompleted,
  metadataCommitted,
  identityVerified,
  completed,
  rollbackStarted,
  rolledBack,
  recoveryRequired;

  /// Names used by journals written before this stage model existed.
  static const notStarted = planned;
  static const snapshotCreated = backupCreated;
  static const migrationComplete = completed;

  static MigrationStage? fromName(String? name) {
    final legacy = switch (name) {
      'notStarted' => planned,
      'snapshotCreated' => backupCreated,
      'tempCreated' => conversionStarted,
      'encryptionApplied' => conversionCompleted,
      'encryptedDatabaseVerified' => destinationVerified,
      'databaseReplaced' => replacementCompleted,
      'migrationComplete' => completed,
      _ => null,
    };
    if (legacy != null) return legacy;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
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
    this.migrationId,
    this.sourceSchemaVersion,
    this.targetSchemaVersion,
    this.oldKeyId,
    this.backupPath,
    this.tempPath,
    this.quarantinePath,
    this.sourceChecksum,
    this.tempChecksum,
    this.lastErrorCode,
    this.pid,
  });

  static const formatVersion = 1;

  final String? migrationId;
  final String databaseId;
  final MigrationStage stage;
  final String sourcePath;
  final List<String> sourceSidecars;
  final int? sourceSchemaVersion;
  final int? targetSchemaVersion;
  final String? backupPath;
  final String? tempPath;
  final String? quarantinePath;
  final String? oldKeyId;
  final String newKeyId;
  final int newKeyGeneration;
  final String cipherProfileId;
  final String? sourceChecksum;
  final String? tempChecksum;
  final String? lastErrorCode;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int? pid;

  bool get isComplete => stage == MigrationStage.completed;

  bool get needsRecovery => !isComplete && stage != MigrationStage.rolledBack;

  bool reached(MigrationStage other) => stage.index >= other.index;

  MigrationJournal advance(MigrationStage next, {DateTime? at}) {
    final recovering =
        stage == MigrationStage.recoveryRequired ||
        stage == MigrationStage.rollbackStarted ||
        stage == MigrationStage.rolledBack;
    if (next.index < stage.index && !recovering) {
      throw StateError(
        'Migration journal cannot move backwards from ${stage.name} to '
        '${next.name}.',
      );
    }
    return _copy(stage: next, updatedAt: at ?? AppClock.now().toUtc());
  }

  /// Records a recoverable failure without losing the last safe stage.
  MigrationJournal fail(String code) => _copy(
    stage: MigrationStage.recoveryRequired,
    lastErrorCode: code,
    updatedAt: AppClock.now().toUtc(),
  );

  MigrationJournal _copy({
    MigrationStage? stage,
    String? migrationId,
    int? sourceSchemaVersion,
    int? targetSchemaVersion,
    String? backupPath,
    String? tempPath,
    String? quarantinePath,
    String? oldKeyId,
    String? sourceChecksum,
    String? tempChecksum,
    String? lastErrorCode,
    DateTime? updatedAt,
  }) => MigrationJournal(
    migrationId: migrationId ?? this.migrationId,
    databaseId: databaseId,
    stage: stage ?? this.stage,
    sourcePath: sourcePath,
    sourceSidecars: sourceSidecars,
    sourceSchemaVersion: sourceSchemaVersion ?? this.sourceSchemaVersion,
    targetSchemaVersion: targetSchemaVersion ?? this.targetSchemaVersion,
    backupPath: backupPath ?? this.backupPath,
    tempPath: tempPath ?? this.tempPath,
    quarantinePath: quarantinePath ?? this.quarantinePath,
    oldKeyId: oldKeyId ?? this.oldKeyId,
    newKeyId: newKeyId,
    newKeyGeneration: newKeyGeneration,
    cipherProfileId: cipherProfileId,
    sourceChecksum: sourceChecksum ?? this.sourceChecksum,
    tempChecksum: tempChecksum ?? this.tempChecksum,
    lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    startedAt: startedAt,
    updatedAt: updatedAt ?? AppClock.now().toUtc(),
    pid: pid,
  );

  MigrationJournal copyWith({
    String? migrationId,
    int? sourceSchemaVersion,
    int? targetSchemaVersion,
    String? backupPath,
    String? tempPath,
    String? quarantinePath,
    String? oldKeyId,
    String? sourceChecksum,
    String? tempChecksum,
    String? lastErrorCode,
  }) => _copy(
    migrationId: migrationId,
    sourceSchemaVersion: sourceSchemaVersion,
    targetSchemaVersion: targetSchemaVersion,
    backupPath: backupPath,
    tempPath: tempPath,
    quarantinePath: quarantinePath,
    oldKeyId: oldKeyId,
    sourceChecksum: sourceChecksum,
    tempChecksum: tempChecksum,
    lastErrorCode: lastErrorCode,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'formatVersion': formatVersion,
    'migrationId': migrationId,
    'databaseId': databaseId,
    'stage': stage.name,
    'sourcePath': sourcePath,
    'sourceSidecars': sourceSidecars,
    'sourceSchemaVersion': sourceSchemaVersion,
    'targetSchemaVersion': targetSchemaVersion,
    'backupPath': backupPath,
    'tempPath': tempPath,
    'quarantinePath': quarantinePath,
    'oldKeyId': oldKeyId,
    'newKeyId': newKeyId,
    'newKeyGeneration': newKeyGeneration,
    'cipherProfileId': cipherProfileId,
    'sourceChecksum': sourceChecksum,
    'tempChecksum': tempChecksum,
    'lastErrorCode': lastErrorCode,
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
    final stage = MigrationStage.fromName(decoded['stage'] as String?);
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
      migrationId: decoded['migrationId'] as String?,
      databaseId: '${decoded['databaseId']}',
      stage: stage,
      sourcePath: '${decoded['sourcePath']}',
      sourceSidecars: sidecars is List
          ? sidecars.whereType<String>().toList()
          : const <String>[],
      sourceSchemaVersion: decoded['sourceSchemaVersion'] as int?,
      targetSchemaVersion: decoded['targetSchemaVersion'] as int?,
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
      lastErrorCode: decoded['lastErrorCode'] as String?,
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
