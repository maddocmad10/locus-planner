import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_service.dart';
import 'package:locus_planner/core/services/attachments/attachment_store.dart';
import 'package:locus_planner/core/utils/app_clock.dart';
import 'package:locus_planner/features/mobile/data/share_intake_importer.dart';
import 'package:locus_planner/features/mobile/data/share_intake_service.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late AttachmentStore store;
  late AttachmentService attachments;
  late DatabaseShareAttachmentRepository realRepository;
  late Directory staged;
  late File firstFile;
  late File secondFile;
  late List<int> firstBytes;
  late List<int> secondBytes;

  setUp(() async {
    AppClock.now = () => DateTime(2026, 11, 22, 10, 30);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('locus-share-attachments-');
    staged = await Directory.systemTemp.createTemp('locus-share-staged-');
    store = AttachmentStore(
      root: root,
      crypto: AttachmentCrypto(
        Uint8List.fromList(List.generate(32, (index) => index + 1)),
      ),
    );
    await store.prepare();
    attachments = AttachmentService(db, store);
    realRepository = DatabaseShareAttachmentRepository(
      db: db,
      attachments: attachments,
    );

    firstBytes = utf8.encode('first shared file body');
    secondBytes = utf8.encode('second shared file body');
    firstFile = File('${staged.path}/first.txt')..writeAsBytesSync(firstBytes);
    secondFile = File('${staged.path}/second.txt')
      ..writeAsBytesSync(secondBytes);
  });

  tearDown(() async {
    AppClock.now = DateTime.now;
    await db.close();
    if (await root.exists()) await root.delete(recursive: true);
    if (await staged.exists()) await staged.delete(recursive: true);
  });

  ShareIntakeImporter importerWith(ShareAttachmentRepository repository) {
    return ShareIntakeImporter(
      db: db,
      attachments: repository,
      createTask:
          ({
            required String id,
            required String title,
            required String? notes,
          }) async {
            await db.addTodoItem(title, null, id: id, notes: notes);
          },
    );
  }

  ShareIntake twoFileIntake({String title = 'Two shared files'}) {
    return ShareIntake(
      id: 'intake-1',
      title: title,
      text: '',
      files: [
        SharedFile(
          path: firstFile.path,
          name: 'first.txt',
          mimeType: 'text/plain',
          attachmentId: 'intake-1-0',
          ordinal: 0,
        ),
        SharedFile(
          path: secondFile.path,
          name: 'second.txt',
          mimeType: 'text/plain',
          attachmentId: 'intake-1-1',
          ordinal: 1,
        ),
      ],
      rejected: const [],
      createdAt: 1763711400000,
    );
  }

  Future<Map<String, Object?>?> stateRow(String id) async {
    final rows = await db
        .customSelect(
          'SELECT status, claimed_at, completed_at FROM share_intake_state '
          'WHERE intake_id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) return null;
    return Map<String, Object?>.from(rows.single.data);
  }

  Future<List<Map<String, Object?>>> fileRows(String id) async {
    final rows = await db
        .customSelect(
          'SELECT ordinal, attachment_id, status, reason, reason_code, '
          'retry_count FROM share_intake_files WHERE intake_id = ? '
          'ORDER BY ordinal',
          variables: [Variable.withString(id)],
        )
        .get();
    return [for (final row in rows) Map<String, Object?>.from(row.data)];
  }

  Future<Attachment> attachmentRow(String id) {
    return (db.select(
      db.attachments,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  test('disk-full on the second file keeps bytes and task; retry imports '
      'both exactly once with stable digests', () async {
    final flaky = _FlakyAttachmentRepository(realRepository);
    final firstImporter = importerWith(flaky);

    final first = await firstImporter.importIntake(twoFileIntake());

    expect(first.completed, isFalse);
    expect(first.acknowledgeNative, isFalse);
    expect(first.taskKept, isTrue);
    expect(first.issues, hasLength(1));
    expect(first.issues.single.name, 'second.txt');
    expect(first.issues.single.status, ShareFileStatus.retryable);
    expect(first.issues.single.reasonCode, 'storage_full');

    final state = await stateRow('intake-1');
    expect(state!['status'], ShareIntakeStatus.retryable);
    expect(state['claimed_at'], isNull);
    expect(state['completed_at'], isNull);

    final rows = await fileRows('intake-1');
    expect(rows, hasLength(2));
    expect(rows[0]['status'], ShareFileStatus.imported);
    expect(rows[1]['status'], ShareFileStatus.retryable);
    expect(rows[1]['reason_code'], 'storage_full');
    expect(rows[1]['retry_count'], 0);

    final tasks = await db.select(db.todoItems).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.id, 'intake-1');
    final firstBefore = await attachmentRow('intake-1-0');
    expect(firstBefore.sha256, sha256.convert(firstBytes).toString());

    // Simulate process death and a later launch: a new importer and repository
    // over the same database and staged files, now with free disk space.
    final retryImporter = importerWith(
      _FlakyAttachmentRepository(realRepository, fail: false),
    );
    final retried = await retryImporter.importIntake(twoFileIntake());

    expect(retried.completed, isTrue);
    expect(retried.acknowledgeNative, isTrue);
    expect(retried.importedFiles, 1);
    expect(retried.taskCreated, isFalse);
    expect(retried.issues, isEmpty);

    final tasksAfter = await db.select(db.todoItems).get();
    expect(tasksAfter, hasLength(1));
    final all = await db.select(db.attachments).get();
    expect(all, hasLength(2));
    final byId = {for (final attachment in all) attachment.id: attachment};
    expect(byId['intake-1-0']!.sha256, sha256.convert(firstBytes).toString());
    expect(byId['intake-1-1']!.sha256, sha256.convert(secondBytes).toString());
    // The first attachment row is byte-for-byte the same row, not a re-import.
    final firstAfter = byId['intake-1-0']!;
    expect(firstAfter.sha256, firstBefore.sha256);
    expect(firstAfter.createdAt, firstBefore.createdAt);
    expect(firstAfter.position, firstBefore.position);

    final completedState = await stateRow('intake-1');
    expect(completedState!['status'], ShareIntakeStatus.completed);
    expect(completedState['completed_at'], isNotNull);
    final completedFiles = await fileRows('intake-1');
    expect(completedFiles[1]['retry_count'], 1);

    // A crash between the DB completion and the native acknowledgement must
    // replay without another task or attachment.
    final replayed = await retryImporter.importIntake(twoFileIntake());
    expect(replayed.completed, isTrue);
    expect(replayed.replayed, isTrue);
    expect(replayed.acknowledgeNative, isTrue);
    expect(await db.select(db.todoItems).get(), hasLength(1));
    expect(await db.select(db.attachments).get(), hasLength(2));
  });

  test(
    'retrying only the failed file keeps the first attachment unchanged',
    () async {
      final firstImporter = importerWith(
        _FlakyAttachmentRepository(realRepository),
      );
      await firstImporter.importIntake(twoFileIntake());
      final firstBefore = await attachmentRow('intake-1-0');

      final onlyFailed = ShareIntake(
        id: 'intake-1',
        title: 'Two shared files',
        text: '',
        files: [
          SharedFile(
            path: secondFile.path,
            name: 'second.txt',
            mimeType: 'text/plain',
            attachmentId: 'intake-1-1',
            ordinal: 1,
          ),
        ],
        rejected: const [],
        createdAt: 1763711400000,
      );
      final retryImporter = importerWith(
        _FlakyAttachmentRepository(realRepository, fail: false),
      );
      final result = await retryImporter.importIntake(onlyFailed);

      expect(result.completed, isTrue);
      expect(result.importedFiles, 1);
      final all = await db.select(db.attachments).get();
      expect(all, hasLength(2));
      final byId = {for (final attachment in all) attachment.id: attachment};
      final firstAfter = byId['intake-1-0']!;
      expect(firstAfter.sha256, firstBefore.sha256);
      expect(firstAfter.createdAt, firstBefore.createdAt);
      expect(
        byId['intake-1-1']!.sha256,
        sha256.convert(secondBytes).toString(),
      );
      expect(await db.select(db.todoItems).get(), hasLength(1));
    },
  );

  test(
    'metadata without a blob is repaired before an import is trusted',
    () async {
      final single = ShareIntake(
        id: 'intake-blob',
        title: 'One file',
        text: '',
        files: [
          SharedFile(
            path: firstFile.path,
            name: 'first.txt',
            mimeType: 'text/plain',
            attachmentId: 'intake-blob-0',
            ordinal: 0,
          ),
        ],
        rejected: const [],
      );
      final importer = importerWith(realRepository);
      expect((await importer.importIntake(single)).completed, isTrue);
      final row = await attachmentRow('intake-blob-0');
      await store.deleteBlob(row.sha256);
      expect(await store.hasBlob(row.sha256), isFalse);

      // Make the intake retryable as if a later step had failed, then retry.
      await db.customStatement(
        "UPDATE share_intake_state SET status = 'retryable' "
        "WHERE intake_id = 'intake-blob'",
      );
      await db.customStatement(
        "UPDATE share_intake_files SET status = 'retryable' "
        "WHERE intake_id = 'intake-blob'",
      );
      final retry = await importer.importIntake(single);

      expect(retry.completed, isTrue);
      final repaired = await attachmentRow('intake-blob-0');
      expect(await store.hasBlob(repaired.sha256), isTrue);
      expect(repaired.sha256, sha256.convert(firstBytes).toString());
      expect(await db.select(db.attachments).get(), hasLength(1));
    },
  );

  test(
    'a rejected-only intake is recorded, classified and not dropped',
    () async {
      final intake = ShareIntake(
        id: 'intake-rejected',
        title: 'Shared file',
        text: '',
        files: const [],
        rejected: const [
          RejectedSharedItem(
            name: 'huge-video.mp4',
            mimeType: 'video/mp4',
            reason: 'Files larger than 25 MB are not supported',
            reasonCode: 'too_large',
            ordinal: 0,
            retryable: false,
          ),
          RejectedSharedItem(
            name: 'extra.pdf',
            mimeType: 'application/pdf',
            reason: 'More than 20 files were shared',
            reasonCode: 'too_many_files',
            ordinal: 20,
            retryable: false,
          ),
        ],
      );
      final importer = importerWith(realRepository);
      final result = await importer.importIntake(intake);

      expect(result.completed, isTrue);
      expect(result.acknowledgeNative, isFalse);
      expect(result.issues, hasLength(2));
      expect(
        result.issues.map((issue) => issue.name),
        containsAll(['huge-video.mp4', 'extra.pdf']),
      );
      expect(
        result.issues.every(
          (issue) => issue.status == ShareFileStatus.permanentlyRejected,
        ),
        isTrue,
      );
      final rows = await fileRows('intake-rejected');
      expect(rows, hasLength(2));
      expect(rows[0]['ordinal'], 0);
      expect(rows[0]['reason_code'], 'too_large');
      expect(rows[1]['ordinal'], 20);
      expect(rows[1]['reason_code'], 'too_many_files');
      expect(
        (await stateRow('intake-rejected'))!['status'],
        ShareIntakeStatus.completed,
      );

      // The names stay discoverable until each rejection is dismissed; only
      // the last dismissal allows native cleanup.
      expect(await importer.discardFile('intake-rejected', 0), isFalse);
      expect(await importer.discardFile('intake-rejected', 20), isTrue);
      expect(await importer.issuesFor('intake-rejected'), isEmpty);
      final replay = await importer.importIntake(intake);
      expect(replay.completed, isTrue);
      expect(replay.acknowledgeNative, isTrue);
      expect(replay.replayed, isTrue);
    },
  );

  test(
    'a blocked format is permanently rejected with an explicit reason',
    () async {
      final blocked = File('${staged.path}/setup.exe')
        ..writeAsBytesSync([0x4D, 0x5A, 0x00, 0x01, 0x02, 0x03]);
      final intake = ShareIntake(
        id: 'intake-format',
        title: 'Shared file',
        text: '',
        files: [
          SharedFile(
            path: blocked.path,
            name: 'setup.exe',
            mimeType: 'application/octet-stream',
            attachmentId: 'intake-format-0',
            ordinal: 0,
          ),
        ],
        rejected: const [],
      );
      final importer = importerWith(realRepository);
      final result = await importer.importIntake(intake);

      expect(result.completed, isTrue);
      expect(result.acknowledgeNative, isFalse);
      expect(result.issues.single.name, 'setup.exe');
      expect(result.issues.single.status, ShareFileStatus.permanentlyRejected);
      expect(result.issues.single.reasonCode, 'unsupported_format');
      expect(await db.select(db.attachments).get(), isEmpty);
      final rows = await fileRows('intake-format');
      expect(rows.single['status'], ShareFileStatus.permanentlyRejected);
      expect(rows.single['reason_code'], 'unsupported_format');
    },
  );

  test('a pre-existing or user-edited task is never deleted', () async {
    await db.addTodoItem(
      'My own task',
      null,
      id: 'intake-edited',
      notes: 'keep me',
    );
    final intake = ShareIntake(
      id: 'intake-edited',
      title: 'Shared file',
      text: '',
      files: const [],
      rejected: const [
        RejectedSharedItem(
          name: 'blocked.exe',
          mimeType: 'application/octet-stream',
          reason: 'Executable and script files cannot be attached.',
          reasonCode: 'unsupported_format',
          ordinal: 0,
        ),
      ],
    );
    final importer = importerWith(realRepository);
    final result = await importer.importIntake(intake);

    expect(result.completed, isTrue);
    expect(result.taskKept, isTrue);
    final task = await db.getTodoItem('intake-edited');
    expect(task, isNotNull);
    expect(task!.title, 'My own task');
    expect(task.notes, 'keep me');
  });

  test(
    'an editable task is preserved when a file is still retryable',
    () async {
      final importer = importerWith(_FlakyAttachmentRepository(realRepository));
      await importer.importIntake(twoFileIntake());
      await db.customStatement(
        "UPDATE todo_items SET title = 'Renamed by me' "
        "WHERE id = 'intake-1'",
      );
      final retry = importerWith(
        _FlakyAttachmentRepository(realRepository, fail: false),
      );
      final result = await retry.importIntake(twoFileIntake());

      expect(result.completed, isTrue);
      final task = await db.getTodoItem('intake-1');
      expect(task!.title, 'Renamed by me');
    },
  );
}

/// Wraps the real repository and fails the named file as a full disk would.
class _FlakyAttachmentRepository implements ShareAttachmentRepository {
  _FlakyAttachmentRepository(this.inner, {this.fail = true});

  final DatabaseShareAttachmentRepository inner;
  bool fail;

  @override
  Future<ShareAttachmentInfo?> find(String attachmentId) =>
      inner.find(attachmentId);

  @override
  Future<void> delete(String attachmentId) => inner.delete(attachmentId);

  @override
  Future<void> importFile({
    required File file,
    required String id,
    required String todoId,
    required String displayName,
  }) async {
    if (fail && displayName == 'second.txt') {
      fail = false;
      throw FileSystemException(
        'write failed: ENOSPC (No space left on device)',
        file.path,
      );
    }
    await inner.importFile(
      file: file,
      id: id,
      todoId: todoId,
      displayName: displayName,
    );
  }
}
