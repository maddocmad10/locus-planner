import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_agenda.dart';
import '../../../core/utils/day_math.dart';

final todayWidgetServiceProvider = Provider<TodayWidgetService>((ref) {
  return TodayWidgetService(ref.watch(databaseProvider));
});

/// Writes the Android home-screen widget snapshot.
///
/// The widget reads only a short text summary; the full planner stays in the
/// local database. There is no network access here.
class TodayWidgetService {
  TodayWidgetService(this._db);

  static const androidProvider = 'TodayWidgetProvider';

  final AppDatabase _db;

  Future<void> update({DateTime? now}) async {
    if (!Platform.isAndroid) return;
    try {
      final clock = now ?? AppClock.now();
      final day = DayMath.dateOnly(clock);

      final allEvents = await _db.select(_db.events).get();
      final events = agendaForDay(allEvents, day);
      final tasks = await _db.select(_db.todoItems).get();
      final habits = await _db.select(_db.habits).get();
      final logs = await _db.select(_db.habitLogs).get();

      final lines = <String>[];
      for (final entry in events.take(3)) {
        final title = entry.event.title;
        lines.add(
          entry.event.allDay
              ? '• $title'
              : '• ${DateFormat('HH:mm').format(entry.start)} $title',
        );
      }
      if (events.length > 3) {
        lines.add('+${events.length - 3} more event(s)');
      }

      final dueTasks = tasks.where((task) {
        final due = task.dueDate;
        return !task.completed &&
            due != null &&
            DayMath.calendarDaysBetween(day, due) == 0;
      }).length;
      if (dueTasks > 0) {
        lines.add('$dueTasks task${dueTasks == 1 ? '' : 's'} due today');
      }

      final completedHabits = <String>{
        for (final log in logs)
          if (log.completed && DayMath.calendarDaysBetween(day, log.date) == 0)
            log.habitId,
      };
      final remainingHabits = habits
          .where((habit) => !completedHabits.contains(habit.id))
          .length;
      if (remainingHabits > 0) {
        lines.add(
          '$remainingHabits habit${remainingHabits == 1 ? '' : 's'} today',
        );
      }

      if (lines.isEmpty) {
        lines.add('Nothing scheduled today.');
      }

      await HomeWidget.saveWidgetData<String>(
        'today_title',
        DateFormat('EEE d MMM').format(day),
      );
      await HomeWidget.saveWidgetData<String>('today_body', lines.join('\n'));
      await HomeWidget.updateWidget(androidName: androidProvider);
    } catch (error) {
      // A widget is a convenience; never let its failure affect the planner.
      debugPrint('Today widget update failed: $error');
    }
  }
}
