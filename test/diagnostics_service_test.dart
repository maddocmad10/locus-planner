import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/diagnostics_service.dart';
import 'package:locus_planner/core/services/reminder_diagnostics.dart';

void main() {
  late AppDatabase db;
  late Directory logDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logDir = await Directory.systemTemp.createTemp('locus-diagnostics-');
    ReminderDiagnostics.clear();
  });

  tearDown(() async {
    ReminderDiagnostics.clear();
    await db.close();
    await logDir.delete(recursive: true);
  });

  DiagnosticsService service() => DiagnosticsService(
    db,
    appVersion: () async => '1.5.0+4',
    logDirectory: logDir,
    now: () => DateTime.utc(2026, 11, 18, 12),
  );

  test(
    'never includes titles, notes, diary text or attachment names',
    () async {
      const sentinel = 'SENTINEL_PRIVATE_92831';
      final todoId = await db.addTodoItem(
        'Task $sentinel',
        null,
        notes: 'Note $sentinel',
      );
      await db
          .into(db.diaryEntries)
          .insert(
            DiaryEntriesCompanion.insert(
              id: 'diary-1',
              date: DateTime(2026, 11, 18),
              mood: 3,
              content: 'Diary $sentinel',
            ),
          );
      await db
          .into(db.events)
          .insert(
            EventsCompanion.insert(
              id: 'event-1',
              title: 'Event $sentinel',
              description: const Value('Description $sentinel'),
              startTime: DateTime(2026, 11, 18, 9),
            ),
          );
      await db
          .into(db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              id: 'attachment-1',
              todoId: Value(todoId),
              kind: 'file',
              displayName: 'file-$sentinel.txt',
              mimeType: 'text/plain',
              sizeBytes: 5,
              sha256: 'a' * 64,
              createdAt: DateTime(2026, 11, 18),
              updatedAt: DateTime(2026, 11, 18),
            ),
          );

      final json = await service().buildJson();
      expect(json, isNot(contains(sentinel)));
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['app']['version'], '1.5.0+4');
      expect(
        decoded['database']['schema_version'],
        AppDatabase.currentSchemaVersion,
      );
      expect(decoded['counts']['todo_items'], 1);
      expect(decoded['counts']['attachments'], 1);
    },
  );

  test('scrubs user profile paths from the log', () async {
    await File('${logDir.path}/locus_error.log').writeAsString(
      'failed to read C:\\Users\\alice\\Documents\\private.txt\n'
      'also /home/alice/private.txt\n',
    );
    final json = await service().buildJson();
    expect(json, isNot(contains('alice')));
    expect(json, contains('<home>'));
  });

  test('the ZIP contains the report and the scrubbed log', () async {
    final bytes = await service().buildZip();
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = {for (final entry in archive.files) entry.name};
    expect(
      names,
      containsAll(['diagnostics.json', 'error-log.txt', 'README.txt']),
    );
  });

  test(
    'the reminder buffer keeps only the newest 200 content-free entries',
    () {
      for (var index = 0; index < 205; index++) {
        ReminderDiagnostics.fired(kind: 'event', minutesLate: index);
      }
      final snapshot = ReminderDiagnostics.snapshot();
      expect(snapshot, hasLength(200));
      expect(snapshot.first['minutesLate'], 5);
      expect(snapshot.last['minutesLate'], 204);
      expect(snapshot.first.keys, isNot(contains('title')));
    },
  );
}
