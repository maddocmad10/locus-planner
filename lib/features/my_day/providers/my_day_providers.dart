import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../data/my_day_models.dart';
import '../data/my_day_repository.dart';

/// The currently viewed day. It is deliberately separate from the system clock
/// so browsing tomorrow never changes what "today" means elsewhere.
class MyDaySelectedDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DayMath.dateOnly(AppClock.now());

  void select(DateTime day) => state = DayMath.dateOnly(day);

  void shift(int days) => state = DayMath.addDays(state, days);

  void goToToday() => state = DayMath.dateOnly(AppClock.now());
}

final myDaySelectedDayProvider =
    NotifierProvider<MyDaySelectedDayNotifier, DateTime>(
      MyDaySelectedDayNotifier.new,
    );

/// A thin action layer over [MyDayRepository]. Widgets call these methods
/// instead of reaching for the database, which keeps every planning write in
/// one place and makes the write paths easy to test.
class MyDayController {
  MyDayController(this._repository);

  final MyDayRepository _repository;

  Future<void> setIntention(DateTime day, String intention) =>
      _repository.setIntention(day: day, intention: intention);

  Future<void> addTask(
    DateTime day,
    PlannableTaskView task, {
    int? plannedMinutes,
  }) {
    return task.source == PlannedTaskSource.todo
        ? _repository.addTodo(
            day: day,
            todoId: task.taskId,
            plannedMinutes: plannedMinutes,
          )
        : _repository.addProjectTask(
            day: day,
            taskId: task.taskId,
            plannedMinutes: plannedMinutes,
          );
  }

  Future<void> addSuggested(DateTime day, SuggestedTaskView task) {
    return task.source == PlannedTaskSource.todo
        ? _repository.addTodo(day: day, todoId: task.taskId)
        : _repository.addProjectTask(day: day, taskId: task.taskId);
  }

  Future<void> removeItem(PlannedTaskView item) =>
      _repository.removeItem(item.planItemId);

  Future<void> moveToDay(PlannedTaskView item, DateTime day) =>
      _repository.moveItem(itemId: item.planItemId, targetDay: day);

  Future<void> moveToTomorrow(DateTime day, PlannedTaskView item) => _repository
      .moveItem(itemId: item.planItemId, targetDay: DayMath.addDays(day, 1));

  Future<void> reorder(List<PlannedTaskView> items) =>
      _repository.reorderItems([for (final item in items) item.planItemId]);

  Future<void> updateEstimate(PlannedTaskView item, int? minutes) => _repository
      .updateEstimate(itemId: item.planItemId, plannedMinutes: minutes);

  Future<void> setCompleted(PlannedTaskView item, bool completed) =>
      _repository.setCompleted(item, completed);

  Future<List<PlannableTaskView>> plannableTasks(DateTime day) =>
      _repository.plannableTasks(day);

  /// Creates a plain to-do and plans it on [day] in one user action.
  Future<void> createTodoForDay(DateTime day, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final id = await _repository.createTodo(trimmed);
    await _repository.addTodo(day: day, todoId: id);
  }
}

final myDayControllerProvider = Provider<MyDayController>((ref) {
  return MyDayController(ref.watch(myDayRepositoryProvider));
});

/// The plan for any day, keyed by the normalized date. The Windows page and
/// the Android Today tab both watch this, so both platforms share one query.
final myDayDayViewProvider = StreamProvider.autoDispose
    .family<DailyPlanView, DateTime>((ref, day) {
      return ref.watch(myDayRepositoryProvider).watchDay(day);
    });
