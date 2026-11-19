import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/app_clock.dart';
import 'atomic_file.dart';
import 'database_file_inspector.dart';
import 'database_lifecycle_lock.dart';
import 'database_metadata.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'restore_journal.dart';

/// Durable request to abandon the current database and create a new one.
class StartFreshRequest {
  const StartFreshRequest({
    required this.requestedAt,
    required this.quarantineDirectory,
    required this.previousDatabaseId,
    required this.previousKeyId,
    required this.previousKeyGeneration,
    required this.previousCipherProfileId,
    this.stage = StartFreshStage.requested,
  });

  static const format = 'locus.start-fresh';
  static const formatVersion = 1;

  final DateTime requestedAt;
  final String quarantineDirectory;
  final String previousDatabaseId;
  final String previousKeyId;
  final int previousKeyGeneration;
  final String previousCipherProfileId;
  final StartFreshStage stage;

  bool get isApplied => stage == StartFreshStage.applied;

  StartFreshRequest advance(StartFreshStage next) => StartFreshRequest(
    requestedAt: requestedAt,
    quarantineDirectory: quarantineDirectory,
    previousDatabaseId: previousDatabaseId,
    previousKeyId: previousKeyId,
    previousKeyGeneration: previousKeyGeneration,
    previousCipherProfileId: previousCipherProfileId,
    stage: next,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'formatVersion': formatVersion,
    'requestedAt': requestedAt.toUtc().toIso8601String(),
    'quarantineDirectory': quarantineDirectory,
    'previousDatabaseId': previousDatabaseId,
    'previousKeyId': previousKeyId,
    'previousKeyGeneration': previousKeyGeneration,
    'previousCipherProfileId': previousCipherProfileId,
    'stage': stage.name,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static StartFreshRequest decode(String source) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The start-fresh request is not valid JSON.',
        cause: error,
      );
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != format ||
        decoded['formatVersion'] != formatVersion) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'Unsupported start-fresh request.',
      );
    }
    final stage = StartFreshStage.fromName(decoded['stage'] as String?);
    final requestedAt = decoded['requestedAt'];
    final quarantine = decoded['quarantineDirectory'];
    final databaseId = decoded['previousDatabaseId'];
    final keyId = decoded['previousKeyId'];
    final generation = decoded['previousKeyGeneration'];
    final profile = decoded['previousCipherProfileId'];
    if (stage == null ||
        requestedAt is! String ||
        quarantine is! String ||
        databaseId is! String ||
        keyId is! String ||
        generation is! int ||
        profile is! String) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The start-fresh request is incomplete.',
      );
    }
    final requested = DateTime.tryParse(requestedAt);
    if (requested == null) {
      throw const DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The start-fresh request has an invalid time.',
      );
    }
    return StartFreshRequest(
      requestedAt: requested,
      quarantineDirectory: quarantine,
      previousDatabaseId: databaseId,
      previousKeyId: keyId,
      previousKeyGeneration: generation,
      previousCipherProfileId: profile,
      stage: stage,
    );
  }
}

enum StartFreshStage {
  requested,
  applied;

  static StartFreshStage? fromName(String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}

class StartFreshRequestStore {
  StartFreshRequestStore(this.file);

  final File file;

  Future<bool> get exists => file.exists();

  Future<StartFreshRequest?> read() async {
    if (!await file.exists()) return null;
    try {
      return StartFreshRequest.decode(await file.readAsString());
    } on FileSystemException catch (error) {
      throw DatabaseSecurityException(
        DatabaseSecurityErrorCode.metadataCorrupt,
        'The start-fresh request could not be read.',
        cause: error,
      );
    }
  }

  Future<void> write(StartFreshRequest request) =>
      AtomicFile.writeString(file, request.encode());

  Future<void> clear() => AtomicFile.deleteIfExists(file);
}

/// Quarantines the current database and lets the normal fresh-install path
/// create a new identity.
class StartFreshService {
  const StartFreshService();

