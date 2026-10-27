import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';
import 'package:locus_planner/core/utils/diary_merge.dart';

void main() {
  group('mergeDiaryContent', () {
    test('appends the other text after a divider', () {
      expect(
        mergeDiaryContent('first', 'second'),
        'first${diaryMergeDivider}second',
      );
    });

    test('returns the survivor unchanged when there is nothing to add', () {
      expect(mergeDiaryContent('first\n', ''), 'first\n');
      expect(mergeDiaryContent('first\n', '  \n'), 'first\n');
      expect(mergeDiaryContent('first\n', 'first'), 'first\n');
    });

    test('an empty survivor takes the other text', () {
      expect(mergeDiaryContent('', '  second \n'), 'second');
    });

    test('is idempotent, so re-merging never grows the entry', () {
      final merged = mergeDiaryContent('first', 'second');
      expect(mergeDiaryContent(merged, 'second'), merged);
      expect(mergeDiaryContent(merged, merged), merged);
      expect(mergeDiaryContent(merged, 'first'), merged);
    });

    test('keeps both texts when one is a substring of the other', () {
      final merged = mergeDiaryContent('Went to the park', 'park');
      expect(merged, 'Went to the park${diaryMergeDivider}park');
    });
  });

  group('same-day clash between two devices', () {
    const insert =
        'INSERT INTO diary_entries (id, date, mood, content) '
        'VALUES (?, 1760000000, 3, ?)';

    late AppDatabase desktop;
    late AppDatabase phone;

    setUp(() async {
      desktop = AppDatabase.forTesting(NativeDatabase.memory());
      phone = AppDatabase.forTesting(NativeDatabase.memory());
      await desktop.ensureDeviceIdentity();
      await phone.ensureDeviceIdentity();
    });

    tearDown(() async {
      await desktop.close();
      await phone.close();
    });

    /// Everything a device has queued, as the changes a peer would receive.
    /// The outbox is cleared, as if the peer had acknowledged it.
    Future<List<Map<String, dynamic>>> takeOutbox(AppDatabase db) async {
      final rows = await db
          .customSelect(
            'SELECT entity_type, entity_id, operation, payload, device_id '
            'FROM sync_outbox ORDER BY id',
          )
          .get();
      await db.customStatement('DELETE FROM sync_outbox');
      return [
        for (final row in rows)
          {
            'entityType': row.read<String>('entity_type'),
            'entityId': row.read<String>('entity_id'),
            'operation': row.read<String>('operation'),
            'payload': jsonDecode(row.read<String>('payload')),
            'deviceId': row.readNullable<String>('device_id'),
          },
      ];
    }

    /// Exchanges changes in both directions until neither device has anything
    /// left to send. A merge that bounced back and forth would never settle.
    Future<void> settle() async {
      for (var round = 0; round < 6; round++) {
        final fromDesktop = await takeOutbox(desktop);
        final fromPhone = await takeOutbox(phone);
        if (fromDesktop.isEmpty && fromPhone.isEmpty) return;
        if (fromDesktop.isNotEmpty) {
          await SyncChangeApplier(phone).apply(fromDesktop);
        }
        if (fromPhone.isNotEmpty) {
          await SyncChangeApplier(desktop).apply(fromPhone);
        }
      }
      fail('The diary clash did not settle within 6 rounds');
    }

    Future<List<Map<String, String>>> diaryRows(AppDatabase db) async {
      final rows = await db
          .customSelect(
            'SELECT id, content FROM diary_entries WHERE date = 1760000000',
          )
          .get();
      return [
        for (final row in rows)
          {
            'id': row.read<String>('id'),
            'content': row.read<String>('content'),
          },
      ];
    }

    test('desktop id is lower: both devices keep it with both texts', () async {
      await desktop.customStatement(insert, ['a-desktop', 'desktop text']);
      await phone.customStatement(insert, ['z-phone', 'phone text']);

      await settle();

      final expected = [
        {
          'id': 'a-desktop',
          'content': mergeDiaryContent('desktop text', 'phone text'),
        },
      ];
      expect(await diaryRows(desktop), expected);
      expect(await diaryRows(phone), expected);
    });

    test('phone id is lower: both devices keep it with both texts', () async {
      await desktop.customStatement(insert, ['z-desktop', 'desktop text']);
      await phone.customStatement(insert, ['a-phone', 'phone text']);

      await settle();

      final expected = [
        {
          'id': 'a-phone',
          'content': mergeDiaryContent('phone text', 'desktop text'),
        },
      ];
      expect(await diaryRows(desktop), expected);
      expect(await diaryRows(phone), expected);
    });

    test('identical text is not duplicated', () async {
      await desktop.customStatement(insert, ['a-desktop', 'same day']);
      await phone.customStatement(insert, ['z-phone', 'same day']);

      await settle();

      final expected = [
        {'id': 'a-desktop', 'content': 'same day'},
      ];
      expect(await diaryRows(desktop), expected);
      expect(await diaryRows(phone), expected);
    });

    test('a stale copy of the losing entry changes nothing', () async {
      await desktop.customStatement(insert, ['a-desktop', 'desktop text']);
      await phone.customStatement(insert, ['z-phone', 'phone text']);
      await settle();
      final before = await diaryRows(desktop);

      final result = await SyncChangeApplier(desktop).apply([
        {
          'entityType': 'diary_entry',
          'entityId': 'z-phone',
          'operation': 'upsert',
          'payload': {
            'id': 'z-phone',
            'date': 1760000000,
            'mood': 3,
            'content': 'phone text',
          },
        },
      ]);

      expect(result.applied, 0);
      expect(result.skipped, 1);
      expect(await diaryRows(desktop), before);
      expect(await takeOutbox(desktop), isEmpty);
    });
  });
}
