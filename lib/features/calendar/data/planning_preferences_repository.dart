import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/capacity_service.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';

/// One editable working interval. [id] is empty for a draft that has not been
/// persisted yet.
class WorkingWindowDraft {
  const WorkingWindowDraft({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    this.id = '',
    this.enabled = true,
    this.label,
  });

  final String id;
  final int weekday;
  final bool enabled;
  final int startMinute;
  final int endMinute;
  final String? label;

  ClockWindow get window => ClockWindow(startMinute, endMinute);

  WorkingWindowDraft copyWith({
    String? id,
    int? weekday,
    bool? enabled,
    int? startMinute,
    int? endMinute,
    String? label,
  }) => WorkingWindowDraft(
    id: id ?? this.id,
    weekday: weekday ?? this.weekday,
    enabled: enabled ?? this.enabled,
    startMinute: startMinute ?? this.startMinute,
    endMinute: endMinute ?? this.endMinute,
    label: label ?? this.label,
  );
}

/// The complete planning profile: preferences plus the weekday rules.
class PlanningProfile {
  const PlanningProfile({
    required this.id,
    required this.timezoneId,
    required this.defaultSlotMinutes,
    required this.weekStartDay,
    required this.dayStartMinute,
    required this.dayEndMinute,
    required this.bufferMinutes,
    required this.urgencyWindowDays,
    required this.workingHours,
    required this.breaks,
  });

  final String id;
  final String? timezoneId;
  final int defaultSlotMinutes;
  final int weekStartDay;
  final int dayStartMinute;
  final int dayEndMinute;
  final int bufferMinutes;
  final int urgencyWindowDays;
  final List<WorkingWindowDraft> workingHours;
  final List<WorkingWindowDraft> breaks;

  /// The windows for [weekday] that are enabled. Uses 1 = Monday.
  List<ClockWindow> windowsFor(int weekday) => [
    for (final row in workingHours)
      if (row.weekday == weekday && row.enabled) row.window,
  ];

  List<ClockWindow> breaksFor(int weekday) => [
    for (final row in breaks)
      if (row.weekday == weekday) row.window,
  ];

  PlanningProfile copyWith({
    String? timezoneId,
    bool clearTimezone = false,
    int? defaultSlotMinutes,
    int? weekStartDay,
    int? dayStartMinute,
    int? dayEndMinute,
    int? bufferMinutes,
    int? urgencyWindowDays,
    List<WorkingWindowDraft>? workingHours,
    List<WorkingWindowDraft>? breaks,
  }) => PlanningProfile(
    id: id,
    timezoneId: clearTimezone ? null : (timezoneId ?? this.timezoneId),
    defaultSlotMinutes: defaultSlotMinutes ?? this.defaultSlotMinutes,
    weekStartDay: weekStartDay ?? this.weekStartDay,
    dayStartMinute: dayStartMinute ?? this.dayStartMinute,
    dayEndMinute: dayEndMinute ?? this.dayEndMinute,
    bufferMinutes: bufferMinutes ?? this.bufferMinutes,
    urgencyWindowDays: urgencyWindowDays ?? this.urgencyWindowDays,
    workingHours: workingHours ?? this.workingHours,
    breaks: breaks ?? this.breaks,
  );
}

final planningPreferencesRepositoryProvider =
    Provider<PlanningPreferencesRepository>((ref) {
      return PlanningPreferencesRepository(ref.watch(databaseProvider));
    });

final planningProfileProvider = StreamProvider<PlanningProfile>((ref) {
  return ref.watch(planningPreferencesRepositoryProvider).watchProfile();
});

/// Local planning preferences and working hours.
///
/// Defaults are returned in memory and only written when the user saves, so
/// merely opening the calendar never creates sync traffic. Every row has a
/// stable id, which keeps a first save on two offline devices convergent.
class PlanningPreferencesRepository {
  PlanningPreferencesRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const defaultProfileId = 'planning-profile-default';

