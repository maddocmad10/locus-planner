// ignore_for_file: prefer_initializing_formals
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/services/attachments/attachment_service.dart';
import '../../../core/services/attachments/attachment_types.dart';
import '../../../core/utils/app_clock.dart';
import 'share_intake_service.dart';

/// Durable per-file outcome vocabulary stored in `share_intake_files`.
class ShareFileStatus {
  ShareFileStatus._();

  static const pending = 'pending';
  static const importing = 'importing';
  static const retryable = 'retryable';
  static const imported = 'imported';
  static const permanentlyRejected = 'permanently_rejected';
  static const userDiscarded = 'user_discarded';

  static const terminal = {imported, permanentlyRejected, userDiscarded};
  static const unfinished = {pending, importing, retryable};
}

/// One durable intake status stored in `share_intake_state`.
class ShareIntakeStatus {
  ShareIntakeStatus._();

  static const pending = 'pending';
  static const importing = 'importing';
  static const retryable = 'retryable';
  static const completed = 'completed';
  static const discarded = 'discarded';
}

/// Metadata/blob state for a deterministic share attachment id.
class ShareAttachmentInfo {
  const ShareAttachmentInfo({
    required this.id,
    required this.sha256,
    required this.blobPresent,
  });

  final String id;
  final String sha256;
  final bool blobPresent;
}

/// Import boundary for attachments, injectable so disk-full and kill/restart
/// scenarios can be tested without a real phone.
abstract class ShareAttachmentRepository {
  Future<ShareAttachmentInfo?> find(String attachmentId);

  Future<void> importFile({
    required File file,
    required String id,
    required String todoId,
    required String displayName,
  });

  Future<void> delete(String attachmentId);
}

class DatabaseShareAttachmentRepository implements ShareAttachmentRepository {
  DatabaseShareAttachmentRepository({
    required AppDatabase db,
    required AttachmentService attachments,
  }) : _db = db,
       _attachments = attachments;

  final AppDatabase _db;
  final AttachmentService _attachments;

  @override
  Future<ShareAttachmentInfo?> find(String attachmentId) async {
    final rows = await _db
        .customSelect(
          'SELECT id, sha256 FROM attachments WHERE id = ?',
          variables: [Variable.withString(attachmentId)],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    final sha = row.read<String>('sha256');
    return ShareAttachmentInfo(
      id: row.read<String>('id'),
      sha256: sha,
      blobPresent: await _attachments.hasBlob(sha),
    );
  }

  @override
  Future<void> importFile({
    required File file,
    required String id,
    required String todoId,
    required String displayName,
  }) async {
    await _attachments.importFile(
      file: file,
      id: id,
      todoId: todoId,
      displayName: displayName,
    );
  }

  @override
  Future<void> delete(String attachmentId) async {
    await _db.customStatement('DELETE FROM attachments WHERE id = ?', [
      attachmentId,
    ]);
    await _attachments.refreshOrphans();
  }
}

typedef ShareTaskCreator =
    Future<void> Function({
      required String id,
      required String title,
      required String? notes,
    });

/// A file the user still needs to retry or dismiss.
class ShareIntakeIssue {
  const ShareIntakeIssue({
    required this.intakeId,
    required this.title,
    required this.ordinal,
    required this.attachmentId,
    required this.name,
    required this.status,
    this.reason,
    this.reasonCode,
  });

  final String intakeId;
  final String title;
  final int ordinal;
  final String attachmentId;
  final String name;
  final String status;
  final String? reason;
  final String? reasonCode;

  bool get retryable => status == ShareFileStatus.retryable;

  String get label => reason == null || reason!.trim().isEmpty
      ? (reasonCode ?? 'Could not be added')
      : reason!;
}

class ShareIntakeImportResult {
  const ShareIntakeImportResult({
    required this.intakeId,
    required this.title,
    required this.completed,
    required this.acknowledgeNative,
    required this.replayed,
    required this.taskCreated,
    required this.taskKept,
    required this.importedFiles,
    required this.issues,
  });

  final String intakeId;
  final String title;

  /// True when every file has a terminal outcome.
  final bool completed;

  /// True when native staging may be removed. Permanent rejections stay
  /// discoverable (with their file names) until the user dismisses them.
  final bool acknowledgeNative;

