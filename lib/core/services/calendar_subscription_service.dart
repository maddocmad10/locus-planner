import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../db/app_database.dart';
import '../utils/app_clock.dart';
import '../utils/day_math.dart';
import '../utils/recurrence.dart';
import 'ics_import.dart';

class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.label,
    required this.enabled,
    required this.etag,
    required this.lastModified,
    required this.lastSuccess,
    required this.lastAttempt,
    required this.lastError,
    required this.coverageStart,
    required this.coverageEnd,
    required this.cacheRevision,
  });

  final String id;
  final String label;
  final bool enabled;
  final String? etag;
  final String? lastModified;
  final DateTime? lastSuccess;
  final DateTime? lastAttempt;
  final String? lastError;
  final DateTime? coverageStart;
  final DateTime? coverageEnd;
  final int cacheRevision;

  bool get isStale =>
      lastSuccess == null ||
      AppClock.now().difference(lastSuccess!) > const Duration(hours: 26);
}

class CalendarFeedOccurrence {
  const CalendarFeedOccurrence({
    required this.sourceId,
    required this.uid,
    required this.recurrenceKey,
    required this.occurrenceStartKey,
    required this.title,
    required this.allDay,
    required this.tzid,
    required this.start,
    required this.end,
    required this.startDate,
    required this.endDate,
  });

  final String sourceId;
  final String uid;
  final String recurrenceKey;
  final String occurrenceStartKey;
  final String title;
  final bool allDay;
  final String? tzid;

  /// Absolute instant for timed occurrences.
  final DateTime? start;
  final DateTime? end;

  /// ISO local dates with an exclusive end for all-day occurrences.
  final String? startDate;
  final String? endDate;
}

class CalendarFetchResult {
  const CalendarFetchResult({
    required this.statusCode,
    required this.body,
    this.etag,
    this.lastModified,
  });

  final int statusCode;
  final String body;
  final String? etag;
  final String? lastModified;
}

typedef CalendarFeedFetcher =
    Future<CalendarFetchResult> Function(
      Uri uri, {
      String? etag,
      String? lastModified,
    });

/// Device-local read-only iCalendar subscriptions. The feed URL may contain a
/// credential, so only the secret store holds it; the database keeps a
/// reference. Cached titles never enter backups, diagnostics or LAN sync.
class CalendarSubscriptionService {
  CalendarSubscriptionService(
    this._db, {
    CalendarFeedFetcher? fetcher,
    CalendarSecretStore? secrets,
  }) : _fetcher = fetcher ?? _httpsFetch,
       _secrets = secrets ?? CalendarSecretStore();

  static const windowPast = Duration(days: 30);
  static const windowAhead = Duration(days: 365);
  static const maxFeedBytes = 5 * 1024 * 1024;

  final AppDatabase _db;
  final CalendarFeedFetcher _fetcher;
  final CalendarSecretStore _secrets;
  final _revisions = StreamController<int>.broadcast();
  int _revision = 0;

  Stream<int> get revisions => _revisions.stream;
  int get revision => _revision;

