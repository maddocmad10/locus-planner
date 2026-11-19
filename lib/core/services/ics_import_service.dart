import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';

import '../db/app_database.dart';
import '../utils/day_math.dart';
import '../utils/recurrence.dart';
import 'ics_import.dart';
import 'undo_service.dart';

class IcsImportReport {
  const IcsImportReport({
    required this.imported,
    this.updated = 0,
    this.skipped = 0,
    this.simplifiedSeries = const [],
    this.simplifiedSkipped = 0,
    this.overridesSkipped = 0,
    this.overridesImported = 0,
    this.exdatesIgnored = 0,
    this.allDayImported = 0,
    this.timezoneFallbacks = 0,
    this.attachmentsIgnored = 0,
  });

  /// New events written.
  final int imported;

  /// Existing events whose id matched and were updated.
  final int updated;

  /// VEVENT blocks that had no usable summary or start time.
  final int skipped;

  /// Titles of recurring series that could not be represented exactly.
  final List<String> simplifiedSeries;

  /// Simplified series left out because the user chose that option.
  final int simplifiedSkipped;

  /// Modified occurrences left out because their master was skipped.
  final int overridesSkipped;

  /// Modified occurrences imported as separate one-off events.
  final int overridesImported;

  final int exdatesIgnored;
  final int allDayImported;
  final int timezoneFallbacks;

  /// ATTACH properties ignored; Locus never downloads remote files.
  final int attachmentsIgnored;

  int get total => imported + updated;
}

/// A parsed calendar waiting for the user's confirmation.
class IcsPreview {
  const IcsPreview({required this.source, required this.parsed});

  final String source;
  final IcsParseResult parsed;

  int get eventCount => parsed.events.length;
  int get allDayCount => parsed.events.where((event) => event.isAllDay).length;
  int get overrideCount =>
      parsed.events.where((event) => event.recurrenceId != null).length;
  int get exdateCount =>
      parsed.events.fold(0, (sum, event) => sum + event.exdates.length);
  List<String> get simplifiedSeries => parsed.simplifiedSeries;
  int get timezoneFallbacks => parsed.timezoneFallbacks;
}

/// RFC 5545 import orchestration: preview, grouping, event id derivation and
/// Undo. The pure parser remains in ics_import.dart.
class IcsImportService {
  IcsImportService(this._db, {this.undo});

  final AppDatabase _db;
  final UndoService? undo;
  static const maxFileBytes = 10 * 1024 * 1024;

