import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../db/database_maintenance.dart';
import '../services/attachments/attachment_crypto.dart';
import '../services/attachments/attachment_key_store.dart';
import '../utils/app_clock.dart';
import 'cipher_profile.dart';
import 'database_file_inspector.dart';
import 'database_identity.dart';
import 'database_metadata.dart';
import 'database_parity_verifier.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'recovery_envelope.dart';
import 'recovery_package_manifest.dart';
import 'sqlite3mc.dart';

/// Thrown when a recovery package cannot be built, read or verified.
class RecoveryPackageException implements Exception {
  const RecoveryPackageException(this.message);

  final String message;

  @override
  String toString() => 'RecoveryPackageException: $message';
}

class RecoveryPackageCreateResult {
  const RecoveryPackageCreateResult({
    required this.file,
    required this.manifest,
    required this.archiveSha256,
    required this.archiveBytes,
  });

  final File file;
  final RecoveryPackageManifest manifest;
  final String archiveSha256;
  final int archiveBytes;
}

/// Builds and verifies self-contained raw database recovery packages.
///
/// A package is a ZIP file with a fixed layout:
///
/// ```text
/// manifest.json                 non-secret identity + checksums
/// recovery.json                 RecoveryBundle (DEK + attachment key)
/// database/locus_planner.db     encrypted VACUUM INTO snapshot
/// attachments/ab/<file-id>      sealed attachment blobs (optional)
/// attachments/thumbs/<id>.t     sealed thumbnails (optional)
/// ```
///
/// The database snapshot is produced with `VACUUM INTO`, so it is a consistent
/// encrypted copy even while the planner is running. Nothing in the package is
/// plaintext: the manifest contains hashes and identifiers only.
class RecoveryPackageService {
  const RecoveryPackageService();

  static const extension = 'locusrecovery';
  static const minPassphraseLength = 10;

