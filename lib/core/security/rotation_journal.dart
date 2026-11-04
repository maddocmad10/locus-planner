import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';

/// Durable stages of a DEK rotation.
///
/// Rotation is not a recovery-passphrase change: the database is re-encrypted
/// with a new key while the old key and a pre-rotation copy are retained until
/// the new database has been verified.
enum RotationStage {
  planned,
  backupCreated,
  backupVerified,
  keyCreated,
  candidateCreated,
  candidateVerified,
  replacementStarted,
  replacementCompleted,
  metadataCommitted,
  completed,
  rollbackStarted,
  rolledBack,
  recoveryRequired;

  static RotationStage? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class RotationJournal {
  const RotationJournal({
    required this.rotationId,
    required this.databaseId,
    required this.stage,
    required this.sourcePath,
    required this.oldKeyId,
    required this.oldGeneration,
    required this.newKeyId,
    required this.newGeneration,
    required this.cipherProfileId,
    required this.startedAt,
    required this.updatedAt,
    this.backupPath,
    this.candidatePath,
    this.sourceChecksum,
    this.candidateChecksum,
    this.lastErrorCode,
    this.pid,
  });

  static const formatVersion = 1;

  final String rotationId;
  final String databaseId;
  final RotationStage stage;
  final String sourcePath;
  final String? backupPath;
  final String? candidatePath;
  final String oldKeyId;
  final int oldGeneration;
  final String newKeyId;
  final int newGeneration;
  final String cipherProfileId;
  final String? sourceChecksum;
  final String? candidateChecksum;
  final String? lastErrorCode;
  final DateTime startedAt;
  final DateTime updatedAt;
  final int? pid;

  bool get isComplete => stage == RotationStage.completed;

  bool get needsRecovery => !isComplete && stage != RotationStage.rolledBack;

  bool reached(RotationStage other) => stage.index >= other.index;

  RotationJournal advance(RotationStage next, {DateTime? at}) {
    final recovering =
        stage == RotationStage.recoveryRequired ||
        stage == RotationStage.rollbackStarted ||
        stage == RotationStage.rolledBack;
    if (next.index < stage.index && !recovering) {
      throw StateError(
        'Rotation journal cannot move backwards from ${stage.name} to '
        '${next.name}.',
      );
    }
    return _copy(stage: next, updatedAt: at ?? AppClock.now().toUtc());
  }

  RotationJournal fail(String code) => _copy(
    stage: RotationStage.recoveryRequired,
    lastErrorCode: code,
    updatedAt: AppClock.now().toUtc(),
  );

  RotationJournal _copy({
    RotationStage? stage,
    String? backupPath,
    String? candidatePath,
    String? sourceChecksum,
    String? candidateChecksum,
    String? lastErrorCode,
    DateTime? updatedAt,
  }) => RotationJournal(
    rotationId: rotationId,
    databaseId: databaseId,
    stage: stage ?? this.stage,
    sourcePath: sourcePath,
    backupPath: backupPath ?? this.backupPath,
    candidatePath: candidatePath ?? this.candidatePath,
    oldKeyId: oldKeyId,
    oldGeneration: oldGeneration,
    newKeyId: newKeyId,
    newGeneration: newGeneration,
    cipherProfileId: cipherProfileId,
    sourceChecksum: sourceChecksum ?? this.sourceChecksum,
    candidateChecksum: candidateChecksum ?? this.candidateChecksum,
    lastErrorCode: lastErrorCode ?? this.lastErrorCode,
    startedAt: startedAt,
    updatedAt: updatedAt ?? AppClock.now().toUtc(),
    pid: pid,
  );

  RotationJournal copyWith({
    String? backupPath,
    String? candidatePath,
    String? sourceChecksum,
    String? candidateChecksum,
  }) => _copy(
    backupPath: backupPath,
    candidatePath: candidatePath,
    sourceChecksum: sourceChecksum,
    candidateChecksum: candidateChecksum,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'formatVersion': formatVersion,
    'rotationId': rotationId,
    'databaseId': databaseId,
    'stage': stage.name,
    'sourcePath': sourcePath,
    'backupPath': backupPath,
    'candidatePath': candidatePath,
    'oldKeyId': oldKeyId,
    'oldGeneration': oldGeneration,
    'newKeyId': newKeyId,
    'newGeneration': newGeneration,
    'cipherProfileId': cipherProfileId,
    'sourceChecksum': sourceChecksum,
    'candidateChecksum': candidateChecksum,
    'lastErrorCode': lastErrorCode,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'pid': pid,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static RotationJournal decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The rotation journal is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The rotation journal must be a JSON object.',
      );
    }
    final stage = RotationStage.fromName(decoded['stage'] as String?);
    if (decoded['formatVersion'] != formatVersion || stage == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The rotation journal has an unsupported format or stage.',
      );
    }
    final startedAt = DateTime.tryParse('${decoded['startedAt']}');
    final updatedAt = DateTime.tryParse('${decoded['updatedAt']}');
    if (startedAt == null || updatedAt == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.migrationInterrupted,
        'The rotation journal has invalid timestamps.',
      );
    }
    return RotationJournal(
      rotationId: '${decoded['rotationId']}',
      databaseId: '${decoded['databaseId']}',
      stage: stage,
      sourcePath: '${decoded['sourcePath']}',
      backupPath: decoded['backupPath'] as String?,
      candidatePath: decoded['candidatePath'] as String?,
      oldKeyId: '${decoded['oldKeyId']}',
      oldGeneration: decoded['oldGeneration'] is int
          ? decoded['oldGeneration'] as int
          : 0,
      newKeyId: '${decoded['newKeyId']}',
      newGeneration: decoded['newGeneration'] is int
          ? decoded['newGeneration'] as int
          : 0,
      cipherProfileId: '${decoded['cipherProfileId']}',
      sourceChecksum: decoded['sourceChecksum'] as String?,
      candidateChecksum: decoded['candidateChecksum'] as String?,
      lastErrorCode: decoded['lastErrorCode'] as String?,
      startedAt: startedAt,
      updatedAt: updatedAt,
      pid: decoded['pid'] as int?,
    );
  }
}

class RotationJournalStore {
  RotationJournalStore(this.file);

  final File file;

  Future<bool> get exists => file.exists();

  Future<RotationJournal?> read() async {
    if (!await file.exists()) return null;
    return RotationJournal.decode(await file.readAsString());
  }

  Future<void> write(RotationJournal journal) =>
      AtomicFile.writeString(file, journal.encode());

  Future<void> clear() => AtomicFile.deleteIfExists(file);
}