  /// Opens a file picker and parses the chosen calendar without writing.
  /// Returns null when the user cancelled.
  Future<IcsPreview?> previewFromPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      dialogTitle: 'Import Events from ICS',
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.single.path;
    if (path == null) return null;
    final content = await readFile(File(path));
    return preview(content);
  }

  /// Parses a calendar without touching the database.
  Future<IcsPreview> preview(String source) async =>
      IcsPreview(source: source, parsed: IcsParser.parse(source));

  /// Backwards-compatible one-step import used by older callers and tests. The
  /// UI should use [preview] and [importPreview] so the user can confirm.
  Future<IcsImportReport?> importFromPicker() async {
    final previewed = await previewFromPicker();
    if (previewed == null) return null;
    return importPreview(previewed, keepSimplified: true);
  }

  /// Pure import entry point used by the picker and regression tests.
  ///
  /// Events are upserted with an id derived from the iCalendar UID, so picking
  /// the same file twice updates its events instead of duplicating them.
  Future<IcsImportReport> importText(String source) async {
    final previewed = await preview(source);
    return importPreview(previewed, keepSimplified: true);
  }

  /// Writes a previewed calendar. [keepSimplified] false omits series whose
  /// replay rule Locus cannot represent exactly.
  Future<IcsImportReport> importPreview(
    IcsPreview preview, {
    required bool keepSimplified,
  }) async {
    final parsed = preview.parsed;
    final companions = <EventsCompanion>[];
    final importedIds = <String>{};
    var simplifiedSkipped = 0;
    var overridesSkipped = 0;
    var overridesImported = 0;
    var allDayImported = 0;

    final groups = <String, List<IcsEvent>>{};
    for (final event in parsed.events) {
      final uid = event.uid?.trim();
      final key = uid != null && uid.isNotEmpty
          ? 'uid:$uid'
          : 'event:${event.summary}|${event.start.toIso8601String()}|'
                '${event.end?.toIso8601String()}|${event.recurrenceRule}';
      groups.putIfAbsent(key, () => []).add(event);
    }

    for (final group in groups.values) {
      IcsEvent? master;
      final overrides = <IcsEvent>[];
      for (final event in group) {
        if (event.recurrenceId == null) {
          master ??= event;
        } else {
          overrides.add(event);
        }
      }

      if (master == null) {
        // An orphaned override has no series to modify; keep it as a one-off.
        for (final override in overrides) {
          companions.add(_companion(override));
          overridesImported++;
          allDayImported += override.isAllDay ? 1 : 0;
        }
        continue;
      }

      if (master.seriesSimplified && !keepSimplified) {
        simplifiedSkipped++;
        overridesSkipped += overrides.length;
        continue;
      }

      final exceptions = <String>{
        for (final day in master.exdates) _dayKey(day),
        for (final override in overrides)
          if (override.recurrenceId != null) _dayKey(override.recurrenceId!),
      };
      companions.add(_companion(master, recurrenceExceptions: exceptions));
      allDayImported += master.isAllDay ? 1 : 0;

      for (final rdate in master.rdates) {
        if (_ruleGenerates(master, rdate)) continue;
        companions.add(_rdateCompanion(master, rdate));
        allDayImported += master.isAllDay ? 1 : 0;
      }

      for (final override in overrides) {
        companions.add(_companion(override, oneOff: true));
        overridesImported++;
        allDayImported += override.isAllDay ? 1 : 0;
      }
    }

    for (final companion in companions) {
      importedIds.add(companion.id.value);
    }
    final existing = <Event>[];
    final ids = importedIds.toList();
    for (var start = 0; start < ids.length; start += 500) {
      final end = (start + 500).clamp(0, ids.length);
      final chunk = ids.sublist(start, end);
      existing.addAll(
        await (_db.select(_db.events)..where((t) => t.id.isIn(chunk))).get(),
      );
    }
    final captured = {for (final event in existing) event.id: event};
    final updated = existing.length;

    await _db.transaction(() async {
      await _db.batch((batch) {
        batch.insertAllOnConflictUpdate(_db.events, companions);
      });
    });

    final undoService = undo;
    if (undoService != null && companions.isNotEmpty) {
      undoService.offer(
        label: 'ICS import',
        restore: () async {
          await _db.transaction(() async {
            for (final id in importedIds) {
              await (_db.delete(
                _db.events,
              )..where((t) => t.id.equals(id))).go();
            }
            for (final event in captured.values) {
              await _db.into(_db.events).insert(event);
            }
          });
        },
      );
    }

    return IcsImportReport(
      imported: companions.length - updated,
      updated: updated,
      skipped: parsed.skipped,
      simplifiedSeries: parsed.simplifiedSeries,
      simplifiedSkipped: simplifiedSkipped,
      overridesSkipped: overridesSkipped,
      overridesImported: overridesImported,
      exdatesIgnored: parsed.exdatesIgnored,
      allDayImported: allDayImported,
      timezoneFallbacks: parsed.timezoneFallbacks,
      attachmentsIgnored: parsed.attachmentsIgnored,
    );
  }

  EventsCompanion _companion(
    IcsEvent event, {
    bool oneOff = false,
    Set<String> recurrenceExceptions = const {},
  }) => EventsCompanion(
    id: Value(_icsEventId(event)),
    title: Value(event.summary),
    description: Value(event.description),
    descriptionFormat: const Value('plain'),
    startTime: Value(event.start),
    endTime: Value(event.end),
    category: Value(event.category),
    hasReminder: Value(!event.isAllDay && event.reminderMinutes != null),
    reminderMinutes: Value(event.reminderMinutes ?? 10),
    recurrenceRule: Value(oneOff ? null : event.recurrenceRule),
    allDay: Value(event.isAllDay),
    recurrenceEnd: Value(oneOff ? null : event.recurrenceEnd),
    recurrenceExceptions: Value(
      oneOff || recurrenceExceptions.isEmpty
          ? '[]'
          : jsonEncode(recurrenceExceptions.toList()..sort()),
    ),
  );

  static String _dayKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static bool _ruleGenerates(IcsEvent master, DateTime at) {
    if (!Recurrence.isRecurring(master.recurrenceRule)) return false;
    final probe = Event(
      id: 'probe',
      title: master.summary,
      description: null,
      descriptionFormat: 'plain',
      startTime: master.start,
      endTime: master.end,
      category: master.category,
      hasReminder: false,
      reminderMinutes: 10,
      recurrenceRule: master.recurrenceRule,
      allDay: master.isAllDay,
      recurrenceEnd: master.recurrenceEnd,
      recurrenceExceptions: '[]',
    );
    final from = DayMath.dateOnly(at);
    return Recurrence.expand(
      probe,
      from,
      DayMath.addDays(from, 1),
    ).any((occurrence) => occurrence.startTime == at);
  }

  static EventsCompanion _rdateCompanion(IcsEvent master, DateTime at) {
    final uid = master.uid?.trim();
    final seed = uid != null && uid.isNotEmpty
        ? 'uid:$uid|rdate:${at.toIso8601String()}'
        : 'event:${master.summary}|${master.start.toIso8601String()}'
              '|rdate:${at.toIso8601String()}';
    return EventsCompanion(
      id: Value(const Uuid().v5(Namespace.url.value, 'locus-ics:$seed')),
      title: Value(master.summary),
      description: Value(master.description),
      descriptionFormat: const Value('plain'),
      startTime: Value(at),
      endTime: Value(null),
      category: Value(master.category),
      hasReminder: const Value(false),
      reminderMinutes: Value(master.reminderMinutes ?? 10),
      recurrenceRule: const Value(null),
      allDay: Value(master.isAllDay),
      recurrenceEnd: const Value(null),
      recurrenceExceptions: const Value('[]'),
    );
  }

  Future<String> readFile(File file) async {
    final length = await file.length();
    if (length > maxFileBytes) {
      throw FormatException(
        'Calendar file is too large. Maximum size is '
        '${maxFileBytes ~/ (1024 * 1024)} MB.',
      );
    }
    return file.readAsString();
  }

  static String _icsEventId(IcsEvent event) {
    final uid = event.uid?.trim();
    if (uid != null && uid.isNotEmpty) {
      final own = RegExp(r'^(.+)@locusplanner$').firstMatch(uid);
      if (own != null) return own.group(1)!;
      if (event.recurrenceId != null) {
        final overrideKey =
            event.recurrenceIdRaw ?? event.recurrenceId!.toIso8601String();
        return const Uuid().v5(
          Namespace.url.value,
          'locus-ics:uid:$uid|recurrence-id:$overrideKey',
        );
      }
      return const Uuid().v5(Namespace.url.value, 'locus-ics:uid:$uid');
    }
    final seed =
        'event:${event.summary}|${event.start.toIso8601String()}|'
        '${event.end?.toIso8601String()}|${event.recurrenceRule}';
    return const Uuid().v5(Namespace.url.value, 'locus-ics:$seed');
  }
}