  Future<RecoveryPackageCreateResult> create({
    required DatabasePaths paths,
    required DatabaseMetadata metadata,
    required Uint8List dek,
    required String passphrase,
    required File target,
    required AttachmentKeyStore attachmentKeyStore,
    bool includeAttachments = true,
    int iterations = RecoveryEnvelopeService.defaultIterations,
    DateTime? createdAt,
  }) async {
    if (passphrase.trim().length < minPassphraseLength) {
      throw const RecoveryPackageException(
        'Use a recovery passphrase of at least $minPassphraseLength characters.',
      );
    }
    if (dek.length != 32) {
      throw const RecoveryPackageException('The database key is invalid.');
    }
    final profile = CipherProfiles.byId(metadata.cipherProfileId);
    if (profile == null) {
      throw const RecoveryPackageException(
        'This build does not support the database cipher profile.',
      );
    }
    if (!await paths.databaseFile.exists()) {
      throw const RecoveryPackageException(
        'The encrypted database file is missing.',
      );
    }

    final stamp = AppClock.now().microsecondsSinceEpoch;
    final work = Directory(
      p.join(paths.dataDirectory.path, 'recovery', 'work-$stamp'),
    );
    await work.create(recursive: true);
    try {
      final snapshot = File(p.join(work.path, 'locus_planner.db'));
      final schemaVersion = _snapshotDatabase(
        paths.databaseFile,
        snapshot,
        profile,
        dek,
      );
      final header = await snapshot.open();
      try {
        final prefix = await header.read(16);
        if (String.fromCharCodes(prefix) ==
            DatabaseFileInspector.sqliteHeader) {
          throw const RecoveryPackageException(
            'The database snapshot unexpectedly has a plaintext header.',
          );
        }
      } finally {
        await header.close();
      }

      final databaseSha256 = await _fileSha256(snapshot);
      final databaseBytes = await snapshot.length();

      final attachmentPlan = includeAttachments
          ? await _collectAttachments(
              paths: paths,
              metadata: metadata,
              dek: dek,
              profile: profile,
              store: attachmentKeyStore,
            )
          : const _AttachmentPlan(
              key: null,
              entries: <_AttachmentSource>[],
              missing: 0,
            );

      final bundle = await RecoveryEnvelopeService.seal(
        dek: dek,
        databaseId: metadata.databaseId,
        keyId: metadata.activeKeyId,
        keyGeneration: metadata.keyGeneration,
        cipherProfileId: metadata.cipherProfileId,
        passphrase: passphrase,
        attachmentKey: attachmentPlan.key,
        iterations: iterations,
        createdAt: createdAt,
      );

      final manifest = RecoveryPackageManifest(
        createdAt: createdAt ?? AppClock.now().toUtc(),
        databaseId: metadata.databaseId,
        keyId: metadata.activeKeyId,
        keyGeneration: metadata.keyGeneration,
        cipherProfileId: metadata.cipherProfileId,
        databaseFile: p.basename(paths.databaseFile.path),
        databaseSha256: databaseSha256,
        databaseBytes: databaseBytes,
        schemaVersion: schemaVersion,
        attachmentsIncluded: attachmentPlan.entries.isNotEmpty,
        attachments: [
          for (final entry in attachmentPlan.entries)
            RecoveryPackageAttachment(
              archivePath: entry.archivePath,
              sha256: entry.sha256,
              sealedSha256: entry.sealedSha256,
              bytes: entry.bytes,
              thumbnail: entry.thumbnail,
            ),
        ],
        skippedAttachmentCount: attachmentPlan.missing,
      );

      final manifestFile = File(p.join(work.path, 'manifest.json'));
      final envelopeFile = File(p.join(work.path, 'recovery.json'));
      await manifestFile.writeAsString(manifest.encode(), flush: true);
      await envelopeFile.writeAsString(bundle.encode(), flush: true);

      await target.parent.create(recursive: true);
      final encoder = ZipFileEncoder();
      encoder.create(target.path);
      try {
        await encoder.addFile(manifestFile, 'manifest.json', 9);
        await encoder.addFile(envelopeFile, 'recovery.json', 9);
        await encoder.addFile(
          snapshot,
          RecoveryPackageManifest.databaseEntry,
          ZipFileEncoder.store,
        );
        for (final entry in attachmentPlan.entries) {
          await encoder.addFile(
            entry.file,
            entry.archivePath,
            ZipFileEncoder.store,
          );
        }
      } finally {
        await encoder.close();
      }

      // Never report success for a package that cannot be reopened.
      await verify(archive: target, passphrase: passphrase);
      return RecoveryPackageCreateResult(
        file: target,
        manifest: manifest,
        archiveSha256: await _fileSha256(target),
        archiveBytes: await target.length(),
      );
    } on RecoveryPackageException {
      await _deleteIfExists(target);
      rethrow;
    } catch (error) {
      await _deleteIfExists(target);
      if (error is DatabaseSecurityException ||
          error is FormatException ||
          error is FileSystemException ||
          error is AttachmentBlobCorruptException) {
        throw RecoveryPackageException(
          'The recovery package could not be created: ${_describe(error)}',
        );
      }
      rethrow;
    } finally {
      await _deleteDirectory(work);
    }
  }

  /// Reads and fully verifies a package without keeping its contents.
  Future<RecoveryPackageManifest> verify({
    required File archive,
    required String passphrase,
  }) async {
    final temp = await Directory.systemTemp.createTemp('locus-verify-');
    try {
      return await extractAndVerify(
        archive: archive,
        passphrase: passphrase,
        destination: temp,
      );
    } finally {
      await _deleteDirectory(temp);
    }
  }

