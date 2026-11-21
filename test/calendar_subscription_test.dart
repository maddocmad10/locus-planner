import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/calendar_subscription_service.dart';

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
}
