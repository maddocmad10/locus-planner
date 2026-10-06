import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/undo_service.dart';

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return HabitRepository(ref.watch(databaseProvider));
});

final habitsStreamProvider = StreamProvider<List<Habit>>((ref) {
  return ref.watch(habitRepositoryProvider).watchAll();
});

class HabitStats {
  const HabitStats({
    required this.doneToday,
    required this.weekProgress,
    required this.streak,
    required this.targetPerWeek,
  });

  final bool doneToday;
  final int weekProgress;
  final int streak;
  final int targetPerWeek;
}

final habitStatsProvider = FutureProvider.family<HabitStats, String>((
  ref,
  habitId,
) async {
  final repo = ref.watch(habitRepositoryProvider);
  final db = ref.watch(databaseProvider);
  final habit = await (db.select(
    db.habits,
  )..where((t) => t.id.equals(habitId))).getSingleOrNull();

  return HabitStats(
    doneToday: await repo.isDoneToday(habitId),
    weekProgress: await repo.weekProgress(habitId),
    streak: await repo.streak(habitId),
    targetPerWeek: habit?.targetPerWeek ?? 5,
  );
});

class HabitRepository {
  HabitRepository(this._db);
  final AppDatabase _db;
  final _uuid = const Uuid();

  Stream<List<Habit>> watchAll() => _db.watchHabits();

  Future<void> create({
    required String name,
    String icon = '🔥',
    int targetPerWeek = 5,
  }) async {
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

  Future<void> delete(String id) async {
    final habit = await (_db.select(
      _db.habits,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (habit == null) return;
    final logs = await (_db.select(
      _db.habitLogs,
    )..where((t) => t.habitId.equals(id))).get();

    await _db.deleteHabit(id);
    UndoService.instance.offer(
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

  Future<void> toggleToday(Habit habit, bool isDone) async {
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    if (isDone) {
      await (_db.delete(
        _db.habitLogs,
      )..where((t) => t.habitId.equals(habit.id) & t.date.equals(today))).go();
    } else {
      await _db
          .into(_db.habitLogs)
          .insert(
            HabitLogsCompanion(
              id: Value(_uuid.v4()),
              habitId: Value(habit.id),
              date: Value(today),
              completed: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  Future<int> weekProgress(String habitId) => _db.habitWeekProgress(habitId);
  Future<int> streak(String habitId) => _db.habitStreak(habitId);
}
