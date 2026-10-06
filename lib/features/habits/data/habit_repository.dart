import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/undo_service.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(
    ref.watch(databaseProvider),
    ref.watch(undoServiceProvider),
  );
});

final habitsStreamProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
});

final habitLogsLast84DaysProvider = StreamProvider<List<HabitLog>>((ref) {
  final db = ref.watch(databaseProvider);
  final today = DateTime.now();
  final start = DateTime(today.year, today.month, today.day).subtract(
    const Duration(days: 83),
  );
  final end = DateTime(today.year, today.month, today.day).add(
    const Duration(days: 1),
  );
  return db.watchHabitLogsForRange(start, end);
});


class HabitRepository {
  HabitRepository(this._db, this._undo);
  final AppDatabase _db;
  final UndoService _undo;
  final _uuid = const Uuid();

  Stream<List<Habit>> watchAll() => _db.watchHabits();

  Future<void> create({
    required String name,
    String icon = '🔥',
    int targetPerWeek = 5,
  }) async {
    if (targetPerWeek < 1 || targetPerWeek > 7) {
      throw ArgumentError.value(targetPerWeek, 'targetPerWeek', 'must be between 1 and 7');
    }
    await _db
        .into(_db.habits)
        .insert(
          HabitsCompanion(
            id: Value(_uuid.v4()),
            name: Value(name),
            icon: Value(icon),
            createdAt: Value(DateTime.now()),
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

  Future<bool> isDoneToday(String habitId) async {
    final logs = await _db.logsForHabitToday(habitId);
    return logs.any((log) => log.completed);
  }

  Future<void> toggleToday(Habit habit, bool currentlyCompleted) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    if (currentlyCompleted) {
      await (_db.delete(_db.habitLogs)
            ..where((t) => t.habitId.equals(habit.id) & t.date.equals(today)))
          .go();
      return;
    }

    await _db.into(_db.habitLogs).insert(
      HabitLogsCompanion(
        id: Value(_uuid.v4()),
        habitId: Value(habit.id),
        date: Value(today),
        completed: const Value(true),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<int> weekProgress(String habitId) => _db.habitWeekProgress(habitId);
  Future<int> streak(String habitId) => _db.habitStreak(habitId);
}
