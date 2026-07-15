import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/db/app_database.dart';
import '../../core/providers/database_provider.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(ref.watch(databaseProvider));
});

class HabitRepository {
  HabitRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Habit>> watchAll() => _db.watchHabits();

  Future<void> create({required String name, String icon = '🔥', int targetPerWeek = 5}) async {
    await _db.into(_db.habits).insert(HabitsCompanion(
          id: Value(_uuid.v4()),
          name: Value(name),
          icon: Value(icon),
          createdAt: Value(DateTime.now()),
          targetPerWeek: Value(targetPerWeek),
        ));
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.habits)..where((t) => t.id.equals(id))).go();
  }

  Future<bool> isDoneToday(String habitId) async {
    final logs = await _db.logsForHabitToday(habitId);
    return logs.isNotEmpty;
  }

  Future<void> toggleToday(Habit habit, bool isDone) async {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (isDone) {
      await (_db.delete(_db.habitLogs)
            ..where((t) => t.habitId.equals(habit.id) & t.date.equals(today)))
          .go();
    } else {
      await _db.into(_db.habitLogs).insert(HabitLogsCompanion(
            id: Value(_uuid.v4()),
            habitId: Value(habit.id),
            date: Value(today),
            completed: const Value(true),
          ));
    }
  }

  Future<int> weekProgress(String habitId) => _db.habitWeekProgress(habitId);
  Future<int> streak(String habitId) => _db.habitStreak(habitId);
}
