import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/calendar_subscription_service.dart';
import 'package:locus_planner/core/utils/app_clock.dart';

String _calendar(String body) =>
    'BEGIN:VCALENDAR\nVERSION:2.0\n${body}END:VCALENDAR\n';

String _event({
  required String uid,
  required String summary,
  required String start,
  String? end,
  String? status,
  String? rrule,
}) =>
    'BEGIN:VEVENT\n'
    'UID:$uid\n'
    'SUMMARY:$summary\n'
    'DTSTART:$start\n'
    '${end == null ? '' : 'DTEND:$end\n'}'
    '${status == null ? '' : 'STATUS:$status\n'}'
    '${rrule == null ? '' : 'RRULE:$rrule\n'}'
    'END:VEVENT\n';

class _FakeSecrets extends CalendarSecretStore {
  final Map<String, String> values = {};

  @override
  Future<void> write(String ref, String value) async => values[ref] = value;

  @override
  Future<String?> read(String ref) async => values[ref];

  @override
  Future<void> delete(String ref) async => values.remove(ref);
}

void main() {
  late AppDatabase db;
  late _FakeSecrets secrets;
  late CalendarFeedFetcher fetcher;
  late CalendarFetchResult next;
  late CalendarSubscriptionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    secrets = _FakeSecrets();
    next = CalendarFetchResult(
      statusCode: 200,
      body:
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:meeting-1\n'
          'DTSTART:20261201T090000\n'
          'DTEND:20261201T100000\n'
          'SUMMARY:Team meeting\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n',
      etag: '"v1"',
    );
    fetcher = (uri, {etag, lastModified}) async => next;
    service = CalendarSubscriptionService(
      db,
      fetcher: fetcher,
      secrets: secrets,
    );
  });
  tearDown(() => db.close());

  test(
    'stores the URL only in the secret store and caches occurrences',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics?token=secret'),
      );
      expect(source.lastSuccess, isNotNull);
      expect(secrets.values.values.single, contains('token=secret'));
      final rows = await db
          .customSelect('SELECT * FROM calendar_sources')
          .get();
      expect(rows.single.read<String>('secret_ref'), isNot(contains('token')));
      final occurrences = await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      );
      expect(occurrences.single.title, 'Team meeting');
      expect(occurrences.single.allDay, isFalse);
      expect(occurrences.single.start, DateTime(2026, 12, 1, 9));
    },
  );

  test('a 304 keeps the cached window and refreshes the check time', () async {
    await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    next = const CalendarFetchResult(statusCode: 304, body: '');
    final source = await service.refresh((await service.sources()).single.id);
    expect(source.lastSuccess, isNotNull);
    expect(
      await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      ),
      hasLength(1),
    );
  });

  test(
    'a failed refresh keeps the last valid calendar and records the error',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      next = const CalendarFetchResult(statusCode: 500, body: 'nope');
      await expectLater(service.refresh(source.id), throwsStateError);
      final after = (await service.sources()).single;
      expect(after.lastError, 'http_500');
      expect(
        await service.occurrencesBetween(
          DateTime(2026, 12, 1),
          DateTime(2026, 12, 1),
        ),
        hasLength(1),
      );
    },
  );

  test('a successful refresh replaces the window without duplicates', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    next = CalendarFetchResult(
      statusCode: 200,
      body:
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:meeting-1\n'
          'DTSTART:20261202T090000\n'
          'DTEND:20261202T100000\n'
          'SUMMARY:Moved meeting\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n',
      etag: '"v2"',
    );
    await service.refresh(source.id);
    final rows = await db
        .customSelect('SELECT * FROM calendar_occurrences')
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('title'), 'Moved meeting');
  });

  test('a valid empty feed replaces the last generation', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    next = const CalendarFetchResult(
      statusCode: 200,
      body: 'BEGIN:VCALENDAR\nVERSION:2.0\nEND:VCALENDAR\n',
    );
    await service.refresh(source.id);
    expect(
      await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      ),
      isEmpty,
    );
  });

  test('a 304 advances last success to the actual check time', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    final before = (await service.sources()).single.lastSuccess!;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    next = const CalendarFetchResult(statusCode: 304, body: '');
    await service.refresh(source.id);
    final after = (await service.sources()).single.lastSuccess!;
    expect(after.isAfter(before), isTrue);
    expect(after.difference(before), greaterThan(Duration.zero));
  });

  test('an unsupported partial response keeps the previous calendar', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    next = const CalendarFetchResult(
      statusCode: 200,
      body:
          'BEGIN:VCALENDAR\n'
          'BEGIN:VEVENT\n'
          'UID:broken\n'
          'SUMMARY:No start\n'
          'END:VEVENT\n'
          'END:VCALENDAR\n',
    );
    await expectLater(service.refresh(source.id), throwsA(anything));
    expect(
      (await service.sources()).single.lastError,
      'unsupported_partial_feed',
    );
    expect(
      await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      ),
      hasLength(1),
    );
  });

  test('disconnect clears only that source cache and its secret', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    await service.disconnect(source.id);
    expect(await service.sources(), isEmpty);
    expect(secrets.values, isEmpty);
    expect(
      (await db.customSelect('SELECT * FROM calendar_occurrences').get()),
      isEmpty,
    );
  });

  test('non-HTTPS subscriptions are refused', () async {
    await expectLater(
      service.addSource(
        label: 'Plain',
        url: Uri.parse('http://example.com/team.ics'),
      ),
      throwsFormatException,
    );
  });

  test(
    'a complete response publishes every meeting and advances metadata',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final before = (await service.sources()).single;
      next = CalendarFetchResult(
        statusCode: 200,
        body: _calendar(
          _event(
                uid: 'meeting-1',
                summary: 'Team meeting',
                start: '20261201T090000',
                end: '20261201T100000',
              ) +
              _event(
                uid: 'meeting-2',
                summary: 'Second meeting',
                start: '20261201T140000',
                end: '20261201T150000',
              ),
        ),
        etag: '"v2"',
        lastModified: 'Tue, 01 Dec 2026 10:00:00 GMT',
      );

      final after = await service.refresh(source.id);
      final occurrences = await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      );

      expect(
        occurrences.map((occurrence) => occurrence.title).toList()..sort(),
        ['Second meeting', 'Team meeting'],
      );
      expect(after.cacheRevision, before.cacheRevision + 1);
      expect(after.etag, '"v2"');
      expect(after.lastModified, 'Tue, 01 Dec 2026 10:00:00 GMT');
      expect(after.lastError, isNull);
      expect(after.lastSuccess, isNotNull);
      expect(after.coverageStart, isNotNull);
      expect(after.coverageEnd!.isAfter(after.coverageStart!), isTrue);
    },
  );

  test(
    'truncated feeds keep last good rows, validators and generation',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final before = (await service.sources()).single;
      final cases = <String, String>{
        'EOF after BEGIN:VCALENDAR': 'BEGIN:VCALENDAR\nVERSION:2.0\n',
        'EOF inside the first event':
            'BEGIN:VCALENDAR\nVERSION:2.0\n'
            'BEGIN:VEVENT\n'
            'UID:meeting-1\n'
            'SUMMARY:Team meeting\n'
            'DTSTART:20261201T090000\n',
        'EOF after one complete event with a second truncated': _calendar(
          '${_event(uid: 'meeting-1', summary: 'Team meeting', start: '20261201T090000')}BEGIN:VEVENT\nUID:meeting-2\nSUMMARY:Second\n',
        ),
      };

      var index = 0;
      for (final entry in cases.entries) {
        next = CalendarFetchResult(
          statusCode: 200,
          body: entry.value,
          etag: '"truncated-${index++}"',
        );
        await expectLater(
          service.refresh(source.id),
          throwsA(isA<FormatException>()),
          reason: entry.key,
        );
        final after = (await service.sources()).single;
        expect(after.lastError, 'truncated_feed', reason: entry.key);
        expect(after.cacheRevision, before.cacheRevision, reason: entry.key);
        expect(after.etag, before.etag, reason: entry.key);
        expect(after.lastModified, before.lastModified, reason: entry.key);
        expect(after.coverageStart, before.coverageStart, reason: entry.key);
        expect(after.coverageEnd, before.coverageEnd, reason: entry.key);
        expect(after.lastSuccess, before.lastSuccess, reason: entry.key);
        expect(
          await service.occurrencesBetween(
            DateTime(2026, 12, 1),
            DateTime(2026, 12, 1),
          ),
          hasLength(1),
          reason: entry.key,
        );
      }
    },
  );

  test(
    'a valid empty document replaces rows, coverage and validators',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final before = (await service.sources()).single;
      next = CalendarFetchResult(
        statusCode: 200,
        body: _calendar(''),
        etag: '"empty"',
        lastModified: 'Wed, 02 Dec 2026 10:00:00 GMT',
      );

      final after = await service.refresh(source.id);

      expect(
        await service.occurrencesBetween(
          DateTime(2026, 12, 1),
          DateTime(2026, 12, 1),
        ),
        isEmpty,
      );
      expect(after.cacheRevision, before.cacheRevision + 1);
      expect(after.etag, '"empty"');
      expect(after.lastModified, 'Wed, 02 Dec 2026 10:00:00 GMT');
      expect(after.lastError, isNull);
      expect(after.coverageStart, isNotNull);
      expect(after.coverageEnd, isNotNull);
    },
  );

  test('a cancelled event is removed from the cache', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    next = CalendarFetchResult(
      statusCode: 200,
      body: _calendar(
        _event(
          uid: 'meeting-1',
          summary: 'Team meeting',
          start: '20261201T090000',
          status: 'CANCELLED',
        ),
      ),
      etag: '"cancelled"',
    );

    final after = await service.refresh(source.id);

    expect(
      await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      ),
      isEmpty,
    );
    expect(after.lastError, isNull);
    expect(after.cacheRevision, greaterThan(0));
  });

  test(
    'an unsupported recurring series keeps the previous generation',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final before = (await service.sources()).single;
      next = CalendarFetchResult(
        statusCode: 200,
        body: _calendar(
          _event(
            uid: 'odd-series',
            summary: 'Odd series',
            start: '20261201T090000',
            rrule: 'FREQ=WEEKLY;BYDAY=MO,WE',
          ),
        ),
        etag: '"odd"',
      );

      await expectLater(service.refresh(source.id), throwsStateError);

      final after = (await service.sources()).single;
      expect(after.lastError, 'unsupported_partial_feed');
      expect(after.cacheRevision, before.cacheRevision);
      expect(after.etag, before.etag);
      expect(after.lastModified, before.lastModified);
      expect(after.coverageStart, before.coverageStart);
      expect(after.coverageEnd, before.coverageEnd);
      expect(after.lastSuccess, before.lastSuccess);
      expect(
        await service.occurrencesBetween(
          DateTime(2026, 12, 1),
          DateTime(2026, 12, 1),
        ),
        hasLength(1),
      );
    },
  );

  test('a 304 within coverage keeps rows, validators and generation', () async {
    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    final before = (await service.sources()).single;
    next = const CalendarFetchResult(statusCode: 304, body: '');

    final after = await service.refresh(source.id);

    expect(after.cacheRevision, before.cacheRevision);
    expect(after.etag, before.etag);
    expect(after.lastModified, before.lastModified);
    expect(after.coverageStart, before.coverageStart);
    expect(after.coverageEnd, before.coverageEnd);
    expect(after.lastError, isNull);
    expect(after.lastSuccess!.isBefore(before.lastSuccess!), isFalse);
    expect(
      await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      ),
      hasLength(1),
    );
  });

  test(
    'a 304 that cannot cover the window forces an unconditional fetch',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final now = AppClock.now();
      await db.customStatement(
        'UPDATE calendar_sources SET coverage_start_ms = ?, '
        'coverage_end_ms = ? WHERE id = ?',
        [
          now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
          now.add(const Duration(days: 5)).millisecondsSinceEpoch,
          source.id,
        ],
      );
      var calls = 0;
      service = CalendarSubscriptionService(
        db,
        secrets: secrets,
        fetcher: (uri, {etag, lastModified}) async {
          calls++;
          if (etag != null) {
            return const CalendarFetchResult(statusCode: 304, body: '');
          }
          return CalendarFetchResult(
            statusCode: 200,
            body: _calendar(
              _event(
                    uid: 'meeting-1',
                    summary: 'Team meeting',
                    start: '20261201T090000',
                  ) +
                  _event(
                    uid: 'meeting-2',
                    summary: 'Second meeting',
                    start: '20261201T140000',
                  ),
            ),
            etag: '"fresh"',
            lastModified: 'Tue, 01 Dec 2026 10:00:00 GMT',
          );
        },
      );

      final after = await service.refresh(source.id);

      expect(calls, 2);
      expect(after.etag, '"fresh"');
      expect(after.cacheRevision, source.cacheRevision + 1);
      expect(
        await service.occurrencesBetween(
          DateTime(2026, 12, 1),
          DateTime(2026, 12, 1),
        ),
        hasLength(2),
      );
    },
  );

  test(
    'a late response cannot replace a newer generation or its validators',
    () async {
      final source = await service.addSource(
        label: 'Work',
        url: Uri.parse('https://example.com/team.ics'),
      );
      final pending = <Completer<CalendarFetchResult>>[];
      service = CalendarSubscriptionService(
        db,
        secrets: secrets,
        fetcher: (uri, {etag, lastModified}) {
          final completer = Completer<CalendarFetchResult>();
          pending.add(completer);
          return completer.future;
        },
      );

      final late = service.refresh(source.id);
      while (pending.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final newer = service.refresh(source.id);
      while (pending.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }

      pending[1].complete(
        CalendarFetchResult(
          statusCode: 200,
          body: _calendar(
            _event(
              uid: 'newer',
              summary: 'Newer meeting',
              start: '20261201T140000',
            ),
          ),
          etag: '"newer"',
          lastModified: 'Tue, 01 Dec 2026 14:00:00 GMT',
        ),
      );
      await newer;
      pending[0].complete(
        CalendarFetchResult(
          statusCode: 200,
          body: _calendar(
            _event(
              uid: 'late',
              summary: 'Late meeting',
              start: '20261201T090000',
            ),
          ),
          etag: '"late"',
        ),
      );
      await late;

      final after = (await service.sources()).single;
      expect(after.cacheRevision, source.cacheRevision + 1);
      expect(after.etag, '"newer"');
      expect(after.lastModified, 'Tue, 01 Dec 2026 14:00:00 GMT');
      expect(after.lastError, isNull);
      final occurrences = await service.occurrencesBetween(
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1),
      );
      expect(occurrences.single.title, 'Newer meeting');
    },
  );

  test('a published meeting is visible for today', () async {
    final original = AppClock.now;
    AppClock.now = () => DateTime(2026, 11, 22, 8);
    addTearDown(() => AppClock.now = original);
    next = CalendarFetchResult(
      statusCode: 200,
      body: _calendar(
        _event(
          uid: 'today',
          summary: 'Today meeting',
          start: '20261122T090000',
          end: '20261122T100000',
        ),
      ),
      etag: '"today"',
    );

    final source = await service.addSource(
      label: 'Work',
      url: Uri.parse('https://example.com/team.ics'),
    );
    final today = await service.occurrencesBetween(
      DateTime(2026, 11, 22),
      DateTime(2026, 11, 22),
    );

    expect(today.single.title, 'Today meeting');
    expect(today.single.sourceId, source.id);
  });
}