  /// Extracts a package into [destination] and verifies every byte.
  ///
  /// The caller owns [destination]; a failed verification may leave partial
  /// files there, and the caller is expected to delete the directory.
  Future<RecoveryPackageManifest> extractAndVerify({
    required File archive,
    required String passphrase,
    required Directory destination,
  }) async {
    if (!await archive.exists() || await archive.length() == 0) {
      throw const RecoveryPackageException(
        'The recovery package is missing or empty.',
      );
    }
    if (passphrase.isEmpty) {
      throw const RecoveryPackageException('Enter the recovery passphrase.');
    }
    final input = InputFileStream(archive.path);
    try {
      final decoded = ZipDecoder().decodeStream(input);
      final entries = <String, ArchiveFile>{};
      for (final entry in decoded.files) {
        if (!entry.isFile) continue;
        final name = entry.name;
        if (!_safeArchivePath(name)) {
          throw const RecoveryPackageException(
            'The recovery package contains an unsafe path.',
          );
        }
        if (entries.containsKey(name)) {
          throw const RecoveryPackageException(
            'The recovery package contains a duplicate entry.',
          );
        }
        entries[name] = entry;
      }

      final manifestEntry = entries['manifest.json'];
      final envelopeEntry = entries['recovery.json'];
      final databaseEntry = entries[RecoveryPackageManifest.databaseEntry];
      if (manifestEntry == null ||
          envelopeEntry == null ||
          databaseEntry == null) {
        throw const RecoveryPackageException(
          'The recovery package is incomplete.',
        );
      }

      final RecoveryPackageManifest manifest;
      final RecoveryBundle bundle;
      try {
        manifest = RecoveryPackageManifest.decode(
          utf8.decode(manifestEntry.readBytes() ?? const <int>[]),
        );
        bundle = RecoveryBundle.decode(
          utf8.decode(envelopeEntry.readBytes() ?? const <int>[]),
        );
      } on FormatException catch (error) {
        throw RecoveryPackageException(error.message);
      }
      _requireMatchingIdentity(manifest, bundle);

      await destination.create(recursive: true);
      final manifestFile = File(p.join(destination.path, 'manifest.json'));
      final envelopeFile = File(p.join(destination.path, 'recovery.json'));
      await _extract(manifestEntry, manifestFile);
      await _extract(envelopeEntry, envelopeFile);
      final databaseFile = File(p.join(destination.path, 'locus_planner.db'));
      await _extract(databaseEntry, databaseFile);
      if (await databaseFile.length() != manifest.databaseBytes) {
        throw const RecoveryPackageException(
          'The database snapshot has the wrong size.',
        );
      }
      if (await _fileSha256(databaseFile) != manifest.databaseSha256) {
        throw const RecoveryPackageException(
          'The database snapshot failed its checksum.',
        );
      }

      final OpenedRecoveryBundle opened;
      try {
        opened = await RecoveryEnvelopeService.open(bundle, passphrase);
      } on DatabaseSecurityException catch (error) {
        throw RecoveryPackageException(
          'The recovery passphrase is wrong, or the envelope is damaged '
          '(${error.codeName}).',
        );
      }

      for (final attachment in manifest.attachments) {
        final entry = entries[attachment.archivePath];
        if (entry == null) {
          throw const RecoveryPackageException(
            'The recovery package is missing an attachment file.',
          );
        }
        final file = File(p.join(destination.path, attachment.archivePath));
        await _extract(entry, file);
        if (await file.length() != attachment.bytes) {
          throw const RecoveryPackageException(
            'An attachment has the wrong size.',
          );
        }
        if (await _fileSha256(file) != attachment.sealedSha256) {
          throw const RecoveryPackageException(
            'An attachment failed its checksum.',
          );
        }
        final key = opened.attachmentKey;
        if (key == null) {
          throw const RecoveryPackageException(
            'The recovery package does not contain the attachment key.',
          );
        }
        final plainSha = await AttachmentCrypto(key).sealedFileSha256(file);
        if (!attachment.thumbnail && plainSha != attachment.sha256) {
          throw const RecoveryPackageException(
            'An attachment failed its content check.',
          );
        }
      }

      _verifyDatabase(
        databaseFile: databaseFile,
        manifest: manifest,
        opened: opened,
      );
      return manifest;
    } on RecoveryPackageException {
      rethrow;
    } on DatabaseSecurityException catch (error) {
      throw RecoveryPackageException(
        'The recovery package failed verification (${error.codeName}).',
      );
    } on FormatException catch (error) {
      throw RecoveryPackageException(
        'The recovery package is malformed: ${error.message}',
      );
    } on FileSystemException catch (error) {
      throw RecoveryPackageException(
        'The recovery package could not be read: ${error.message}.',
      );
    } on AttachmentBlobCorruptException catch (error) {
      throw RecoveryPackageException(error.message);
    } finally {
      await input.close();
    }
  }

