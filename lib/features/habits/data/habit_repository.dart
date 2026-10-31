import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/app_clock.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
    clock: ref.watch(clockProvider),
  );
});

final habitsStreamProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
});

final habitLogsLast84DaysProvider = StreamProvider.autoDispose<List<HabitLog>>((
  ref,
) {
  // Derive the window from the injected clock and rebuild when the calendar
  // day changes, so a tray-resident app never serves yesterday's range.
  final clock = ref.watch(clockProvider);
  ref.watch(dayChangeProvider);

  final db = ref.watch(databaseProvider);
  final today = DayMath.dateOnly(clock());
  return db.watchHabitLogsForRange(
    DayMath.addDays(today, -83),
    DayMath.addDays(today, 1),
  );
});

/// Logs for one calendar day. The phone's upcoming-day browser uses it to
/// show the same toggle state the desktop shows, including days synced from a
/// desktop in another time zone (both sides store calendar midnights).
final habitLogsForDayProvider = StreamProvider.autoDispose
    .family<List<HabitLog>, DateTime>((ref, day) {
      final date = DayMath.dateOnly(day);
      return ref
          .watch(databaseProvider)
          .watchHabitLogsForRange(date, DayMath.addDays(date, 1));
    });

/// The true streak across the whole history. The 84-day window above only
/// feeds the heatmap; a streak older than 12 weeks must still count.
final habitStreakProvider = FutureProvider.autoDispose.family<int, String>(
  (ref, habitId) => ref.watch(habitRepositoryProvider).streak(habitId),
);

class HabitRepository {
  HabitRepository(this._db, this._undo, {DateTime Function()? clock})
    : _now = clock ?? AppClock.now;
  final AppDatabase _db;
  final UndoService _undo;
  final DateTime Function() _now;
  final _uuid = const Uuid();

  Stream<List<Habit>> watchAll() => _db.watchHabits();

  Future<void> create({
    required String name,
    String icon = '🔥',
    int targetPerWeek = 5,
  }) async {
    if (targetPerWeek < 1 || targetPerWeek > 7) {
      throw ArgumentError.value(
        targetPerWeek,
        'targetPerWeek',
        'must be between 1 and 7',
      );
    }
    await _db
        .into(_db.habits)
        .insert(
          HabitsCompanion(
            id: Value(_uuid.v4()),
            name: Value(name),
            icon: Value(icon),
            createdAt: Value(_now()),
            targetPerWeek: Value(targetPerWeek),
          ),
        );
  }

  Future<void> update(Habit habit) => _db.update(_db.habits).replace(habit);

  Future<void> delete(String id) async {
    final habit = await (_db.select(
      _db.habits,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (habit == null) return;
    final logs = await (_db.select(
      _db.habitLogs,
    )..where((t) => t.habitId.equals(id))).get();

    await _db.deleteHabit(id);
    _undo.offer(
      label: 'habit',
      restore: () async {
        await _db.transaction(() async {
          await _db.into(_db.habits).insert(habit);
          for (final log in logs) {
            await _db.into(_db.habitLogs).insert(log);
          }
        });
      },
    );
  }

  Future<bool> isDoneToday(String habitId) => isDoneOn(habitId, _now());

  /// Whether the habit is marked complete on [day].
  Future<bool> isDoneOn(String habitId, DateTime day) async {
    final date = DayMath.dateOnly(day);
    final logs = await (_db.select(
      _db.habitLogs,
    )..where((t) => t.habitId.equals(habitId) & t.date.equals(date))).get();
    return logs.any((log) => log.completed);
  }

  Future<void> toggleToday(Habit habit, bool currentlyCompleted) =>
      toggleDay(habit, _now(), currentlyCompleted);

  /// Toggles the habit on any day, not just today. This is what lets the phone
  /// fill in a habit for an upcoming day while browsing the week.
  Future<void> toggleDay(
    Habit habit,
    DateTime day,
    bool currentlyCompleted,
  ) async {
    final date = DayMath.dateOnly(day);

    if (currentlyCompleted) {
      await (_db.delete(
        _db.habitLogs,
      )..where((t) => t.habitId.equals(habit.id) & t.date.equals(date))).go();
      return;
    }

    await _db
        .into(_db.habitLogs)
        .insert(
          HabitLogsCompanion(
            id: Value(_uuid.v4()),
            habitId: Value(habit.id),
            date: Value(date),
            completed: const Value(true),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<int> streak(String habitId) => _db.habitStreak(habitId, now: _now());
}