  Future<StartFreshRequest> request({required DatabasePaths paths}) async {
    final lock = DatabaseLifecycleLock(paths.lifecycleLockFile);
    return lock.withLock(DatabaseLockMode.exclusive, () async {
      final store = StartFreshRequestStore(paths.startFreshRequestFile);
      if (await store.exists) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'A start-fresh request is already pending. Restart Locus to finish '
          'it.',
        );
      }
      if (await RestoreJournalStore(paths.restoreJournalFile).exists) {
        throw const DatabaseSecurityException(
          DatabaseSecurityErrorCode.recoveryRequired,
          'A restore is staged. Finish or cancel it before starting fresh.',
        );
      }
      final metadata = await DatabaseMetadataStore(paths.metadataFile).read();
      final stamp = AppClock.now().microsecondsSinceEpoch;
      final request = StartFreshRequest(
        requestedAt: AppClock.now().toUtc(),
        quarantineDirectory: p.join(
          paths.quarantineDirectory.path,
          'start-fresh-$stamp',
        ),
        previousDatabaseId: metadata?.databaseId ?? '',
        previousKeyId: metadata?.activeKeyId ?? '',
        previousKeyGeneration: metadata?.keyGeneration ?? 0,
        previousCipherProfileId: metadata?.cipherProfileId ?? '',
      );
      await store.write(request);
      return request;
    });
  }

  /// Moves the old files aside. Called from DatabaseBootstrap while the
  /// exclusive lifecycle lock is held.
  Future<bool> applyIfRequestedLocked({required DatabasePaths paths}) async {
    final store = StartFreshRequestStore(paths.startFreshRequestFile);
    final request = await store.read();
    if (request == null) return false;
    if (request.isApplied) {
      // A previous attempt created the new database but did not clear the
      // request. Treat the new identity as success.
      final metadata = await DatabaseMetadataStore(paths.metadataFile).read();
      if (metadata != null &&
          metadata.databaseId != request.previousDatabaseId) {
        await store.clear();
        return false;
      }
    }

    final quarantine = Directory(request.quarantineDirectory);
    await quarantine.create(recursive: true);
    final quarantinedDatabase = File(
      p.join(quarantine.path, p.basename(paths.databaseFile.path)),
    );
    if (await paths.databaseFile.exists() &&
        !await quarantinedDatabase.exists()) {
      await DatabaseFileInspector.quarantine(paths.databaseFile, quarantine);
    }
    for (final file in <File>[
      paths.metadataFile,
      paths.migrationJournalFile,
      paths.rotationJournalFile,
      paths.restoreJournalFile,
    ]) {
      if (!await file.exists()) continue;
      final target = File(p.join(quarantine.path, p.basename(file.path)));
      if (await target.exists()) await AtomicFile.deleteIfExists(target);
      await file.rename(target.path);
    }
    final attachments = Directory(
      p.join(paths.dataDirectory.path, 'attachments'),
    );
    final quarantinedAttachments = Directory(
      p.join(quarantine.path, 'attachments'),
    );
    if (await attachments.exists() && !await quarantinedAttachments.exists()) {
      await attachments.rename(quarantinedAttachments.path);
    }

    await AtomicFile.writeString(
      File(p.join(quarantine.path, 'manifest.json')),
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'reason': 'start-fresh',
        'requestedAt': request.requestedAt.toUtc().toIso8601String(),
        'previousDatabaseId': request.previousDatabaseId,
        'previousKeyId': request.previousKeyId,
        'previousKeyGeneration': request.previousKeyGeneration,
        'previousCipherProfileId': request.previousCipherProfileId,
        'note':
            'Old key records and recovery envelopes were preserved. Delete '
            'this directory only after the new database is verified.',
      }),
    );
    await store.write(request.advance(StartFreshStage.applied));
    return true;
  }

  /// Clears the request after the new database has opened successfully.
  Future<void> completeIfApplied({required DatabasePaths paths}) async {
    final store = StartFreshRequestStore(paths.startFreshRequestFile);
    final request = await store.read();
    if (request == null || !request.isApplied) return;
    final metadata = await DatabaseMetadataStore(paths.metadataFile).read();
    if (metadata == null || metadata.databaseId == request.previousDatabaseId) {
      return;
    }
    await store.clear();
  }
}