  /// True when this was an idempotent replay of an already completed intake.
  final bool replayed;
  final bool taskCreated;
  final bool taskKept;
  final int importedFiles;
  final List<ShareIntakeIssue> issues;
}

class _PermanentFileRejection implements Exception {
  const _PermanentFileRejection(this.message, this.code);

  final String message;
  final String code;
}

/// Imports one staged Android share into exactly one task and one attachment
/// per file. The intake UUID is the task id and `<intake>-<ordinal>` is the
/// attachment id, so replaying after a crash is idempotent.
///
/// Every step writes a durable status before doing work. A transient failure
/// leaves both the staged bytes and the task in place and names the file in
/// [ShareIntakeIssue] so the phone can offer Retry.
class ShareIntakeImporter {
  ShareIntakeImporter({
    required AppDatabase db,
    required ShareAttachmentRepository attachments,
    required ShareTaskCreator createTask,
    DateTime Function()? clock,
  }) : _db = db,
       _attachments = attachments,
       _createTask = createTask,
       _clock = clock ?? AppClock.now;

  final AppDatabase _db;
  final ShareAttachmentRepository _attachments;
  final ShareTaskCreator _createTask;
  final DateTime Function() _clock;

  /// Guards two in-process import passes from racing the same intake. The
  /// database claim is released in a finally block as well.
  final Set<String> _active = <String>{};

  Future<ShareIntakeImportResult> importIntake(ShareIntake intake) async {
    await _ensureState(intake);
    final status = await _stateStatus(intake.id);
    if (status == ShareIntakeStatus.completed ||
        status == ShareIntakeStatus.discarded) {
      return _replayResult(intake);
    }
    if (!_active.add(intake.id)) return _busyResult(intake);
    final claimAt = _nowMs();
    try {
      final claimed = await _claim(intake.id, claimAt);
      if (claimed == 0) {
        final current = await _stateStatus(intake.id);
        if (current == ShareIntakeStatus.completed ||
            current == ShareIntakeStatus.discarded) {
          return await _replayResult(intake);
        }
        return await _busyResult(intake);
      }
      return await _importClaimed(intake);
    } finally {
      await _releaseClaim(intake.id, claimAt);
      _active.remove(intake.id);
    }
  }

  /// Marks one file as user-discarded. Returns true when no issue remains, so
  /// the caller may acknowledge native cleanup.
  Future<bool> discardFile(String intakeId, int ordinal) async {
    final row = await _fileRow(intakeId, ordinal);
    if (row == null) return false;
    final status = row['status'] as String?;
    if (status == ShareFileStatus.userDiscarded ||
        status == ShareFileStatus.imported) {
      return false;
    }
    await _setFileStatus(
      intakeId: intakeId,
      ordinal: ordinal,
      attachmentId: (row['attachment_id'] as String?) ?? '',
      status: ShareFileStatus.userDiscarded,
      reason: row['reason'] as String?,
      reasonCode: row['reason_code'] as String?,
    );
    final completed = await _finalizeState(intakeId);
    if (!completed) return false;
    return await _issueCount(intakeId) == 0;
  }

  /// Issues persisted for one intake, used by the retry card after a restart.
  Future<List<ShareIntakeIssue>> issuesFor(
    String intakeId, {
    String title = '',
  }) async {
    return _issuesFor(
      intakeId,
      title,
      const ShareIntake(id: '', title: '', text: '', files: [], rejected: []),
    );
  }

