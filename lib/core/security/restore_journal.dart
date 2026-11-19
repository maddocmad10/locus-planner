import 'dart:convert';
import 'dart:io';

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_security_errors.dart';

/// Durable state of a raw database restore that is waiting for a restart.
enum RestoreStage {
  staged,
  applied;

  static RestoreStage? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

/// Crash-safe record of a staged `.locusrecovery` restore.
///
/// The journal is written before any live file is touched. It records both the
/// target identity and the previous identity so a failed swap can be rolled
/// back without guessing.
class RestoreJournal {
  const RestoreJournal({
    required this.packageSha256,
    required this.stagedDirectory,
    required this.quarantineDirectory,
    required this.databaseId,
    required this.keyId,
    required this.keyGeneration,
    required this.cipherProfileId,
    required this.databaseSha256,
    required this.databaseBytes,
    required this.schemaVersion,
    required this.attachmentsIncluded,
    required this.attachmentCount,
    required this.previousDatabaseId,
    required this.previousKeyId,
    required this.previousKeyGeneration,
    required this.previousCipherProfileId,
    required this.previousDatabaseFile,
    required this.startedAt,
    required this.updatedAt,
    this.replaceAttachmentStore = false,
    this.stage = RestoreStage.staged,
    this.lastErrorCode,
  });

  static const format = 'locus.restore.journal';
  static const formatVersion = 1;

  final String packageSha256;
  final String stagedDirectory;
  final String quarantineDirectory;
  final String databaseId;
  final String keyId;
  final int keyGeneration;
  final String cipherProfileId;
  final String databaseSha256;
  final int databaseBytes;
  final int schemaVersion;
  final bool attachmentsIncluded;
  final int attachmentCount;
  final bool replaceAttachmentStore;
  final String previousDatabaseId;
  final String previousKeyId;
  final int previousKeyGeneration;
  final String previousCipherProfileId;
  final String previousDatabaseFile;
  final DateTime startedAt;
  final DateTime updatedAt;
  final RestoreStage stage;
  final String? lastErrorCode;

  bool get isComplete => stage == RestoreStage.applied;

  RestoreJournal advance(RestoreStage next, {DateTime? at}) =>
      _copy(stage: next, updatedAt: at ?? AppClock.now().toUtc());

  RestoreJournal fail(String code) =>
      _copy(lastErrorCode: code, updatedAt: AppClock.now().toUtc());

  RestoreJournal _copy({
    RestoreStage? stage,
    String? lastErrorCode,
    DateTime? updatedAt,
  }) => RestoreJournal(
    packageSha256: packageSha256,
    stagedDirectory: stagedDirectory,
    quarantineDirectory: quarantineDirectory,
    databaseId: databaseId,
    keyId: keyId,
    keyGeneration: keyGeneration,
    cipherProfileId: cipherProfileId,
    databaseSha256: databaseSha256,
    databaseBytes: databaseBytes,
    schemaVersion: schemaVersion,
    attachmentsIncluded: attachmentsIncluded,
    attachmentCount: attachmentCount,
    replaceAttachmentStore: replaceAttachmentStore,
    previousDatabaseId: previousDatabaseId,
    previousKeyId: previousKeyId,
    previousKeyGeneration: previousKeyGeneration,
    previousCipherProfileId: previousCipherProfileId,
    previousDatabaseFile: previousDatabaseFile,
    startedAt: startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    stage: stage ?? this.stage,
    lastErrorCode: lastErrorCode ?? this.lastErrorCode,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'formatVersion': formatVersion,
    'packageSha256': packageSha256,
    'stagedDirectory': stagedDirectory,
    'quarantineDirectory': quarantineDirectory,
    'databaseId': databaseId,
    'keyId': keyId,
    'keyGeneration': keyGeneration,
    'cipherProfileId': cipherProfileId,
    'databaseSha256': databaseSha256,
    'databaseBytes': databaseBytes,
    'schemaVersion': schemaVersion,
    'attachmentsIncluded': attachmentsIncluded,
    'attachmentCount': attachmentCount,
    'replaceAttachmentStore': replaceAttachmentStore,
    'previousDatabaseId': previousDatabaseId,
    'previousKeyId': previousKeyId,
    'previousKeyGeneration': previousKeyGeneration,
    'previousCipherProfileId': previousCipherProfileId,
    'previousDatabaseFile': previousDatabaseFile,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'stage': stage.name,
    'lastErrorCode': lastErrorCode,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static RestoreJournal decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['formatVersion'] != formatVersion) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Unsupported restore journal.',
      );
    }
    final stage = RestoreStage.fromName(decoded['stage'] as String?);
    if (stage == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal has an invalid stage.',
      );
    }
    return RestoreJournal(
      packageSha256: _string(decoded, 'packageSha256'),
      stagedDirectory: _string(decoded, 'stagedDirectory'),
      quarantineDirectory: _string(decoded, 'quarantineDirectory'),
      databaseId: _string(decoded, 'databaseId'),
      keyId: _string(decoded, 'keyId'),
      keyGeneration: _int(decoded, 'keyGeneration'),
      cipherProfileId: _string(decoded, 'cipherProfileId'),
      databaseSha256: _string(decoded, 'databaseSha256'),
      databaseBytes: _int(decoded, 'databaseBytes'),
      schemaVersion: _int(decoded, 'schemaVersion'),
      attachmentsIncluded: decoded['attachmentsIncluded'] == true,
      attachmentCount: _int(decoded, 'attachmentCount'),
      replaceAttachmentStore: decoded['replaceAttachmentStore'] == true,
      previousDatabaseId: _string(decoded, 'previousDatabaseId'),
      previousKeyId: _string(decoded, 'previousKeyId'),
      previousKeyGeneration: _int(decoded, 'previousKeyGeneration'),
      previousCipherProfileId: _string(decoded, 'previousCipherProfileId'),
      previousDatabaseFile: _string(decoded, 'previousDatabaseFile'),
      startedAt: _date(decoded, 'startedAt'),
      updatedAt: _date(decoded, 'updatedAt'),
      stage: stage,
      lastErrorCode: decoded['lastErrorCode'] is String
          ? decoded['lastErrorCode'] as String
          : null,
    );
  }

  static String _string(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal is missing "$key".',
      );
    }
    return value;
  }

  static int _int(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! int) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal is missing "$key".',
      );
    }
    return value;
  }

  static DateTime _date(Map<String, dynamic> json, String key) {
    final value = json[key];
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal has an invalid "$key".',
      );
    }
    return parsed;
  }
}

class RestoreJournalStore {
  RestoreJournalStore(this.file);

  final File file;

  Future<bool> get exists => file.exists();

  Future<RestoreJournal?> read() async {
    if (!await file.exists()) return null;
    try {
      return RestoreJournal.decode(await file.readAsString());
    } on FileSystemException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The restore journal could not be read.',
        cause: error,
      );
    }
  }

  Future<void> write(RestoreJournal journal) =>
      AtomicFile.writeString(file, journal.encode());

  Future<void> clear() => AtomicFile.deleteIfExists(file);
}
