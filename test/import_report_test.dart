// Importing backups from other versions: settings, best-effort restore, report.
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/data_export_service.dart';
import 'package:locus_planner/core/utils/recurrence.dart';

void main() {
  const jan1 = 1767225600000; // 2026-01-01T00:00:00Z

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<RestoreReport> restore(Map<String, Object?> backup) =>
      DataExportService(db).restoreFromJson(jsonEncode(backup));

  test(
    'rejects arbitrary JSON objects before replacing database data',
    () async {
      await restore({
        'projects': [
          {'id': 'keep', 'name': 'Keep', 'createdAt': jan1},
        ],
      });

      await expectLater(
        DataExportService(db).restoreFromJson(jsonEncode({'hello': 'world'})),
        throwsA(isA<FormatException>()),
      );

      expect((await db.select(db.projects).get()).map((p) => p.id), ['keep']);
    },
  );

  test(
    'rejects null recognized sections without replacing existing data',
    () async {
      await restore({
        'projects': [
          {'id': 'keep', 'name': 'Keep', 'createdAt': jan1},
        ],
      });

      await expectLater(
        restore({'projects': null}),
        throwsA(isA<FormatException>()),
      );

      expect((await db.select(db.projects).getSingle()).id, 'keep');
    },
  );

  test('rejects empty ids without replacing existing data', () async {
    await restore({
      'projects': [
        {'id': 'keep', 'name': 'Keep', 'createdAt': jan1},
      ],
    });

    await expectLater(
      restore({
        'projects': [
          {'id': '', 'name': 'Bad', 'createdAt': jan1},
        ],
      }),
      throwsA(isA<FormatException>()),
    );

    expect((await db.select(db.projects).getSingle()).id, 'keep');
  });

  group('settings', () {
    test('a backup without app_settings keeps the current settings', () async {
      await db.setSetting('theme', 'dark');
      await db.setSetting(
        AppDatabase.focusSessionSettingKey,
        '{"running":true}',
      );

      await restore({'projects': <Object>[]});

      expect(await db.getSetting('theme'), 'dark');
      expect(
        await db.getSetting(AppDatabase.focusSessionSettingKey),
        '{"running":true}',
      );
    });

    test(
      'a backup with app_settings replaces ordinary settings only',
      () async {
        await db.setSetting('old', '1');
        await db.setSetting(
          AppDatabase.lastAutoBackupSettingKey,
          '2026-01-01T00:00:00',
        );

        await restore({
          'app_settings': [
            {'key': 'new', 'value': '2'},
            {
              'key': AppDatabase.lastAutoBackupSettingKey,
              'value': 'from-backup',
            },
          ],
        });

        expect(await db.getSetting('old'), isNull);
        expect(await db.getSetting('new'), '2');
        expect(
          await db.getSetting(AppDatabase.lastAutoBackupSettingKey),
          '2026-01-01T00:00:00',
        );
      },
    );
  });

  group('best-effort restore', () {
    test('out-of-range values are moved into range and counted', () async {
      final report = await restore({
        'projects': [
          {'id': 'p1', 'name': 'A', 'createdAt': jan1, 'targetProgress': 100},
        ],
        'progress_logs': [
          {'id': 'pl', 'projectId': 'p1', 'value': 140, 'timestamp': jan1},
        ],
        'habits': [
          {'id': 'h1', 'name': 'Read', 'createdAt': jan1, 'targetPerWeek': 0},
        ],
        'events': [
          {'id': 'e1', 'title': 'T', 'startTime': jan1, 'reminderMinutes': -5},
        ],
        'diary_entries': [
          {'id': 'd1', 'date': jan1, 'mood': 9, 'content': 'x'},
        ],
        'focus_sessions': [
          {'id': 'f1', 'startTime': jan1, 'durationMinutes': 5000},
        ],
      });

      expect(report.adjustedValues, 5);
      expect(report.skippedRows, 0);
      expect(report.isClean, isFalse);
      expect(report.summary, '5 values adjusted');

      expect((await db.select(db.progressLogs).getSingle()).value, 100);
      expect((await db.select(db.habits).getSingle()).targetPerWeek, 1);
      expect((await db.select(db.events).getSingle()).reminderMinutes, 0);
      expect((await db.select(db.diaryEntries).getSingle()).mood, 5);
      expect(
        (await db.select(db.focusSessions).getSingle()).durationMinutes,
        1440,
      );
    });

    test('duplicates and orphaned rows are skipped and counted', () async {
      final report = await restore({
        'projects': [
          {'id': 'p1', 'name': 'A', 'createdAt': jan1},
        ],
        'habits': [
          {'id': 'h1', 'name': 'Read', 'createdAt': jan1},
        ],
        'tasks': [
          {'id': 't1', 'projectId': 'p1', 'title': 'kept'},
          {'id': 't2', 'projectId': 'gone', 'title': 'orphan'},
        ],
        'habit_logs': [
          {'id': 'l1', 'habitId': 'h1', 'date': jan1},
          {'id': 'l2', 'habitId': 'h1', 'date': jan1},
          {'id': 'l3', 'habitId': 'ghost', 'date': jan1},
        ],
        'diary_entries': [
          {'id': 'd1', 'date': jan1, 'mood': 3, 'content': 'first'},
          {'id': 'd2', 'date': jan1, 'mood': 4, 'content': 'second'},
        ],
      });

      expect(report.skippedRows, 4);
      expect(report.summary, '4 rows skipped');
      expect((await db.select(db.tasks).get()).map((t) => t.id), ['t1']);
      expect((await db.select(db.habitLogs).get()).map((l) => l.id), ['l1']);
      expect((await db.select(db.diaryEntries).getSingle()).content, 'first');
    });

    test('duplicate primary keys are skipped and counted', () async {
      final report = await restore({
        'projects': [
          {'id': 'p1', 'name': 'First', 'createdAt': jan1},
          {'id': 'p1', 'name': 'Duplicate', 'createdAt': jan1},
        ],
        'events': [
          {'id': 'e1', 'title': 'First', 'startTime': jan1},
          {'id': 'e1', 'title': 'Duplicate', 'startTime': jan1},
        ],
      });

      expect(report.skippedRows, 2);
      expect((await db.select(db.projects).get()).map((p) => p.id), ['p1']);
      expect((await db.select(db.events).get()).map((e) => e.id), ['e1']);
      expect((await db.select(db.events).getSingle()).title, 'First');
    });

    test(
      'a focus session pointing at a missing project is kept, unlinked',
      () async {
        final report = await restore({
          'focus_sessions': [
            {
              'id': 'f1',
              'projectId': 'gone',
              'startTime': jan1,
              'durationMinutes': 25,
            },
          ],
        });

        expect(
          (await db.select(db.focusSessions).getSingle()).projectId,
          isNull,
        );
        expect(report.adjustedValues, 1);
      },
    );

    test(
      'an unrecognised recurrence rule is kept and shown as a single event',
      () async {
        final report = await restore({
          'events': [
            {
              'id': 'e1',
              'title': 'Future',
              'startTime': jan1,
              'recurrenceRule': 'every_blue_moon',
            },
          ],
        });

        final event = await db.select(db.events).getSingle();
        expect(event.recurrenceRule, 'every_blue_moon');
        expect(report.isClean, isTrue);

        final shown = Recurrence.expand(
          event,
          event.startTime.subtract(const Duration(hours: 1)),
          event.startTime.add(const Duration(hours: 1)),
        );
        expect(shown, hasLength(1));
      },
    );

    test('a normal backup produces a clean report', () async {
      final report = await restore({
        'projects': [
          {'id': 'p1', 'name': 'A', 'createdAt': jan1},
        ],
      });
      expect(report.isClean, isTrue);
      expect(report.summary, isEmpty);
    });

    test(
      'malformed files are still rejected without touching existing data',
      () async {
        await restore({
          'projects': [
            {'id': 'keep', 'name': 'Keep', 'createdAt': jan1},
          ],
        });

        await expectLater(
          restore({
            'projects': [
              {'id': 'bad', 'name': 'Bad', 'createdAt': 'not a date'},
            ],
          }),
          throwsA(isA<FormatException>()),
        );

        expect((await db.select(db.projects).getSingle()).id, 'keep');
      },
    );
  });
}