  static const defaults = PlanningProfile(
    id: defaultProfileId,
    timezoneId: null,
    defaultSlotMinutes: 30,
    weekStartDay: 1,
    dayStartMinute: 9 * 60,
    dayEndMinute: 17 * 60,
    bufferMinutes: 10,
    urgencyWindowDays: 3,
    workingHours: [
      WorkingWindowDraft(
        id: 'working-hours-mon',
        weekday: 1,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      ),
      WorkingWindowDraft(
        id: 'working-hours-tue',
        weekday: 2,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      ),
      WorkingWindowDraft(
        id: 'working-hours-wed',
        weekday: 3,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      ),
      WorkingWindowDraft(
        id: 'working-hours-thu',
        weekday: 4,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      ),
      WorkingWindowDraft(
        id: 'working-hours-fri',
        weekday: 5,
        startMinute: 9 * 60,
        endMinute: 17 * 60,
      ),
    ],
    breaks: [],
  );

  Stream<PlanningProfile> watchProfile() {
    return _db
        .customSelect(
          'SELECT 1 AS tick',
          readsFrom: {
            _db.planningPreferences,
            _db.workingHours,
            _db.workingBreaks,
          },
        )
        .watch()
        .asyncMap((_) => loadProfile());
  }

  Future<PlanningProfile> loadProfile() async {
    final preference = await (_db.select(
      _db.planningPreferences,
    )..limit(1)).getSingleOrNull();
    final hours =
        await (_db.select(_db.workingHours)..orderBy([
              (t) => OrderingTerm.asc(t.weekday),
              (t) => OrderingTerm.asc(t.startMinute),
            ]))
            .get();
    final breaks =
        await (_db.select(_db.workingBreaks)..orderBy([
              (t) => OrderingTerm.asc(t.weekday),
              (t) => OrderingTerm.asc(t.startMinute),
            ]))
            .get();

    return PlanningProfile(
      id: preference?.id ?? defaultProfileId,
      timezoneId: preference?.timezoneId,
      defaultSlotMinutes: preference?.defaultSlotMinutes ?? 30,
      weekStartDay: preference?.weekStartDay ?? 1,
      dayStartMinute: preference?.dayStartMinute ?? 9 * 60,
      dayEndMinute: preference?.dayEndMinute ?? 17 * 60,
      bufferMinutes: preference?.bufferMinutes ?? 10,
      urgencyWindowDays: preference?.urgencyWindowDays ?? 3,
      workingHours: hours.isEmpty
          ? defaults.workingHours
          : [
              for (final row in hours)
                WorkingWindowDraft(
                  id: row.id,
                  weekday: row.weekday,
                  enabled: row.enabled,
                  startMinute: row.startMinute,
                  endMinute: row.endMinute,
                ),
            ],
      breaks: [
        for (final row in breaks)
          WorkingWindowDraft(
            id: row.id,
            weekday: row.weekday,
            startMinute: row.startMinute,
            endMinute: row.endMinute,
            label: row.label,
          ),
      ],
    );
  }