  Future<ShareIntakeImportResult> _importClaimed(ShareIntake intake) async {
    var task = await _db.getTodoItem(intake.id);
    final preExisting = task != null;
    var taskCreated = false;
    TodoItem? createdDefaults;
    final notes = intake.text.trim();
    if (task == null) {
      try {
        await _createTask(
          id: intake.id,
          title: intake.title,
          notes: notes.isEmpty ? null : notes,
        );
        taskCreated = true;
        task = await _db.getTodoItem(intake.id);
        createdDefaults = task;
      } catch (error) {
        await _markState(intake.id, ShareIntakeStatus.retryable);
        return ShareIntakeImportResult(
          intakeId: intake.id,
          title: intake.title,
          completed: false,
          acknowledgeNative: false,
          replayed: false,
          taskCreated: false,
          taskKept: false,
          importedFiles: 0,
          issues: [
            ShareIntakeIssue(
              intakeId: intake.id,
              title: intake.title,
              ordinal: -1,
              attachmentId: '',
              name: intake.title,
              status: ShareFileStatus.retryable,
              reason: '$error',
              reasonCode: 'task_create_failed',
            ),
          ],
        );
      }
    }
    if (task == null) {
      await _markState(intake.id, ShareIntakeStatus.retryable);
      return ShareIntakeImportResult(
        intakeId: intake.id,
        title: intake.title,
        completed: false,
        acknowledgeNative: false,
        replayed: false,
        taskCreated: false,
        taskKept: false,
        importedFiles: 0,
        issues: [
          ShareIntakeIssue(
            intakeId: intake.id,
            title: intake.title,
            ordinal: -1,
            attachmentId: '',
            name: intake.title,
            status: ShareFileStatus.retryable,
            reason: 'The shared task could not be created',
            reasonCode: 'task_create_failed',
          ),
        ],
      );
    }

    await _markState(intake.id, ShareIntakeStatus.importing);
    for (final file in intake.files) {
      await _ensureFilePending(intake, file);
    }
    final rejectedOrdinals = _rejectedOrdinals(intake);
    for (var index = 0; index < intake.rejected.length; index++) {
      await _ensureRejectedPending(
        intake,
        intake.rejected[index],
        rejectedOrdinals[index]!,
      );
    }

    var importedFiles = 0;
    for (final file in intake.files) {
      final attachmentId = file.attachmentId ?? '${intake.id}-${file.ordinal}';
      final row = await _fileRow(intake.id, file.ordinal);
      final current = row?['status'] as String?;
      if (current == ShareFileStatus.userDiscarded ||
          current == ShareFileStatus.permanentlyRejected) {
        continue;
      }

      // Check metadata *and* bytes before replaying an import.
      final existing = await _attachments.find(attachmentId);
      if (existing != null && existing.blobPresent) {
        if (current != ShareFileStatus.imported) {
          await _setFileStatus(
            intakeId: intake.id,
            ordinal: file.ordinal,
            attachmentId: attachmentId,
            status: ShareFileStatus.imported,
          );
          importedFiles++;
        }
        continue;
      }
      if (existing != null) {
        // Metadata committed but the blob did not reach durable storage.
        await _attachments.delete(attachmentId);
      }

      await _setFileStatus(
        intakeId: intake.id,
        ordinal: file.ordinal,
        attachmentId: attachmentId,
        status: ShareFileStatus.importing,
        countRetry:
            current == ShareFileStatus.retryable ||
            current == ShareFileStatus.importing,
      );
      try {
        await _precheck(file);
        await _attachments.importFile(
          file: File(file.path),
          id: attachmentId,
          todoId: intake.id,
          displayName: file.name,
        );
        await _setFileStatus(
          intakeId: intake.id,
          ordinal: file.ordinal,
          attachmentId: attachmentId,
          status: ShareFileStatus.imported,
        );
        importedFiles++;
      } on _PermanentFileRejection catch (error) {
        await _setFileStatus(
          intakeId: intake.id,
          ordinal: file.ordinal,
          attachmentId: attachmentId,
          status: ShareFileStatus.permanentlyRejected,
          reason: error.message,
          reasonCode: error.code,
        );
      } on AttachmentImportException catch (error) {
        await _setFileStatus(
          intakeId: intake.id,
          ordinal: file.ordinal,
          attachmentId: attachmentId,
          status: ShareFileStatus.permanentlyRejected,
          reason: error.message,
          reasonCode: _reasonCodeForMessage(error.message),
        );
      } catch (error) {
        // Storage, read or database failure: keep the staged bytes and task.
        await _setFileStatus(
          intakeId: intake.id,
          ordinal: file.ordinal,
          attachmentId: attachmentId,
          status: ShareFileStatus.retryable,
          reason: _describe(error),
          reasonCode: _reasonCodeForError(error),
        );
      }
    }

    for (var index = 0; index < intake.rejected.length; index++) {
      final rejected = intake.rejected[index];
      final ordinal = rejectedOrdinals[index]!;
      final row = await _fileRow(intake.id, ordinal);
      final current = row?['status'] as String?;
      if (current != null && ShareFileStatus.terminal.contains(current)) {
        continue;
      }
      final retryable = _nativeRejectionIsRetryable(rejected);
      await _setFileStatus(
        intakeId: intake.id,
        ordinal: ordinal,
        attachmentId: 'rejected-${intake.id}-$ordinal',
        status: retryable
            ? ShareFileStatus.retryable
            : ShareFileStatus.permanentlyRejected,
        reason: rejected.reason,
        reasonCode: rejected.reasonCode ?? 'rejected',
      );
    }

    final rows = await _fileRows(intake.id);
    final pending = rows.any(
      (row) => ShareFileStatus.unfinished.contains(row['status']),
    );
    final imported = rows
        .where((row) => row['status'] == ShareFileStatus.imported)
        .length;
    final currentTask = await _db.getTodoItem(intake.id);
    final edited =
        currentTask == null ||
        (taskCreated &&
            createdDefaults != null &&
            currentTask != createdDefaults) ||
        (!taskCreated && _taskEdited(currentTask, intake));
    // An empty task created only for this share is removed once there is
    // nothing left to attach. A pre-existing or user-edited task is kept.
    if (!pending &&
        imported == 0 &&
        notes.isEmpty &&
        taskCreated &&
        !preExisting &&
        !edited) {
      await _db.deleteTodoItem(intake.id);
    }
    final completed = await _finalizeState(intake.id);
    final remaining = await _db.getTodoItem(intake.id);
    final issues = await _issuesFor(intake.id, intake.title, intake);
    return ShareIntakeImportResult(
      intakeId: intake.id,
      title: intake.title,
      completed: completed,
      acknowledgeNative: completed && issues.isEmpty,
      replayed: false,
      taskCreated: taskCreated,
      taskKept: remaining != null,
      importedFiles: importedFiles,
      issues: issues,
    );
  }

