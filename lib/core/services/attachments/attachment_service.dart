import 'dart:io';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../db/app_database.dart';
import '../../utils/app_clock.dart';
import '../undo_service.dart';
import 'attachment_images.dart';
import 'attachment_store.dart';
import 'attachment_types.dart';

/// Database-backed attachment operations. Blob bytes live in [AttachmentStore];
/// this service owns validation, limits, metadata rows and Undo.
class AttachmentService {
  AttachmentService(this._db, this._store, {this.undo, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final AttachmentStore _store;
  final UndoService? undo;
  final Uuid _uuid;

  AttachmentStore get store => _store;

  /// Prepares the disk layout, removes temporary plaintext copies and expires
  /// orphaned blobs. Safe to call once at startup and in tests.
  Future<void> initialize() async {
    await _store.prepare();
    await purgeExpiredOrphans();
    await _sweepUntrackedFiles();
  }

  Future<List<Attachment>> forTodo(String todoId) {
    return (_db.select(_db.attachments)
          ..where((row) => row.todoId.equals(todoId))
          ..orderBy(_ordering))
        .get();
  }

  Future<List<Attachment>> forEvent(String eventId) {
    return (_db.select(_db.attachments)
          ..where((row) => row.eventId.equals(eventId))
          ..orderBy(_ordering))
        .get();
  }

  Stream<List<Attachment>> watchForTodo(String todoId) {
    return (_db.select(_db.attachments)
          ..where((row) => row.todoId.equals(todoId))
          ..orderBy(_ordering))
        .watch();
  }

  Stream<List<Attachment>> watchForEvent(String eventId) {
    return (_db.select(_db.attachments)
          ..where((row) => row.eventId.equals(eventId))
          ..orderBy(_ordering))
        .watch();
  }

  /// Position decides the user's order; the tie-breakers keep that order
  /// deterministic when Undo reinserts a row at the same position.
  static List<OrderingTerm Function($AttachmentsTable)> get _ordering => [
    (row) => OrderingTerm.asc(row.position),
    (row) => OrderingTerm.asc(row.createdAt),
    (row) => OrderingTerm.asc(row.id),
  ];

  /// True when the sealed blob for [sha256Hex] exists on this device.
  Future<bool> hasBlob(String sha256Hex) => _store.hasBlob(sha256Hex);

  /// Whether the user pinned this blob against phone cache eviction.
  Future<bool> isPinned(String sha256Hex) async {
    final row = await (_db.select(
      _db.attachmentBlobs,
    )..where((t) => t.sha256.equals(sha256Hex))).getSingleOrNull();
    return row?.pinned ?? false;
  }

  /// Pins or unpins a local blob. Pinned blobs survive the LRU eviction pass.
  Future<void> setPinned(String sha256Hex, bool pinned) async {
    final size = await _store.blobLength(sha256Hex);
    await _db.customStatement(
      'INSERT INTO attachment_blobs '
      '(sha256, size_bytes, state, pinned) VALUES (?, ?, ?, ?) '
      'ON CONFLICT(sha256) DO UPDATE SET pinned = excluded.pinned',
      [
        sha256Hex,
        size ?? 0,
        size == null ? 'missing' : 'present',
        pinned ? 1 : 0,
      ],
    );
  }

  Future<bool> keepOriginalEnabled() async =>
      await _db.getSetting(AttachmentRules.keepOriginalSettingKey) == '1';

  Future<void> setKeepOriginal(bool enabled) async {
    await _db.setSetting(
      AttachmentRules.keepOriginalSettingKey,
      enabled ? '1' : '0',
    );
  }

  Future<Attachment> importFile({
    required File file,
    String? todoId,
    String? eventId,
    String? displayName,
    bool? keepOriginal,
  }) async {
    final length = await file.length();
    if (length > AttachmentRules.maxFileBytes) {
      throw const AttachmentImportException(
        'Files larger than 25 MB are not supported.',
      );
    }
    final bytes = await file.readAsBytes();
    return importBytes(
      bytes: bytes,
      fileName: displayName ?? file.uri.pathSegments.last,
      todoId: todoId,
      eventId: eventId,
      keepOriginal: keepOriginal,
    );
  }

  Future<Attachment> importBytes({
    required Uint8List bytes,
    required String fileName,
    String? todoId,
    String? eventId,
    bool? keepOriginal,
  }) async {
    if ((todoId == null) == (eventId == null)) {
      throw const AttachmentImportException(
        'An attachment must belong to exactly one item.',
      );
    }
    if (bytes.isEmpty) {
      throw const AttachmentImportException('This file is empty.');
    }
    if (bytes.length > AttachmentRules.maxFileBytes) {
      throw const AttachmentImportException(
        'Files larger than 25 MB are not supported.',
      );
    }

    final existing = await _countForParent(todoId: todoId, eventId: eventId);
    if (existing >= AttachmentRules.maxPerItem) {
      throw const AttachmentImportException(
        'This item already has the maximum of 20 attachments.',
      );
    }

    final display = AttachmentRules.sanitizeDisplayName(fileName);
    final sniffed = AttachmentMime.sniff(bytes);
    if (AttachmentMime.isDangerous(sniffed, display)) {
      throw const AttachmentImportException(
        'Executable and script files cannot be attached.',
      );
    }

    final wantsOriginal = keepOriginal ?? await keepOriginalEnabled();
    Uint8List storedBytes = bytes;
    Uint8List? thumbnail;
    int? width;
    int? height;
    var mimeType = sniffed.mimeType;
    var kind = sniffed.kind;

    if (sniffed.isImage) {
      final processed = await processImageBytes(
        bytes,
        keepOriginal: wantsOriginal,
      );
      if (!processed.isSuccess) {
        throw AttachmentImportException(processed.error!);
      }
      storedBytes = processed.bytes!;
      thumbnail = processed.thumbnail;
      width = processed.width;
      height = processed.height;
      mimeType = AttachmentImageOutput.mimeOf(
        storedBytes,
        keepOriginal: wantsOriginal,
      );
    }

    final sha256Hex = await _store.putBytes(storedBytes);
    if (thumbnail != null) {
      await _store.putThumb(sha256Hex, thumbnail);
    }

    final now = AppClock.now();
    await _db
        .into(_db.attachmentBlobs)
        .insertOnConflictUpdate(
          AttachmentBlobsCompanion.insert(
            sha256: sha256Hex,
            sizeBytes: storedBytes.length,
            state: const Value('present'),
            hasThumb: Value(thumbnail != null),
            lastAccessedAt: Value(now),
            orphanedAt: const Value(null),
          ),
        );

    final position = await _nextPosition(todoId: todoId, eventId: eventId);
    final attachment = Attachment(
      id: _uuid.v4(),
      todoId: todoId,
      eventId: eventId,
      kind: kind,
      displayName: display,
      mimeType: mimeType,
      sizeBytes: storedBytes.length,
      sha256: sha256Hex,
      width: width,
      height: height,
      position: position,
      createdAt: now,
      updatedAt: now,
    );
    await _db.into(_db.attachments).insert(attachment);
    await refreshOrphans();
    return attachment;
  }

  /// Removes the metadata row immediately but keeps the blob for the Undo
  /// window and the seven-day orphan grace period.
  Future<void> remove(String attachmentId) async {
    final rows = await (_db.select(
      _db.attachments,
    )..where((row) => row.id.equals(attachmentId))).get();
    if (rows.isEmpty) return;
    final attachment = rows.single;
    await (_db.delete(
      _db.attachments,
    )..where((row) => row.id.equals(attachmentId))).go();
    await refreshOrphans();
    undo?.offer(
      label: 'Attachment removed',
      restore: () async {
        await _db.into(_db.attachments).insert(attachment);
        await refreshOrphans();
      },
    );
  }

  /// Decrypts a blob to a temporary file for the OS handler. The copy is
  /// deleted at exit and at the next startup.
  Future<File> open(Attachment attachment) async {
    final file = await _store.materialize(
      attachment.sha256,
      attachment.displayName,
    );
    await (_db.update(_db.attachmentBlobs)
          ..where((row) => row.sha256.equals(attachment.sha256)))
        .write(AttachmentBlobsCompanion(lastAccessedAt: Value(AppClock.now())));
    return file;
  }

  Future<Uint8List?> thumbnail(Attachment attachment) =>
      _store.readThumb(attachment.sha256);

  /// Verified plaintext bytes. Throws [AttachmentBlobCorruptException] when
  /// the file is missing, fails authentication or no longer matches its hash.
  Future<Uint8List> readBytes(Attachment attachment) =>
      _store.readBytes(attachment.sha256);

  /// Marks hashes with no live attachment row, and clears the mark when Undo
  /// or a sync brings the row back.
  Future<void> refreshOrphans() async {
    final now = AppClock.now().millisecondsSinceEpoch;
    await _db.customStatement(
      'UPDATE attachment_blobs SET orphaned_at = ? '
      'WHERE orphaned_at IS NULL '
      'AND sha256 NOT IN (SELECT sha256 FROM attachments)',
      [now],
    );
    await _db.customStatement(
      'UPDATE attachment_blobs SET orphaned_at = NULL '
      'WHERE orphaned_at IS NOT NULL '
      'AND sha256 IN (SELECT sha256 FROM attachments)',
    );
  }

  /// Deletes files whose metadata row vanished more than the grace period ago.
  Future<int> purgeExpiredOrphans() async {
    final cutoff = AppClock.now()
        .subtract(AttachmentRules.orphanGrace)
        .millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          'SELECT sha256 FROM attachment_blobs '
          'WHERE orphaned_at IS NOT NULL AND orphaned_at < ?',
          variables: [Variable.withInt(cutoff)],
        )
        .get();
    for (final row in rows) {
      await _store.deleteBlob(row.read<String>('sha256'));
    }
    if (rows.isNotEmpty) {
      await _db.customStatement(
        'DELETE FROM attachment_blobs '
        'WHERE orphaned_at IS NOT NULL AND orphaned_at < ?',
        [cutoff],
      );
    }
    return rows.length;
  }

  Future<bool> isOverSoftQuota() async =>
      await _store.totalBlobBytes() > AttachmentRules.softQuotaBytes;

  Future<int> _countForParent({String? todoId, String? eventId}) async {
    final rows =
        await (_db.select(_db.attachments)..where(
              (row) => todoId != null
                  ? row.todoId.equals(todoId)
                  : row.eventId.equals(eventId!),
            ))
            .get();
    return rows.length;
  }

  Future<int> _nextPosition({String? todoId, String? eventId}) async {
    final maxPosition = _db.attachments.position.max();
    final query = _db.selectOnly(_db.attachments)..addColumns([maxPosition]);
    if (todoId != null) {
      query.where(_db.attachments.todoId.equals(todoId));
    } else if (eventId != null) {
      query.where(_db.attachments.eventId.equals(eventId));
    }
    final row = await query.getSingle();
    // Start at 0 for the first attachment and never reuse a position, so a
    // delete followed by an add cannot reorder the remaining rows.
    return (row.read(maxPosition) ?? -1) + 1;
  }

  Future<void> _sweepUntrackedFiles() async {
    final rows = await _db.select(_db.attachmentBlobs).get();
    final tracked = {for (final row in rows) _store.crypto.fileId(row.sha256)};
    final untracked = await _store.untrackedFileIds(tracked);
    final cutoff = AppClock.now().subtract(const Duration(hours: 1));
    for (final path in untracked) {
      final file = File(path);
      final stat = await file.stat();
      if (stat.modified.isBefore(cutoff)) {
        await _store.deleteByPath(path);
      }
    }
  }
}

/// MIME type of the bytes actually stored. Keeping the original preserves the
/// original container; downscaling always writes JPEG or PNG.
class AttachmentImageOutput {
  const AttachmentImageOutput._();

  static String mimeOf(Uint8List bytes, {required bool keepOriginal}) {
    return AttachmentMime.sniff(bytes).mimeType;
  }
}