  Future<void> savePreferences({
    String? timezoneId,
    int defaultSlotMinutes = 30,
    int weekStartDay = 1,
    int dayStartMinute = 9 * 60,
    int dayEndMinute = 17 * 60,
    int bufferMinutes = 10,
    int? urgencyWindowDays,
  }) async {
    final now = AppClock.now();
    final existing = await (_db.select(
      _db.planningPreferences,
    )..limit(1)).getSingleOrNull();
    final nextUrgencyWindow =
        urgencyWindowDays ?? existing?.urgencyWindowDays ?? 3;
    _validatePreferences(
      defaultSlotMinutes: defaultSlotMinutes,
      weekStartDay: weekStartDay,
      dayStartMinute: dayStartMinute,
      dayEndMinute: dayEndMinute,
      bufferMinutes: bufferMinutes,
      urgencyWindowDays: nextUrgencyWindow,
    );
    await _db
        .into(_db.planningPreferences)
        .insertOnConflictUpdate(
          PlanningPreferencesCompanion.insert(
            id: existing?.id ?? defaultProfileId,
            timezoneId: Value(_normalizeTimezone(timezoneId)),
            defaultSlotMinutes: Value(defaultSlotMinutes),
            weekStartDay: Value(weekStartDay),
            dayStartMinute: Value(dayStartMinute),
            dayEndMinute: Value(dayEndMinute),
            bufferMinutes: Value(bufferMinutes),
            urgencyWindowDays: Value(nextUrgencyWindow),
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
  }

  /// Replaces the weekday intervals atomically. Rows with an empty id get a
  /// UUID; existing rows keep their id so sync treats them as edits.
  Future<void> replaceWorkingHours(List<WorkingWindowDraft> windows) async {
    for (final window in windows) {
      _validateWindow(window, label: 'working hours');
    }
    final now = AppClock.now();
    await _db.transaction(() async {
      await _db.delete(_db.workingHours).go();
      for (final window in windows) {
        await _db
            .into(_db.workingHours)
            .insert(
              WorkingHoursCompanion.insert(
                id: window.id.isEmpty ? _uuid.v4() : window.id,
                weekday: window.weekday,
                enabled: Value(window.enabled),
                startMinute: window.startMinute,
                endMinute: window.endMinute,
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  Future<void> replaceBreaks(List<WorkingWindowDraft> breaks) async {
    for (final window in breaks) {
      _validateWindow(window, label: 'breaks');
    }
    final now = AppClock.now();
    await _db.transaction(() async {
      await _db.delete(_db.workingBreaks).go();
      for (final window in breaks) {
        await _db
            .into(_db.workingBreaks)
            .insert(
              WorkingBreaksCompanion.insert(
                id: window.id.isEmpty ? _uuid.v4() : window.id,
                weekday: window.weekday,
                startMinute: window.startMinute,
                endMinute: window.endMinute,
                label: Value(window.label),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }
    });
  }

  /// Builds a capacity summary for [day] from the saved profile and the
  /// supplied blocks/events/My Day estimates.
  CapacitySummary capacityFor({
    required DateTime day,
    required PlanningProfile profile,
    List<BookedInterval> blocks = const [],
    List<({DateTime start, DateTime end})> busyEvents = const [],
    Map<String, int> plannedMinutesByTask = const {},
  }) {
    final weekday = day.weekday;
    return CapacityService.summarize(
      CapacityInput(
        day: DayMath.dateOnly(day),
        workingHours: profile.windowsFor(weekday),
        breaks: profile.breaksFor(weekday),
        busyEvents: busyEvents,
        blocks: blocks,
        plannedMinutesByTask: plannedMinutesByTask,
        bufferMinutes: profile.bufferMinutes,
      ),
    );
  }

  static void _validatePreferences({
    required int defaultSlotMinutes,
    required int weekStartDay,
    required int dayStartMinute,
    required int dayEndMinute,
    required int bufferMinutes,
    required int urgencyWindowDays,
  }) {
    if (defaultSlotMinutes < 5 || defaultSlotMinutes > 720) {
      throw ArgumentError('Default slot must be between 5 and 720 minutes.');
    }
    if (weekStartDay < 1 || weekStartDay > 7) {
      throw ArgumentError('Week start must be between Monday and Sunday.');
    }
    if (dayStartMinute < 0 || dayStartMinute > 1439) {
      throw ArgumentError('Day start is outside the day.');
    }
    if (dayEndMinute < 1 || dayEndMinute > 1440) {
      throw ArgumentError('Day end is outside the day.');
    }
    if (dayEndMinute <= dayStartMinute) {
      throw ArgumentError('Day end must be after day start.');
    }
    if (bufferMinutes < 0 || bufferMinutes > 240) {
      throw ArgumentError('Buffer must be between 0 and 240 minutes.');
    }
    if (urgencyWindowDays < 1 || urgencyWindowDays > 30) {
      throw ArgumentError('Urgency window must be between 1 and 30 days.');
    }
  }

  static void _validateWindow(
    WorkingWindowDraft window, {
    required String label,
  }) {
    if (window.weekday < 1 || window.weekday > 7) {
      throw ArgumentError('$label weekday must be 1-7.');
    }
    if (window.startMinute < 0 || window.startMinute > 1439) {
      throw ArgumentError('$label start is outside the day.');
    }
    if (window.endMinute < 1 || window.endMinute > 1440) {
      throw ArgumentError('$label end is outside the day.');
    }
    if (window.endMinute <= window.startMinute) {
      throw ArgumentError('$label end must be after start.');
    }
  }

  static String? _normalizeTimezone(String? timezoneId) {
    final trimmed = timezoneId?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