  Future<void> _precheck(SharedFile file) async {
    final source = File(file.path);
    if (!await source.exists()) {
      throw const _PermanentFileRejection(
        'The shared file is no longer available',
        'staged_file_missing',
      );
    }
    final size = await source.length();
    if (size > AttachmentRules.maxFileBytes) {
      throw const _PermanentFileRejection(
        'Files larger than 25 MB are not supported.',
        'too_large',
      );
    }
    if (size == 0) {
      throw const _PermanentFileRejection('This file is empty.', 'empty_file');
    }
    final head = await _readHead(source);
    final sniffed = AttachmentMime.sniff(head);
    if (AttachmentMime.isDangerous(sniffed, file.name)) {
      throw const _PermanentFileRejection(
        'Executable and script files cannot be attached.',
        'unsupported_format',
      );
    }
  }

  static Future<Uint8List> _readHead(File file) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(0, 4096)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static bool _taskEdited(TodoItem task, ShareIntake intake) {
    final expectedNotes = intake.text.trim();
    final actualNotes = task.notes?.trim() ?? '';
    return task.title != intake.title ||
        actualNotes != expectedNotes ||
        task.completed;
  }

  static String _reasonCodeForMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('25 mb') || lower.contains('larger than')) {
      return 'too_large';
    }
    if (lower.contains('empty')) return 'empty_file';
    if (lower.contains('maximum of 20')) return 'too_many_attachments';
    if (lower.contains('executable') || lower.contains('script')) {
      return 'unsupported_format';
    }
    return 'rejected';
  }

  static String _reasonCodeForError(Object error) {
    if (error is FileSystemException) {
      final lower = '${error.message} ${error.osError?.message ?? ''}'
          .toLowerCase();
      if (lower.contains('enospc') || lower.contains('no space')) {
        return 'storage_full';
      }
      return 'storage_error';
    }
    return 'import_failed';
  }

  static String _describe(Object error) {
    if (error is FileSystemException) {
      if (_reasonCodeForError(error) == 'storage_full') {
        return 'There is not enough free space to save this file.';
      }
      return 'The file could not be copied to storage.';
    }
    return '$error';
  }

  static bool _nativeRejectionIsRetryable(RejectedSharedItem item) {
    if (item.retryable) return true;
    const transient = {'unreadable', 'storage_full', 'storage_error'};
    return transient.contains(item.reasonCode);
  }

  Future<void> _ensureState(ShareIntake intake) async {
    final now = _nowMs();
    final createdAt = intake.createdAt > 0 ? intake.createdAt : now;
    await _db.customStatement(
      'INSERT OR IGNORE INTO share_intake_state '
      '(intake_id, status, claimed_at, created_at, updated_at) '
      'VALUES (?, ?, NULL, ?, ?)',
      [intake.id, ShareIntakeStatus.pending, createdAt, now],
    );
  }

  Future<int> _claim(String intakeId, int claimAt) {
    return _db.customUpdate(
      'UPDATE share_intake_state SET status = ?, claimed_at = ?, updated_at = ? '
      'WHERE intake_id = ? AND status IN (?, ?, ?)',
      variables: [
        Variable.withString(ShareIntakeStatus.importing),
        Variable.withInt(claimAt),
        Variable.withInt(claimAt),
        Variable.withString(intakeId),
        Variable.withString(ShareIntakeStatus.pending),
        Variable.withString(ShareIntakeStatus.importing),
        Variable.withString(ShareIntakeStatus.retryable),
      ],
    );
  }

  Future<void> _releaseClaim(String intakeId, int claimAt) async {
    await _db.customUpdate(
      'UPDATE share_intake_state SET claimed_at = NULL, updated_at = ? '
      'WHERE intake_id = ? AND claimed_at = ?',
      variables: [
        Variable.withInt(_nowMs()),
        Variable.withString(intakeId),
        Variable.withInt(claimAt),
      ],
    );
  }

  Future<String?> _stateStatus(String intakeId) async {
    final rows = await _db
        .customSelect(
          'SELECT status FROM share_intake_state WHERE intake_id = ?',
          variables: [Variable.withString(intakeId)],
        )
        .get();
    if (rows.isEmpty) return null;
    return rows.single.read<String>('status');
  }

  Future<void> _markState(String intakeId, String status) async {
    await _db.customStatement(
      'UPDATE share_intake_state SET status = ?, updated_at = ? '
      'WHERE intake_id = ?',
      [status, _nowMs(), intakeId],
    );
  }

  Future<bool> _finalizeState(String intakeId) async {
    final rows = await _fileRows(intakeId);
    final pending = rows.any(
      (row) => ShareFileStatus.unfinished.contains(row['status']),
    );
    final now = _nowMs();
    if (pending) {
      await _db.customStatement(
        'UPDATE share_intake_state SET status = ?, completed_at = NULL, '
        'updated_at = ? WHERE intake_id = ?',
        [ShareIntakeStatus.retryable, now, intakeId],
      );
      return false;
    }
    await _db.customStatement(
      'UPDATE share_intake_state SET status = ?, claimed_at = NULL, '
      'completed_at = ?, updated_at = ? WHERE intake_id = ?',
      [ShareIntakeStatus.completed, now, now, intakeId],
    );
    return true;
  }

  Future<void> _ensureFilePending(ShareIntake intake, SharedFile file) async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO share_intake_files '
      '(intake_id, ordinal, attachment_id, status, reason, reason_code, '
      'retry_count, updated_at) '
      "VALUES (?, ?, ?, 'pending', NULL, NULL, 0, ?)",
      [
        intake.id,
        file.ordinal,
        file.attachmentId ?? '${intake.id}-${file.ordinal}',
        _nowMs(),
      ],
    );
  }

  Future<void> _ensureRejectedPending(
    ShareIntake intake,
    RejectedSharedItem rejected,
    int ordinal,
  ) async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO share_intake_files '
      '(intake_id, ordinal, attachment_id, status, reason, reason_code, '
      'retry_count, updated_at) '
      "VALUES (?, ?, ?, 'pending', NULL, NULL, 0, ?)",
      [intake.id, ordinal, 'rejected-${intake.id}-$ordinal', _nowMs()],
    );
  }

  /// Rejected entries from newer manifests carry their own ordinal. Older
  /// manifests may omit it, so assign a deterministic non-conflicting slot.
  static Map<int, int> _rejectedOrdinals(ShareIntake intake) {
    final used = <int>{for (final file in intake.files) file.ordinal};
    final result = <int, int>{};
    for (var index = 0; index < intake.rejected.length; index++) {
      final requested = intake.rejected[index].ordinal;
      var ordinal =
          requested != null && requested >= 0 && !used.contains(requested)
          ? requested
          : 1000 + index;
      while (used.contains(ordinal)) {
        ordinal++;
      }
      used.add(ordinal);
      result[index] = ordinal;
    }
    return result;
  }

  Future<Map<String, Object?>?> _fileRow(String intakeId, int ordinal) async {
    final rows = await _db
        .customSelect(
          'SELECT ordinal, attachment_id, status, reason, reason_code '
          'FROM share_intake_files WHERE intake_id = ? AND ordinal = ?',
          variables: [Variable.withString(intakeId), Variable.withInt(ordinal)],
        )
        .get();
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.single.data);
  }

  Future<List<Map<String, Object?>>> _fileRows(String intakeId) async {
    final rows = await _db
        .customSelect(
          'SELECT ordinal, attachment_id, status, reason, reason_code '
          'FROM share_intake_files WHERE intake_id = ? ORDER BY ordinal',
          variables: [Variable.withString(intakeId)],
        )
        .get();
    return [for (final row in rows) Map<String, Object?>.from(row.data)];
  }

  Future<void> _setFileStatus({
    required String intakeId,
    required int ordinal,
    required String attachmentId,
    required String status,
    String? reason,
    String? reasonCode,
    bool countRetry = false,
  }) async {
    final now = _nowMs();
    await _db.customStatement(
      'INSERT INTO share_intake_files '
      '(intake_id, ordinal, attachment_id, status, reason, reason_code, '
      'retry_count, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, 0, ?) '
      'ON CONFLICT(intake_id, ordinal) DO UPDATE SET '
      'attachment_id = excluded.attachment_id, status = excluded.status, '
      'reason = excluded.reason, reason_code = excluded.reason_code, '
      'retry_count = share_intake_files.retry_count + ?, '
      'updated_at = excluded.updated_at',
      [
        intakeId,
        ordinal,
        attachmentId,
        status,
        reason,
        reasonCode,
        now,
        countRetry ? 1 : 0,
      ],
    );
  }

  Future<int> _issueCount(String intakeId) async {
    final rows = await _db
        .customSelect(
          'SELECT COUNT(*) AS issue_count FROM share_intake_files '
          'WHERE intake_id = ? AND status IN (?, ?)',
          variables: [
            Variable.withString(intakeId),
            Variable.withString(ShareFileStatus.retryable),
            Variable.withString(ShareFileStatus.permanentlyRejected),
          ],
        )
        .get();
    return rows.single.read<int>('issue_count');
  }

  Future<List<ShareIntakeIssue>> _issuesFor(
    String intakeId,
    String title,
    ShareIntake intake,
  ) async {
    final rows = await _db
        .customSelect(
          'SELECT ordinal, attachment_id, status, reason, reason_code '
          'FROM share_intake_files '
          'WHERE intake_id = ? AND status IN (?, ?) ORDER BY ordinal',
          variables: [
            Variable.withString(intakeId),
            Variable.withString(ShareFileStatus.retryable),
            Variable.withString(ShareFileStatus.permanentlyRejected),
          ],
        )
        .get();
    final names = <int, String>{};
    for (final file in intake.files) {
      names[file.ordinal] = file.name;
    }
    final rejectedOrdinals = _rejectedOrdinals(intake);
    for (var index = 0; index < intake.rejected.length; index++) {
      names[rejectedOrdinals[index]!] = intake.rejected[index].name;
    }
    return [
      for (final row in rows)
        ShareIntakeIssue(
          intakeId: intakeId,
          title: title,
          ordinal: row.read<int>('ordinal'),
          attachmentId: row.readNullable<String>('attachment_id') ?? '',
          name:
              names[row.read<int>('ordinal')] ??
              'Shared file ${row.read<int>('ordinal') + 1}',
          status: row.read<String>('status'),
          reason: row.readNullable<String>('reason'),
          reasonCode: row.readNullable<String>('reason_code'),
        ),
    ];
  }

  Future<ShareIntakeImportResult> _replayResult(ShareIntake intake) async {
    final task = await _db.getTodoItem(intake.id);
    final issues = await _issuesFor(intake.id, intake.title, intake);
    return ShareIntakeImportResult(
      intakeId: intake.id,
      title: intake.title,
      completed: true,
      acknowledgeNative: issues.isEmpty,
      replayed: true,
      taskCreated: false,
      taskKept: task != null,
      // Replaying a completed intake adds nothing; report zero so the phone
      // does not claim the same files were attached again.
      importedFiles: 0,
      issues: issues,
    );
  }

  Future<ShareIntakeImportResult> _busyResult(ShareIntake intake) async {
    final task = await _db.getTodoItem(intake.id);
    return ShareIntakeImportResult(
      intakeId: intake.id,
      title: intake.title,
      completed: false,
      acknowledgeNative: false,
      replayed: false,
      taskCreated: false,
      taskKept: task != null,
      importedFiles: 0,
      issues: await _issuesFor(intake.id, intake.title, intake),
    );
  }

  int _nowMs() => _clock().millisecondsSinceEpoch;
}