  Future<List<CalendarSource>> sources() async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM calendar_sources ORDER BY label COLLATE NOCASE',
        )
        .get();
    return [for (final row in rows) _sourceFromRow(row)];
  }

  Future<CalendarSource> addSource({
    required String label,
    required Uri url,
  }) async {
    if (url.scheme != 'https') {
      throw const FormatException('Calendar subscriptions must use HTTPS.');
    }
    final trimmed = label.trim();
    if (trimmed.isEmpty || trimmed.length > 120) {
      throw const FormatException('Give the feed a short label.');
    }
    final id = 'feed_${AppClock.now().microsecondsSinceEpoch}';
    final secretRef = 'calendar.feed.$id';
    await _secrets.write(secretRef, url.toString());
    await _db.customStatement(
      'INSERT INTO calendar_sources '
      '(id, label, kind, secret_ref, enabled) '
      "VALUES (?, ?, 'ics_feed', ?, 1)",
      [id, trimmed, secretRef],
    );
    await refresh(id);
    final all = await sources();
    return all.firstWhere((source) => source.id == id);
  }

  Future<void> disconnect(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT secret_ref FROM calendar_sources WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (rows.isNotEmpty) {
      await _secrets.delete(rows.first.read<String>('secret_ref'));
    }
    await _db.customStatement('DELETE FROM calendar_sources WHERE id = ?', [
      id,
    ]);
    _revision++;
    _revisions.add(_revision);
  }

  Future<void> refreshAll() async {
    for (final source in await sources()) {
      if (!source.enabled) continue;
      try {
        await refresh(source.id);
      } catch (_) {
        // One broken feed must not stop the others.
      }
    }
  }

  Future<CalendarSource> refresh(String id) async {
    final rows = await _db
        .customSelect(
          'SELECT * FROM calendar_sources WHERE id = ?',
          variables: [Variable.withString(id)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Unknown calendar source.');
    final current = _sourceFromRow(rows.first);
    final url = await _secrets.read(rows.first.read<String>('secret_ref'));
    final now = AppClock.now();
    await _db.customStatement(
      'UPDATE calendar_sources SET last_attempt_ms = ? WHERE id = ?',
      [now.millisecondsSinceEpoch, id],
    );
    if (url == null || url.isEmpty) {
      await _recordFailure(id, 'secret_missing');
      throw StateError(
        'The feed credential is missing. Disconnect and add it again.',
      );
    }
    final startRevision = current.cacheRevision;
    try {
      var conditional = true;
      CalendarFetchResult response;
      while (true) {
        response = await _fetcher(
          Uri.parse(url),
          etag: conditional ? current.etag : null,
          lastModified: conditional ? current.lastModified : null,
        );
        if (response.statusCode == 304 && !_coverageAdequate(current, now)) {
          if (!conditional) {
            await _recordFailure(id, 'invalid_feed');
            throw StateError(
              'The feed returned 304 to an unconditional request.',
            );
          }
          // A cached response that does not cover the rolling window cannot
          // answer this refresh; rebuild it with an unconditional 200.
          conditional = false;
          continue;
        }
        break;
      }
      if (response.statusCode == 304) {
        // The check itself succeeded and advanced freshness even though the
        // content generation did not change.
        await _db.customStatement(
          'UPDATE calendar_sources SET last_error_code = NULL, '
          'last_attempt_ms = ?, last_success_ms = ? WHERE id = ?',
          [now.millisecondsSinceEpoch, now.millisecondsSinceEpoch, id],
        );
        return (await sources()).firstWhere((source) => source.id == id);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await _recordFailure(id, 'http_${response.statusCode}');
        throw StateError('The feed returned HTTP ${response.statusCode}.');
      }
      final upper = response.body.toUpperCase();
      if (!upper.contains('BEGIN:VCALENDAR')) {
        await _recordFailure(id, 'invalid_feed');
        throw const FormatException('The feed is not an iCalendar document.');
      }
      final parsed = IcsParser.parse(response.body);
      if (parsed.skipped > 0) {
        await _recordFailure(id, 'unsupported_partial_feed');
        throw StateError(
          'The feed contained unsupported partial events; the previous '
          'calendar was kept.',
        );
      }
      final hasEventBlock = upper.contains('BEGIN:VEVENT');
      final rowsToWrite = parsed.events.isEmpty
          ? <CalendarFeedOccurrence>[]
          : _materialize(id, parsed.events, now);
      if (!hasEventBlock && parsed.events.isNotEmpty) {
        await _recordFailure(id, 'invalid_feed');
        throw const FormatException('The feed has no usable calendar body.');
      }
      final coverageStart = now.subtract(windowPast);
      final coverageEnd = now.add(windowAhead);
      await _db.transaction(() async {
        final currentRows = await _db
            .customSelect(
              'SELECT cache_revision FROM calendar_sources WHERE id = ?',
              variables: [Variable.withString(id)],
            )
            .getSingleOrNull();
        if (currentRows == null ||
            currentRows.read<int>('cache_revision') != startRevision) {
          throw StateError(
            'A newer calendar generation already replaced this fetch.',
          );
        }
        await _db.customStatement(
          'DELETE FROM calendar_occurrences WHERE source_id = ?',
          [id],
        );
        for (final occurrence in rowsToWrite) {
          await _db.customStatement(
            'INSERT OR REPLACE INTO calendar_occurrences '
            '(source_id, uid, recurrence_key, occurrence_start_key, title, '
            'all_day, tzid, start_ms, end_ms, start_date, end_date) '
            'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
            [
              occurrence.sourceId,
              occurrence.uid,
              occurrence.recurrenceKey,
              occurrence.occurrenceStartKey,
              occurrence.title,
              occurrence.allDay ? 1 : 0,
              occurrence.tzid,
              occurrence.start?.toUtc().millisecondsSinceEpoch,
              occurrence.end?.toUtc().millisecondsSinceEpoch,
              occurrence.startDate,
              occurrence.endDate,
            ],
          );
        }
        await _db.customStatement(
          'UPDATE calendar_sources SET etag = ?, last_modified = ?, '
          'last_attempt_ms = ?, last_success_ms = ?, last_error_code = NULL, '
          'coverage_start_ms = ?, coverage_end_ms = ?, '
          'cache_revision = cache_revision + 1 WHERE id = ?',
          [
            response.etag ?? current.etag,
            response.lastModified ?? current.lastModified,
            now.millisecondsSinceEpoch,
            now.millisecondsSinceEpoch,
            coverageStart.millisecondsSinceEpoch,
            coverageEnd.millisecondsSinceEpoch,
            id,
          ],
        );
      });
      _revision++;
      _revisions.add(_revision);
      return (await sources()).firstWhere((source) => source.id == id);
    } catch (error) {
      await _recordFailure(id, _errorCode(error));
      rethrow;
    }
  }

  bool _coverageAdequate(CalendarSource source, DateTime now) {
    final start = source.coverageStart;
    final end = source.coverageEnd;
    if (start == null || end == null) return false;
    const slack = Duration(days: 1);
    return !start.isAfter(now.subtract(windowPast).add(slack)) &&
        !end.isBefore(now.add(windowAhead).subtract(slack));
  }

  Future<List<CalendarFeedOccurrence>> occurrencesBetween(
    DateTime from,
    DateTime to,
  ) async {
    final start = DayMath.dateOnly(from).millisecondsSinceEpoch;
    final end = DayMath.addDays(DayMath.dateOnly(to), 1).millisecondsSinceEpoch;
    final rows = await _db
        .customSelect(
          'SELECT o.* FROM calendar_occurrences o '
          'JOIN calendar_sources s ON s.id = o.source_id '
          'WHERE s.enabled = 1 AND ('
          '  (o.start_ms IS NOT NULL AND o.start_ms < ? AND '
          '   COALESCE(o.end_ms, o.start_ms) >= ?) OR '
          '  (o.start_date IS NOT NULL AND o.start_date < ? AND '
          '   COALESCE(o.end_date, o.start_date) > ?)'
          ') ORDER BY o.start_ms, o.start_date',
          variables: [
            Variable.withInt(end),
            Variable.withInt(start),
            Variable.withString(
              _dateKey(DayMath.addDays(DayMath.dateOnly(to), 1)),
            ),
            Variable.withString(_dateKey(DayMath.dateOnly(from))),
          ],
        )
        .get();
    return [for (final row in rows) _occurrenceFromRow(row)];
  }

  List<CalendarFeedOccurrence> _materialize(
    String sourceId,
    List<IcsEvent> events,
    DateTime now,
  ) {
    final from = now.subtract(windowPast);
    final to = now.add(windowAhead);
    final overrides = <String, IcsEvent>{};
    for (final event in events) {
      if (event.recurrenceId != null) {
        overrides['${event.uid}|${event.recurrenceId!.millisecondsSinceEpoch}'] =
            event;
      }
    }
    final result = <CalendarFeedOccurrence>[];
    for (final event in events) {
      if (event.recurrenceId != null) continue;
      if (event.cancelled) continue;
      final uid =
          event.uid ?? '${event.summary}|${event.start.toIso8601String()}';
      var exceptions = '[]';
      for (final excluded in event.exdates) {
        exceptions = Recurrence.addException(exceptions, excluded);
      }
      final probe = Event(
        id: 'feed',
        title: event.summary,
        description: event.description,
        descriptionFormat: 'plain',
        startTime: event.start,
        endTime: event.end,
        category: 'general',
        hasReminder: false,
        reminderMinutes: 10,
        recurrenceRule: event.recurrenceRule,
        allDay: event.isAllDay,
        recurrenceEnd: event.recurrenceEnd,
        recurrenceExceptions: exceptions,
      );
      final occurrenceStarts = Recurrence.isRecurring(event.recurrenceRule)
          ? [
              for (final occurrence in Recurrence.expand(probe, from, to))
                occurrence.startTime,
            ]
          : [
              if (event.start.isAfter(from) && event.start.isBefore(to))
                event.start,
            ];
      for (final occurrenceStart in occurrenceStarts) {
        final overrideKey = '$uid|${occurrenceStart.millisecondsSinceEpoch}';
        final override = overrides[overrideKey];
        if (override?.cancelled == true) continue;
        final actual = override ?? event;
        final start = override?.start ?? occurrenceStart;
        final occurrenceKey = override != null
            ? '${override.recurrenceId!.millisecondsSinceEpoch}'
            : '${occurrenceStart.millisecondsSinceEpoch}';
        result.add(
          _row(
            sourceId: sourceId,
            uid: uid,
            recurrenceKey: uid,
            occurrenceKey: occurrenceKey,
            event: actual,
            start: start,
          ),
        );
      }
    }
    return result;
  }

  CalendarFeedOccurrence _row({
    required String sourceId,
    required String uid,
    required String recurrenceKey,
    required String occurrenceKey,
    required IcsEvent event,
    required DateTime start,
  }) {
    final end = event.end == null
        ? null
        : start.add(event.end!.difference(event.start));
    if (event.isAllDay) {
      final startDate = _dateKey(start);
      final endDate = _dateKey(end ?? DayMath.addDays(start, 1));
      return CalendarFeedOccurrence(
        sourceId: sourceId,
        uid: uid,
        recurrenceKey: recurrenceKey,
        occurrenceStartKey: occurrenceKey,
        title: event.summary,
        allDay: true,
        tzid: event.tzid,
        start: null,
        end: null,
        startDate: startDate,
        endDate: endDate,
      );
    }
    return CalendarFeedOccurrence(
      sourceId: sourceId,
      uid: uid,
      recurrenceKey: recurrenceKey,
      occurrenceStartKey: occurrenceKey,
      title: event.summary,
      allDay: false,
      tzid: event.tzid,
      start: start,
      end: end ?? start.add(const Duration(minutes: 30)),
      startDate: null,
      endDate: null,
    );
  }

  Future<void> _recordFailure(String id, String code) async {
    await _db.customStatement(
      'UPDATE calendar_sources SET last_error_code = ? WHERE id = ?',
      [code, id],
    );
  }

  String _errorCode(Object error) {
    if (error is SocketException) return 'network_unavailable';
    if (error is TimeoutException) return 'timeout';
    if (error is FormatException) return 'invalid_feed';
    if (error is StateError) {
      final http = RegExp(r'HTTP (\d{3})').firstMatch(error.message);
      if (http != null) return 'http_${http.group(1)}';
      if (error.message.contains('no supported events') ||
          error.message.contains('no displayable occurrences') ||
          error.message.contains('unsupported partial')) {
        return 'unsupported_partial_feed';
      }
    }
    return 'refresh_failed';
  }

  static CalendarSource _sourceFromRow(dynamic row) => CalendarSource(
    id: row.read<String>('id'),
    label: row.read<String>('label'),
    enabled: row.read<int>('enabled') == 1,
    etag: row.readNullable<String>('etag'),
    lastModified: row.readNullable<String>('last_modified'),
    lastSuccess: _date(row.readNullable<int>('last_success_ms')),
    lastAttempt: _date(row.readNullable<int>('last_attempt_ms')),
    lastError: row.readNullable<String>('last_error_code'),
    coverageStart: _date(row.readNullable<int>('coverage_start_ms')),
    coverageEnd: _date(row.readNullable<int>('coverage_end_ms')),
    cacheRevision: row.readNullable<int>('cache_revision') ?? 0,
  );

  static CalendarFeedOccurrence _occurrenceFromRow(dynamic row) =>
      CalendarFeedOccurrence(
        sourceId: row.read<String>('source_id'),
        uid: row.read<String>('uid'),
        recurrenceKey: row.read<String>('recurrence_key'),
        occurrenceStartKey: row.read<String>('occurrence_start_key'),
        title: row.read<String>('title'),
        allDay: row.read<int>('all_day') == 1,
        tzid: row.readNullable<String>('tzid'),
        start: _date(row.readNullable<int>('start_ms')),
        end: _date(row.readNullable<int>('end_ms')),
        startDate: row.readNullable<String>('start_date'),
        endDate: row.readNullable<String>('end_date'),
      );

  static DateTime? _date(int? ms) =>
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Future<CalendarFetchResult> _httpsFetch(
    Uri uri, {
    String? etag,
    String? lastModified,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      if (etag != null) request.headers.set('If-None-Match', etag);
      if (lastModified != null) {
        request.headers.set('If-Modified-Since', lastModified);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode == 304) {
        return CalendarFetchResult(statusCode: 304, body: '');
      }
      final builder = BytesBuilder(copy: false);
      var bytes = 0;
      await for (final chunk in response) {
        bytes += chunk.length;
        if (bytes > maxFeedBytes) {
          throw const FormatException('The calendar feed is too large.');
        }
        builder.add(chunk);
      }
      return CalendarFetchResult(
        statusCode: response.statusCode,
        body: utf8.decode(builder.takeBytes(), allowMalformed: false),
        etag: response.headers.value(HttpHeaders.etagHeader),
        lastModified: response.headers.value(HttpHeaders.lastModifiedHeader),
      );
    } finally {
      client.close(force: true);
    }
  }
}

class CalendarSecretStore {
  CalendarSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _prefix = 'locus.calendar.';
  final FlutterSecureStorage _storage;

  Future<void> write(String ref, String value) =>
      _storage.write(key: '$_prefix$ref', value: value);

  Future<String?> read(String ref) => _storage.read(key: '$_prefix$ref');

  Future<void> delete(String ref) => _storage.delete(key: '$_prefix$ref');
}
