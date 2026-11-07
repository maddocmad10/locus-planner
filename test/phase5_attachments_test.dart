import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_service.dart';
import 'package:locus_planner/core/services/attachments/attachment_store.dart';
import 'package:locus_planner/core/services/attachments/attachment_types.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/services/undo_service.dart';

void main() {
  group('attachment crypto', () {
    final key = Uint8List.fromList(List.generate(32, (index) => index));
    final crypto = AttachmentCrypto(key);

    test('round-trips bytes across chunk boundaries', () {
      final data = Uint8List.fromList(
        List.generate(200000, (index) => index % 251),
      );
      final sealed = crypto.sealBytes(data);
      expect(sealed, isNot(equals(data)));
      expect(crypto.openBytes(sealed), equals(data));
    });

    test('round-trips an empty blob', () {
      final sealed = crypto.sealBytes(Uint8List(0));
      expect(crypto.openBytes(sealed), isEmpty);
    });

    test('rejects a flipped ciphertext byte', () {
      final data = Uint8List.fromList(List.generate(1000, (index) => index));
      final sealed = crypto.sealBytes(data);
      sealed[sealed.length - 1] ^= 0x01;
      expect(
        () => crypto.openBytes(sealed),
        throwsA(isA<AttachmentBlobCorruptException>()),
      );
    });

    test('rejects truncation and trailing bytes', () {
      final data = Uint8List.fromList(List.generate(70000, (index) => index));
      final sealed = crypto.sealBytes(data);
      expect(
        () => crypto.openBytes(Uint8List.sublistView(sealed, 0, 100)),
        throwsA(isA<AttachmentBlobCorruptException>()),
      );
      expect(
        () => crypto.openBytes(Uint8List.fromList([...sealed, 1, 2, 3])),
        throwsA(isA<AttachmentBlobCorruptException>()),
      );
    });

    test('derives a deterministic content-addressed file id', () {
      final id = crypto.fileId('a' * 64);
      expect(id, hasLength(64));
      expect(id, isNot('a' * 64));
      expect(crypto.fileId('a' * 64), id);
    });
  });

  group('attachment store', () {
    late Directory root;
    late AttachmentStore store;
    final crypto = AttachmentCrypto(
      Uint8List.fromList(List.generate(32, (index) => 255 - index)),
    );

    setUp(() async {
      root = await Directory.systemTemp.createTemp('locus-attachments-');
      store = AttachmentStore(root: root, crypto: crypto);
      await store.prepare();
    });

    tearDown(() async {
      await root.delete(recursive: true);
    });

    test('deduplicates identical content', () async {
      final bytes = Uint8List.fromList(utf8.encode('same bytes'));
      final first = await store.putBytes(bytes);
      final second = await store.putBytes(bytes);
      expect(second, first);
      expect(await store.hasBlob(first), isTrue);
      expect(await store.readBytes(first), bytes);
      final files = await store.blobsDirectory.list().toList();
      expect(files.whereType<File>(), hasLength(1));
    });

    test('sealed file does not contain the plaintext', () async {
      final bytes = Uint8List.fromList(utf8.encode('secret needle'));
      final sha = await store.putBytes(bytes);
      final sealed = await store.blobFile(sha).readAsBytes();
      expect(String.fromCharCodes(sealed).contains('secret needle'), isFalse);
    });

    test('thumbnail survives a round trip and delete removes both', () async {
      final bytes = Uint8List.fromList(utf8.encode('blob'));
      final thumb = Uint8List.fromList(utf8.encode('thumb'));
      final sha = await store.putBytes(bytes);
      await store.putThumb(sha, thumb);
      expect(await store.readThumb(sha), thumb);
      await store.deleteBlob(sha);
      expect(await store.hasBlob(sha), isFalse);
      expect(await store.readThumb(sha), isNull);
    });
  });

  group('attachment policy', () {
    test('sanitizes names and blocks executable extensions', () {
      expect(
        AttachmentRules.sanitizeDisplayName('..\\evil/name?.txt'),
        isNot(contains('\\')),
      );
      expect(AttachmentRules.sanitizeDisplayName('CON.txt'), 'file_CON.txt');
      expect(AttachmentRules.sanitizeDisplayName('a' * 200).length, 120);
      expect(AttachmentRules.hasBlockedExtension('setup.exe'), isTrue);
      expect(AttachmentRules.hasBlockedExtension('notes.txt'), isFalse);
    });

    test('sniffs content instead of trusting the extension', () {
      expect(
        AttachmentMime.sniff(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ).mimeType,
        'image/png',
      );
      expect(
        AttachmentMime.sniff(
          Uint8List.fromList(utf8.encode('%PDF-1.7')),
        ).mimeType,
        'application/pdf',
      );
      expect(
        AttachmentMime.sniff(
          Uint8List.fromList(utf8.encode('MZ\x90\x00')),
        ).mimeType,
        contains('portable-executable'),
      );
      expect(
        AttachmentMime.sniff(Uint8List.fromList(utf8.encode('hello'))).kind,
        'file',
      );
    });
  });

  group('attachment service', () {
    late AppDatabase db;
    late Directory root;
    late AttachmentService service;
    late UndoService undo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      root = await Directory.systemTemp.createTemp('locus-attachment-service-');
      undo = UndoService();
      service = AttachmentService(
        db,
        AttachmentStore(
          root: root,
          crypto: AttachmentCrypto(
            Uint8List.fromList(List.generate(32, (index) => index)),
          ),
        ),
        undo: undo,
      );
      await service.initialize();
    });

    tearDown(() async {
      undo.dispose();
      await db.close();
      await root.delete(recursive: true);
    });

    test('imports, lists, removes and restores with undo', () async {
      final todoId = await db.addTodoItem('Task', null);
      final attachment = await service.importBytes(
        bytes: Uint8List.fromList(utf8.encode('hello')),
        fileName: 'Hello.txt',
        todoId: todoId,
      );

      expect(attachment.kind, 'file');
      expect(attachment.mimeType, 'text/plain');
      expect(attachment.sizeBytes, 5);
      expect(await service.forTodo(todoId), hasLength(1));
      expect(await service.store.hasBlob(attachment.sha256), isTrue);

      await service.remove(attachment.id);
      expect(await service.forTodo(todoId), isEmpty);
      expect(await service.store.hasBlob(attachment.sha256), isTrue);

      expect(await undo.undo(), isTrue);
      expect(await service.forTodo(todoId), hasLength(1));
    });

    test('rejects empty, oversized and executable files', () async {
      final todoId = await db.addTodoItem('Task', null);
      await expectLater(
        service.importBytes(
          bytes: Uint8List(0),
          fileName: 'empty.txt',
          todoId: todoId,
        ),
        throwsA(isA<AttachmentImportException>()),
      );
      await expectLater(
        service.importBytes(
          bytes: Uint8List.fromList(utf8.encode('MZ fake')),
          fileName: 'setup.exe',
          todoId: todoId,
        ),
        throwsA(isA<AttachmentImportException>()),
      );
      await expectLater(
        service.importBytes(
          bytes: Uint8List(AttachmentRules.maxFileBytes + 1),
          fileName: 'big.bin',
          todoId: todoId,
        ),
        throwsA(isA<AttachmentImportException>()),
      );
    });

    test('enforces the twenty-attachment limit', () async {
      final todoId = await db.addTodoItem('Task', null);
      for (var index = 0; index < AttachmentRules.maxPerItem; index++) {
        await service.importBytes(
          bytes: Uint8List.fromList(utf8.encode('same')),
          fileName: 'note-$index.txt',
          todoId: todoId,
        );
      }
      await expectLater(
        service.importBytes(
          bytes: Uint8List.fromList(utf8.encode('same')),
          fileName: 'overflow.txt',
          todoId: todoId,
        ),
        throwsA(isA<AttachmentImportException>()),
      );
    });

    test('requires exactly one parent', () async {
      await expectLater(
        service.importBytes(
          bytes: Uint8List.fromList(utf8.encode('x')),
          fileName: 'x.txt',
        ),
        throwsA(isA<AttachmentImportException>()),
      );
    });

    test('positions never repeat after a delete', () async {
      final todoId = await db.addTodoItem('Task', null);
      final first = await service.importBytes(
        bytes: Uint8List.fromList(utf8.encode('one')),
        fileName: 'one.txt',
        todoId: todoId,
      );
      final second = await service.importBytes(
        bytes: Uint8List.fromList(utf8.encode('two')),
        fileName: 'two.txt',
        todoId: todoId,
      );
      expect([first.position, second.position], [0, 1]);

      await service.remove(first.id);
      final third = await service.importBytes(
        bytes: Uint8List.fromList(utf8.encode('three')),
        fileName: 'three.txt',
        todoId: todoId,
      );

      expect(third.position, 2);
      final rows = await service.forTodo(todoId);
      expect(rows.map((row) => row.position), [1, 2]);
    });
  });

  test('backup v4 records attachment metadata but no blob rows', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final root = await Directory.systemTemp.createTemp('locus-attachment-db-');
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final todoId = await db.addTodoItem('Task', null);
    final service = AttachmentService(
      db,
      AttachmentStore(
        root: root,
        crypto: AttachmentCrypto(
          Uint8List.fromList(List.generate(32, (index) => 42)),
        ),
      ),
    );
    await service.initialize();
    await service.importBytes(
      bytes: Uint8List.fromList(utf8.encode('hello')),
      fileName: 'hello.txt',
      todoId: todoId,
    );
    await service.setKeepOriginal(true);

    final dir = await Directory.systemTemp.createTemp('locus-attachment-bak-');
    addTearDown(() => dir.delete(recursive: true));
    final json = await DataExportService(
      db,
      backupDirectory: dir,
    ).buildBackupJson();
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format_version'], 4);
    expect(decoded['attachments_included'], isFalse);
    expect(decoded.containsKey('attachment_blobs'), isFalse);
    expect((decoded['attachments'] as List), hasLength(1));
    final settings = (decoded['app_settings'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      settings.any(
        (row) => row['key'] == AttachmentRules.keepOriginalSettingKey,
      ),
      isFalse,
      reason: 'the image policy is device-local, not user content',
    );

    final restored = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(restored.close);
    final report = await DataExportService(restored).restoreFromJson(json);
    expect(report.skippedRows, 0);
    final rows = await restored.select(restored.attachments).get();
    expect(rows, hasLength(1));
    expect(rows.single.displayName, 'hello.txt');
    expect(await restored.select(restored.attachmentBlobs).get(), isEmpty);
  });
}
