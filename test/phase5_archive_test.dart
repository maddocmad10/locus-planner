import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/attachments/attachment_crypto.dart';
import 'package:locus_planner/core/services/attachments/attachment_service.dart';
import 'package:locus_planner/core/services/attachments/attachment_store.dart';
import 'package:locus_planner/core/services/attachments/locus_archive.dart';

void main() {
  late AppDatabase db;
  late Directory root;
  late AttachmentService service;
  late Directory archiveDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('locus-archive-store-');
    archiveDir = await Directory.systemTemp.createTemp('locus-archive-out-');
    service = AttachmentService(
      db,
      AttachmentStore(
        root: root,
        crypto: AttachmentCrypto(
          Uint8List.fromList(List.generate(32, (index) => index)),
        ),
      ),
    );
    await service.initialize();
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
    await archiveDir.delete(recursive: true);
  });

  test('archive round-trips metadata and blob bytes', () async {
    final todoId = await db.addTodoItem('Task', null);
    final large = Uint8List.fromList(
      List.generate(100000, (index) => index % 251),
    );
    final largeAttachment = await service.importBytes(
      bytes: large,
      fileName: 'large.bin',
      todoId: todoId,
    );
    final small = await service.importBytes(
      bytes: Uint8List.fromList(utf8.encode('hello archive')),
      fileName: 'hello.txt',
      todoId: todoId,
    );

    final archive = File('${archiveDir.path}/backup.locusarchive');
    final built = await LocusArchiveService().create(
      db: db,
      attachments: service,
      passphrase: 'correct horse battery',
      target: archive,
    );
    expect(built.blobCount, 2);
    expect(built.missingHashes, isEmpty);
    expect(await archive.length(), greaterThan(100000));

    final restoredDb = AppDatabase.forTesting(NativeDatabase.memory());
    final restoredRoot = await Directory.systemTemp.createTemp(
      'locus-archive-restored-',
    );
    final restoredService = AttachmentService(
      restoredDb,
      AttachmentStore(
        root: restoredRoot,
        crypto: AttachmentCrypto(
          Uint8List.fromList(List.generate(32, (index) => 255 - index)),
        ),
      ),
    );
    await restoredService.initialize();
    addTearDown(() async {
      await restoredDb.close();
      await restoredRoot.delete(recursive: true);
    });

    final report = await LocusArchiveService().restore(
      db: restoredDb,
      attachments: restoredService,
      archive: archive,
      passphrase: 'correct horse battery',
    );

    expect(report.blobsWritten, 2);
    expect(report.skippedRows, 0);
    final rows = await restoredDb.select(restoredDb.attachments).get();
    expect(rows, hasLength(2));
    expect(
      await restoredService.store.readBytes(largeAttachment.sha256),
      large,
    );
    expect(
      await restoredService.store.readBytes(small.sha256),
      utf8.encode('hello archive'),
    );
  });

  test('a wrong passphrase and a flipped byte both fail closed', () async {
    final todoId = await db.addTodoItem('Task', null);
    await service.importBytes(
      bytes: Uint8List.fromList(utf8.encode('secret')),
      fileName: 'secret.txt',
      todoId: todoId,
    );
    final archive = File('${archiveDir.path}/backup.locusarchive');
    await LocusArchiveService().create(
      db: db,
      attachments: service,
      passphrase: 'correct horse battery',
      target: archive,
    );

    expect(
      () => LocusArchiveService().restore(
        db: db,
        attachments: service,
        archive: archive,
        passphrase: 'wrong passphrase',
      ),
      throwsA(isA<LocusArchiveException>()),
    );

    final bytes = await archive.readAsBytes();
    bytes[bytes.length - 10] ^= 0x01;
    final damaged = File('${archiveDir.path}/damaged.locusarchive');
    await damaged.writeAsBytes(bytes);
    expect(
      () => LocusArchiveService().restore(
        db: db,
        attachments: service,
        archive: damaged,
        passphrase: 'correct horse battery',
      ),
      throwsA(isA<LocusArchiveException>()),
    );
  });

  test('missing blobs are reported but metadata still restores', () async {
    final todoId = await db.addTodoItem('Task', null);
    final present = await service.importBytes(
      bytes: Uint8List.fromList(utf8.encode('present')),
      fileName: 'present.txt',
      todoId: todoId,
    );
    final missing = await service.importBytes(
      bytes: Uint8List.fromList(utf8.encode('missing')),
      fileName: 'missing.txt',
      todoId: todoId,
    );
    await service.store.deleteBlob(missing.sha256);

    final archive = File('${archiveDir.path}/partial.locusarchive');
    final built = await LocusArchiveService().create(
      db: db,
      attachments: service,
      passphrase: 'correct horse battery',
      target: archive,
    );
    expect(built.blobCount, 1);
    expect(built.missingHashes, contains(missing.sha256));

    final restoredDb = AppDatabase.forTesting(NativeDatabase.memory());
    final restoredRoot = await Directory.systemTemp.createTemp(
      'locus-archive-partial-',
    );
    final restoredService = AttachmentService(
      restoredDb,
      AttachmentStore(
        root: restoredRoot,
        crypto: AttachmentCrypto(
          Uint8List.fromList(List.generate(32, (index) => 42)),
        ),
      ),
    );
    await restoredService.initialize();
    addTearDown(() async {
      await restoredDb.close();
      await restoredRoot.delete(recursive: true);
    });

    final report = await LocusArchiveService().restore(
      db: restoredDb,
      attachments: restoredService,
      archive: archive,
      passphrase: 'correct horse battery',
    );
    expect(report.blobsWritten, 1);
    expect(report.missingHashes, contains(missing.sha256));
    expect(await restoredDb.select(restoredDb.attachments).get(), hasLength(2));
    expect(await restoredService.store.hasBlob(present.sha256), isTrue);
    expect(await restoredService.store.hasBlob(missing.sha256), isFalse);
  });
}