  int _snapshotDatabase(
    File source,
    File target,
    CipherProfile profile,
    Uint8List dek,
  ) {
    final db = SqliteRuntime.open(source.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, dek);
      // Committed WAL frames are visible to VACUUM INTO. A busy checkpoint is
      // not fatal; the snapshot itself still sees a consistent transaction.
      try {
        db.select('PRAGMA wal_checkpoint(TRUNCATE)');
      } catch (_) {
        // Keep going: VACUUM INTO reads through the WAL.
      }
      final escaped = target.path.replaceAll("'", "''");
      db.execute("VACUUM INTO '$escaped'");
      final rows = db.select('PRAGMA user_version');
      return rows.isEmpty ? 0 : rows.first['user_version'] as int;
    } finally {
      db.dispose();
    }
  }

  Future<_AttachmentPlan> _collectAttachments({
    required DatabasePaths paths,
    required DatabaseMetadata metadata,
    required Uint8List dek,
    required CipherProfile profile,
    required AttachmentKeyStore store,
  }) async {
    final db = SqliteRuntime.open(paths.databaseFile.path);
    final hashes = <String>{};
    try {
      SqliteCipherRuntime.applyKey(db, profile, dek);
      for (final row in db.select(
        'SELECT sha256 FROM attachments '
        'UNION SELECT sha256 FROM attachment_blobs WHERE state = \'present\'',
      )) {
        final value = row['sha256'];
        if (value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
          hashes.add(value);
        }
      }
    } finally {
      db.dispose();
    }
    if (hashes.isEmpty) {
      return const _AttachmentPlan(
        key: null,
        entries: <_AttachmentSource>[],
        missing: 0,
      );
    }
    final key = await store.read();
    if (key == null) {
      throw const RecoveryPackageException(
        'The attachment key is unavailable, so attachment files cannot be '
        'included. Recreate the package with attachments off.',
      );
    }
    final crypto = AttachmentCrypto(key);
    final entries = <_AttachmentSource>[];
    var missing = 0;
    for (final sha in hashes) {
      final fileId = crypto.fileId(sha);
      final blob = File(
        p.join(paths.dataDirectory.path, 'attachments', 'ab', fileId),
      );
      final thumb = File(
        p.join(paths.dataDirectory.path, 'attachments', 'thumbs', '$fileId.t'),
      );
      if (!await blob.exists()) {
        missing++;
        continue;
      }
      entries.add(
        _AttachmentSource(
          file: blob,
          archivePath: 'attachments/ab/$fileId',
          sha256: sha,
          sealedSha256: await _fileSha256(blob),
          bytes: await blob.length(),
        ),
      );
      if (await thumb.exists()) {
        entries.add(
          _AttachmentSource(
            file: thumb,
            archivePath: 'attachments/thumbs/$fileId.t',
            sha256: '',
            sealedSha256: await _fileSha256(thumb),
            bytes: await thumb.length(),
            thumbnail: true,
          ),
        );
      }
    }
    return _AttachmentPlan(
      key: entries.isEmpty ? null : key,
      entries: entries,
      missing: missing,
    );
  }

  void _verifyDatabase({
    required File databaseFile,
    required RecoveryPackageManifest manifest,
    required OpenedRecoveryBundle opened,
  }) {
    final profile = CipherProfiles.byId(manifest.cipherProfileId);
    if (profile == null) {
      throw const RecoveryPackageException(
        'This build does not support the package cipher profile.',
      );
    }
    final db = SqliteRuntime.open(databaseFile.path);
    try {
      SqliteCipherRuntime.applyKey(db, profile, opened.dek);
      DatabaseParityVerifier.requireIntegrity(db);
      final identity = DatabaseIdentityStore.read(db);
      if (identity == null) {
        throw const RecoveryPackageException(
          'The database snapshot has no identity anchor.',
        );
      }
      if (identity.databaseId != manifest.databaseId ||
          identity.keyId != manifest.keyId ||
          identity.keyGeneration != manifest.keyGeneration ||
          identity.cipherProfileId != manifest.cipherProfileId) {
        throw const RecoveryPackageException(
          'The database identity does not match the recovery package.',
        );
      }
      final rows = db.select('PRAGMA user_version');
      final version = rows.isEmpty ? 0 : rows.first['user_version'] as int;
      if (version != manifest.schemaVersion) {
        throw const RecoveryPackageException(
          'The database schema version does not match the package manifest.',
        );
      }
      if (version > currentDatabaseSchemaVersion) {
        throw const RecoveryPackageException(
          'This package was created by a newer version of Locus.',
        );
      }
    } finally {
      db.dispose();
    }
  }

  static void _requireMatchingIdentity(
    RecoveryPackageManifest manifest,
    RecoveryBundle bundle,
  ) {
    if (manifest.databaseId != bundle.databaseId ||
        manifest.keyId != bundle.keyId ||
        manifest.keyGeneration != bundle.keyGeneration ||
        manifest.cipherProfileId != bundle.cipherProfileId) {
      throw const RecoveryPackageException(
        'The recovery envelope does not match the package manifest.',
      );
    }
  }

  static final _attachmentEntryPattern = RegExp(
    r'^attachments/(ab/[0-9a-f]{64}|thumbs/[0-9a-f]{64}\.t)$',
  );

  static bool _safeArchivePath(String name) {
    if (name.isEmpty || name.length > 256) return false;
    if (name.startsWith('/') ||
        name.contains(r'\') ||
        name.contains('\u0000')) {
      return false;
    }
    final segments = name.split('/');
    if (segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      return false;
    }
    return name == 'manifest.json' ||
        name == 'recovery.json' ||
        name == RecoveryPackageManifest.databaseEntry ||
        _attachmentEntryPattern.hasMatch(name);
  }

  static Future<void> _extract(ArchiveFile entry, File target) async {
    await target.parent.create(recursive: true);
    final output = OutputFileStream(target.path);
    try {
      entry.writeContent(output);
    } finally {
      await output.close();
    }
  }

  static Future<String> _fileSha256(File file) async {
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static String _describe(Object error) {
    if (error is FormatException) return error.message;
    if (error is DatabaseSecurityException) return error.message;
    if (error is FileSystemException) return error.message;
    if (error is AttachmentBlobCorruptException) return error.message;
    return error.toString();
  }

  static Future<void> _deleteIfExists(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best effort: the caller still gets the original failure.
    }
  }

  static Future<void> _deleteDirectory(Directory directory) async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on FileSystemException {
      // A locked temporary file is cleaned up by the OS or the next run.
    }
  }
}

class _AttachmentSource {
  const _AttachmentSource({
    required this.file,
    required this.archivePath,
    required this.sha256,
    required this.sealedSha256,
    required this.bytes,
    this.thumbnail = false,
  });

  final File file;
  final String archivePath;
  final String sha256;
  final String sealedSha256;
  final int bytes;
  final bool thumbnail;
}

class _AttachmentPlan {
  const _AttachmentPlan({
    required this.key,
    required this.entries,
    required this.missing,
  });

  final Uint8List? key;
  final List<_AttachmentSource> entries;
  final int missing;
}
