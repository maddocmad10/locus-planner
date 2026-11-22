import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_agenda.dart';
import '../../../core/utils/day_math.dart';

final todayWidgetServiceProvider = Provider<TodayWidgetService>((ref) {
  return TodayWidgetService(ref.watch(databaseProvider));
});

/// Calls the Android widget channel. Tests inject a fake so the snapshot
/// contract can be verified without a phone.
typedef WidgetChannelInvoker =
    Future<Object?> Function(String method, Map<String, Object?>? arguments);

class _PublishResult {
  const _PublishResult({required this.ok, this.reason});

  final bool ok;
  final String? reason;
}

/// Writes the Android home-screen widget snapshot.
///
/// A snapshot is published as one atomic platform call carrying the title,
/// body, counts, generation, instant and the zone it was generated for. Native
/// code validates the day/zone and commits the whole snapshot in one
/// preferences edit; it never renders a partial update.
class TodayWidgetService {
  TodayWidgetService(
    this._db, {
    WidgetChannelInvoker? invoke,
    DateTime Function()? clock,
    bool? isAndroid,
  }) : _invoke = invoke ?? _channelInvoke,
       _clock = clock ?? AppClock.now,
       _isAndroid = isAndroid ?? Platform.isAndroid;

  static const androidProvider = 'TodayWidgetProvider';
  static const channelName = 'locus_planner/widget_snapshot';
  static const _channel = MethodChannel(channelName);
  static const _maxAttempts = 2;

  final AppDatabase _db;
  final WidgetChannelInvoker _invoke;
  final DateTime Function() _clock;
  final bool _isAndroid;

  int _generation = 0;
  bool _running = false;
  bool _queued = false;

  /// Publishes a snapshot. Overlapping calls coalesce into one extra run, so a
  /// burst of database changes cannot queue an unbounded series of refreshes.
  Future<void> update({DateTime? now}) async {
    if (!_isAndroid) return;
    _queued = true;
    if (_running) return;
    _running = true;
    try {
      while (_queued) {
        _queued = false;
        await _updateOnce(now: now);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _updateOnce({DateTime? now}) async {
    final generation = _nextGeneration();
    // A zone change deserves one immediate retry with a fresh instant. Any
    // other failure leaves the last complete snapshot in place for the next
    // normal refresh.
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        final clock = now ?? _clock();
        final zoneToken = await _zoneToken();
        if (zoneToken == null) {
          // No native bridge (or a non-widget host): keep the existing
          // snapshot rather than writing a partial one.
          return;
        }
        final snapshot = await _buildSnapshot(clock);
        final result = await _publish(
          snapshot: snapshot,
          generation: generation,
          expectedZoneToken: zoneToken,
        );
        if (result.ok) return;
        if (result.reason == 'zone_changed' && attempt + 1 < _maxAttempts) {
          continue;
        }
        debugPrint(
          'Today widget snapshot was not published: '
          '${result.reason ?? 'unknown'}',
        );
        return;
      } catch (error) {
        debugPrint('Today widget update failed: $error');
        return;
      }
    }
  }

  Future<String?> _zoneToken() async {
    try {
      final token = await _invoke('zoneToken', null);
      return token is String && token.isNotEmpty ? token : null;
    } catch (_) {
      return null;
    }
  }

  Future<_PublishResult> _publish({
    required _WidgetSnapshot snapshot,
    required int generation,
    required String expectedZoneToken,
  }) async {
    final value = await _invoke('publishSnapshot', {
      'title': snapshot.title,
      'body': snapshot.body,
      'eventCount': snapshot.eventCount,
      'taskCount': snapshot.taskCount,
      'habitCount': snapshot.habitCount,
      'generation': generation,
      'generatedAtMs': snapshot.generatedAt.toUtc().millisecondsSinceEpoch,
      'expectedZoneToken': expectedZoneToken,
      'day': snapshot.day,
    });
    if (value is bool) return _PublishResult(ok: value);
    if (value is Map) {
      final ok = value['ok'] == true;
      return _PublishResult(
        ok: ok,
        reason: value['reason'] is String ? value['reason'] as String : null,
      );
    }
    return const _PublishResult(ok: false, reason: 'invalid_response');
  }

  Future<_WidgetSnapshot> _buildSnapshot(DateTime clock) async {
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

    return _WidgetSnapshot(
      title: DateFormat('EEE d MMM').format(day),
      body: lines.join('\n'),
      eventCount: events.length,
      taskCount: dueTasks,
      habitCount: remainingHabits,
      generatedAt: clock,
      day: _dayKey(day),
    );
  }

  /// Generation is a timestamp-like monotonic token, so a process restart
  /// cannot accidentally publish a lower generation than the last commit.
  int _nextGeneration() {
    final candidate = _clock().microsecondsSinceEpoch;
    _generation = candidate > _generation ? candidate : _generation + 1;
    return _generation;
  }

  static String _dayKey(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '$year-$month-$date';
  }

  static Future<Object?> _channelInvoke(
    String method,
    Map<String, Object?>? arguments,
  ) {
    return _channel.invokeMethod<Object?>(method, arguments);
  }
}

class _WidgetSnapshot {
  const _WidgetSnapshot({
    required this.title,
    required this.body,
    required this.eventCount,
    required this.taskCount,
    required this.habitCount,
    required this.generatedAt,
    required this.day,
  });

  final String title;
  final String body;
  final int eventCount;
  final int taskCount;
  final int habitCount;
  final DateTime generatedAt;
  final String day;
}
