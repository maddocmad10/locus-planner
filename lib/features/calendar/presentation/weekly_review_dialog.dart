import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../data/planning_preferences_repository.dart';

/// Weekly planning review. Metrics are derived from tasks; only the user's
/// notes and the completion marker are stored, under a private app-setting
/// key that is included in backups like any other user preference.
class WeeklyReviewDialog extends ConsumerStatefulWidget {
  const WeeklyReviewDialog({
    super.key,
    required this.todos,
    required this.profile,
  });

  final List<TodoItem> todos;
  final PlanningProfile profile;

  static Future<void> show(
    BuildContext context, {
    required List<TodoItem> todos,
    required PlanningProfile profile,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => WeeklyReviewDialog(todos: todos, profile: profile),
    );
  }

  @override
  ConsumerState<WeeklyReviewDialog> createState() => _WeeklyReviewDialogState();
}

class _WeeklyReviewDialogState extends ConsumerState<WeeklyReviewDialog> {
  final _wins = TextEditingController();
  final _unfinished = TextEditingController();
  final _priorities = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _wins.dispose();
    _unfinished.dispose();
    _priorities.dispose();
    super.dispose();
  }

  String get _settingKey {
    final week = DayMath.startOfWeek(AppClock.now());
    return 'weekly_review_${week.year}-${week.month}-${week.day}';
  }

  Future<void> _load() async {
    final raw = await ref.read(databaseProvider).getSetting(_settingKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _wins.text = decoded['wins'] as String? ?? '';
          _unfinished.text = decoded['unfinished'] as String? ?? '';
          _priorities.text = decoded['priorities'] as String? ?? '';
        }
      } catch (_) {
        // A corrupt note must not block the review dialog.
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .setSetting(
          _settingKey,
          jsonEncode({
            'wins': _wins.text.trim(),
            'unfinished': _unfinished.text.trim(),
            'priorities': _priorities.text.trim(),
            'completedAt': AppClock.now().toIso8601String(),
          }),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DayMath.dateOnly(AppClock.now());
    final thisWeekStart = DayMath.startOfWeek(now);
    final thisWeekEnd = DayMath.addDays(thisWeekStart, 7);
    final nextWeekStart = thisWeekEnd;
    final nextWeekEnd = DayMath.addDays(nextWeekStart, 7);

    final dueThisWeek = widget.todos
        .where(
          (task) =>
              task.dueDate != null &&
              !task.dueDate!.isBefore(thisWeekStart) &&
              task.dueDate!.isBefore(thisWeekEnd),
        )
        .toList();
    final completedThisWeek = dueThisWeek
        .where((task) => task.completed)
        .length;
    final overdue = widget.todos
        .where(
          (task) =>
              !task.completed &&
              task.dueDate != null &&
              task.dueDate!.isBefore(now),
        )
        .length;
    final nextWeek = widget.todos
        .where(
          (task) =>
              !task.completed &&
              task.dueDate != null &&
              !task.dueDate!.isBefore(nextWeekStart) &&
              task.dueDate!.isBefore(nextWeekEnd),
        )
        .length;

    var nextWeekCapacity = 0;
    for (var offset = 0; offset < 7; offset++) {
      final day = DayMath.addDays(nextWeekStart, offset);
      final working = widget.profile
          .windowsFor(day.weekday)
          .fold<int>(0, (sum, window) => sum + window.minutes);
      final breaks = widget.profile
          .breaksFor(day.weekday)
          .fold<int>(0, (sum, window) => sum + window.minutes);
      nextWeekCapacity += (working - breaks).clamp(0, 24 * 60);
    }

    final range = DateFormat('d MMM').format(thisWeekStart);
    final rangeEnd = DateFormat(
      'd MMM',
    ).format(DayMath.addDays(thisWeekEnd, -1));
    return AlertDialog(
      title: const Text('Weekly review'),
      content: SizedBox(
        width: 560,
        height: 520,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Week $range – $rangeEnd',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _Metric(
                          label: 'Completed this week',
                          value: '$completedThisWeek/${dueThisWeek.length}',
                        ),
                        _Metric(label: 'Overdue carryover', value: '$overdue'),
                        _Metric(label: 'Due next week', value: '$nextWeek'),
                        _Metric(
                          label: 'Next week capacity',
                          value:
                              '${nextWeekCapacity ~/ 60}h '
                              '${nextWeekCapacity % 60}m',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _wins,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Wins',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _unfinished,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Unfinished work',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priorities,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Priorities for next week',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Nothing is rescheduled automatically. Move or plan each '
                      'task yourself; every calendar move remains undoable.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: const Text('Save review'),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
