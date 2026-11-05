import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/planning/capacity_service.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/navigation_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../events/data/event_repository.dart';
import '../../tasks/data/task_repository.dart';
import '../data/calendar_projection.dart';
import '../data/planning_preferences_repository.dart';
import '../data/saved_filter_repository.dart';
import '../data/schedule_block_repository.dart';
import 'block_editor_dialog.dart';
import 'saved_view_dialog.dart';
import 'weekly_review_dialog.dart';
import 'working_hours_dialog.dart';

enum _CalendarView { month, week, day, agenda }

const _hourHeight = 52.0;
const _gutterWidth = 56.0;
const _allDayHeight = 34.0;

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  _CalendarView _view = _CalendarView.week;
  final _weekScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DayMath.dateOnly(ref.read(clockProvider)());
    _focusedDay = now;
    _selectedDay = now;
  }

  @override
  void dispose() {
    _weekScroll.dispose();
    super.dispose();
  }

  ({DateTime from, DateTime to}) get _range {
    switch (_view) {
      case _CalendarView.day:
        return (from: _selectedDay, to: _selectedDay);
      case _CalendarView.month:
        final first = DateTime(_focusedDay.year, _focusedDay.month, 1);
        final gridStart = DayMath.addDays(first, -(first.weekday - 1));
        return (from: gridStart, to: DayMath.addDays(gridStart, 41));
      case _CalendarView.week:
      case _CalendarView.agenda:
        final start = DayMath.startOfWeek(_focusedDay);
        return (from: start, to: DayMath.addDays(start, 6));
    }
  }

  void _moveFocus(int days) {
    setState(() {
      _focusedDay = _view == _CalendarView.month
          ? DateTime(_focusedDay.year, _focusedDay.month + days)
          : DayMath.addDays(_focusedDay, days);
      _selectedDay = _focusedDay;
    });
  }

  void _goToday() {
    final now = DayMath.dateOnly(ref.read(clockProvider)());
    setState(() {
      _focusedDay = now;
      _selectedDay = now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile =
        ref.watch(planningProfileProvider).valueOrNull ??
        PlanningPreferencesRepository.defaults;
    final events = ref.watch(allEventsProvider).valueOrNull ?? const <Event>[];
    final range = _range;
    final blocks =
        ref.watch(scheduleBlocksForRangeProvider(range)).valueOrNull ??
        const <TaskScheduleBlock>[];
    final titles =
        ref.watch(calendarTaskTitlesProvider).valueOrNull ??
        const <String, String>{};
    final plannable =
        ref.watch(unscheduledCalendarTasksProvider(range)).valueOrNull ??
        const <PlannableCalendarTask>[];

    final entries = buildCalendarEntries(
      events: events,
      blocks: blocks,
      from: range.from,
      to: range.to,
      titleForBlock: (block) {
        if (block.todoItemId != null) {
          return titles['todo:${block.todoItemId}'] ?? 'Task';
        }
        return titles['task:${block.projectTaskId}'] ?? 'Project task';
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(profile),
                    const SizedBox(height: 8),
                    Expanded(child: _buildBody(entries, profile)),
                  ],
                ),
              ),
            ),
            if (wide)
              SizedBox(
                width: 300,
                child: _CalendarSidePanel(
                  profile: profile,
                  entries: entries,
                  selectedDay: _selectedDay,
                  plannable: plannable,
                  onScheduleAtDefault: (task) =>
                      _scheduleAtDefault(task, profile),
                  onOpenEntry: _openEntry,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(PlanningProfile profile) {
    final title = switch (_view) {
      _CalendarView.month => DateFormat('MMMM yyyy').format(_focusedDay),
      _CalendarView.day => dayHeading(_selectedDay),
      _CalendarView.week => _weekTitle(),
      _CalendarView.agenda => 'Agenda · ${_weekTitle()}',
    };
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _moveFocus(-1),
            ),
            TextButton(onPressed: _goToday, child: const Text('Today')),
            IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _moveFocus(1),
            ),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<_CalendarView>(
              showSelectedIcon: false,
              selected: {_view},
              segments: const [
                ButtonSegment(value: _CalendarView.month, label: Text('Month')),
                ButtonSegment(value: _CalendarView.week, label: Text('Week')),
                ButtonSegment(value: _CalendarView.day, label: Text('Day')),
                ButtonSegment(
                  value: _CalendarView.agenda,
                  label: Text('Agenda'),
                ),
              ],
              onSelectionChanged: (selection) {
                setState(() => _view = selection.first);
              },
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Working hours & planning',
              icon: const Icon(Icons.schedule_outlined),
              onPressed: () => WorkingHoursDialog.show(context, profile),
            ),
            IconButton(
              tooltip: 'Weekly review',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => _openWeeklyReview(profile),
            ),
          ],
        ),
      ],
    );
  }

  String _weekTitle() {
    final start = DayMath.startOfWeek(_focusedDay);
    final end = DayMath.addDays(start, 6);
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${DateFormat('MMM yyyy').format(end)}';
    }
    return '${DateFormat('d MMM').format(start)} – '
        '${DateFormat('d MMM yyyy').format(end)}';
  }

  Widget _buildBody(List<CalendarEntry> entries, PlanningProfile profile) {
    switch (_view) {
      case _CalendarView.month:
        return _MonthView(
          focusedDay: _focusedDay,
          selectedDay: _selectedDay,
          entries: entries,
          onSelectDay: (day) {
            setState(() {
              _selectedDay = day;
              _focusedDay = day;
              _view = _CalendarView.day;
            });
          },
        );
      case _CalendarView.week:
        return _WeekView(
          range: _range,
          entries: entries,
          profile: profile,
          scrollController: _weekScroll,
          onOpenEntry: _openEntry,
          onDropTask: _dropTask,
          onDropBlock: _dropBlock,
          onNudgeBlock: _nudgeBlock,
          onDeleteBlock: _deleteBlock,
          onSelectDay: (day) => setState(() => _selectedDay = day),
        );
      case _CalendarView.day:
        return _DayView(
          day: _selectedDay,
          entries: entriesForDay(entries, _selectedDay),
          profile: profile,
          scrollController: _weekScroll,
          onOpenEntry: _openEntry,
          onDropTask: _dropTask,
          onDropBlock: _dropBlock,
          onNudgeBlock: _nudgeBlock,
          onDeleteBlock: _deleteBlock,
        );
      case _CalendarView.agenda:
        return _AgendaView(
          range: _range,
          entries: entries,
          onOpenEntry: _openEntry,
          onSelectDay: (day) => setState(() {
            _selectedDay = day;
            _view = _CalendarView.day;
          }),
        );
    }
  }

  Future<void> _dropTask(
    PlannableCalendarTask task,
    DateTime day,
    int minute, {
    PlanningProfile? profile,
  }) async {
    final settings =
        profile ??
        ref.read(planningProfileProvider).valueOrNull ??
        PlanningPreferencesRepository.defaults;
    final start = _atMinute(day, minute);
    final requested = task.estimatedMinutes ?? settings.defaultSlotMinutes;
    final duration = requested.clamp(15, 480);
    final end = start.add(Duration(minutes: duration));
    try {
      final block = await ref
          .read(scheduleBlockRepositoryProvider)
          .createBlock(
            todoItemId: task.source == 'todo' ? _idOf(task.key) : null,
            projectTaskId: task.source == 'task' ? _idOf(task.key) : null,
            startAt: start,
            endAt: end,
          );
      if (!mounted) return;
      UndoSnackbar.show(
        context,
        message: 'Scheduled “${task.title}”',
        service: ref.read(undoServiceProvider),
      );
      await BlockEditorDialog.show(context, block: block, title: task.title);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _scheduleAtDefault(
    PlannableCalendarTask task,
    PlanningProfile profile,
  ) async {
    final startMinute = profile.dayStartMinute.clamp(0, 23 * 60 + 45);
    await _dropTask(task, _selectedDay, startMinute, profile: profile);
  }

  Future<void> _dropBlock(
    TaskScheduleBlock block,
    DateTime day,
    int minute,
  ) async {
    try {
      await ref
          .read(scheduleBlockRepositoryProvider)
          .moveBlock(block: block, newStart: _atMinute(day, minute));
      if (mounted) {
        UndoSnackbar.show(
          context,
          message: 'Moved time block',
          service: ref.read(undoServiceProvider),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _nudgeBlock(
    TaskScheduleBlock block,
    int minutes, {
    required bool resize,
  }) async {
    final repository = ref.read(scheduleBlockRepositoryProvider);
    try {
      if (resize) {
        await repository.resizeBlock(
          block: block,
          newEnd: block.endAt.add(Duration(minutes: minutes)),
        );
      } else {
        await repository.moveBlock(
          block: block,
          newStart: block.startAt.add(Duration(minutes: minutes)),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _deleteBlock(TaskScheduleBlock block) async {
    try {
      await ref.read(scheduleBlockRepositoryProvider).deleteBlock(block);
      if (mounted) {
        UndoSnackbar.show(
          context,
          message: 'Deleted time block',
          service: ref.read(undoServiceProvider),
        );
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update the calendar: $error')),
    );
  }

  Future<void> _openEntry(CalendarEntry entry) async {
    final block = entry.block;
    if (block != null) {
      await BlockEditorDialog.show(context, block: block, title: entry.title);
      return;
    }
    final event = entry.event;
    if (event == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(event.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry.allDay
                  ? 'All day · ${DateFormat('d MMM yyyy').format(entry.start)}'
                  : '${DateFormat('EEE d MMM, HH:mm').format(entry.start)}'
                        ' – ${DateFormat('HH:mm').format(entry.end)}',
            ),
            if (entry.isRecurring) ...[
              const SizedBox(height: 8),
              const Text('Part of a repeating series.'),
            ],
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(event.description!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(navigationIndexProvider.notifier)
                  .setIndex(NavPage.events);
            },
            child: const Text('Open Events'),
          ),
        ],
      ),
    );
  }

  Future<void> _openWeeklyReview(PlanningProfile profile) async {
    final todos =
        ref.read(tasksStreamProvider).valueOrNull ??
        await ref.read(taskRepositoryProvider).watchAll().first;
    if (!mounted) return;
    await WeeklyReviewDialog.show(context, todos: todos, profile: profile);
  }

  static DateTime _atMinute(DateTime day, int minute) {
    final clamped = minute.clamp(0, 24 * 60 - 15);
    return DateTime(day.year, day.month, day.day, clamped ~/ 60, clamped % 60);
  }

  static String _idOf(String key) {
    final separator = key.indexOf(':');
    return separator == -1 ? key : key.substring(separator + 1);
  }
}

// ==================== MONTH ====================

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.focusedDay,
    required this.selectedDay,
    required this.entries,
    required this.onSelectDay,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final List<CalendarEntry> entries;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(focusedDay.year, focusedDay.month, 1);
    final gridStart = DayMath.addDays(first, -(first.weekday - 1));
    return Column(
      children: [
        Row(
          children: [
            for (var weekday = 1; weekday <= 7; weekday++)
              Expanded(
                child: Center(
                  child: Text(
                    DateFormat('EEE').format(DateTime(2026, 1, 4 + weekday)),
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellWidth = constraints.maxWidth / 7;
              final cellHeight = constraints.maxHeight / 6;
              return GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 42,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: cellHeight == 0
                      ? 1
                      : cellWidth / cellHeight,
                ),
                itemBuilder: (context, index) {
                  final day = DayMath.addDays(gridStart, index);
                  final dayEntries = entriesForDay(entries, day);
                  return _MonthCell(
                    day: day,
                    inMonth: day.month == focusedDay.month,
                    selected:
                        DayMath.dateOnly(day) == DayMath.dateOnly(selectedDay),
                    entries: dayEntries,
                    onTap: () => onSelectDay(day),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.entries,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final List<CalendarEntry> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conflicts = conflictingEntryKeys(entries);
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
              : null,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: inMonth
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                fontWeight: selected ? FontWeight.w700 : null,
              ),
            ),
            const SizedBox(height: 2),
            for (final entry in entries.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: 1),
                child: Text(
                  '${entry.allDay ? '·' : DateFormat('HH:mm').format(entry.start)} '
                  '${entry.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: conflicts.contains(entry.key)
                        ? theme.colorScheme.error
                        : entry.kind == CalendarEntryKind.block
                        ? theme.colorScheme.primary
                        : theme.colorScheme.tertiary,
                  ),
                ),
              ),
            if (entries.length > 3)
              Text(
                '+${entries.length - 3} more',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================== WEEK / DAY ====================

class _WeekView extends StatefulWidget {
  const _WeekView({
    required this.range,
    required this.entries,
    required this.profile,
    required this.scrollController,
    required this.onOpenEntry,
    required this.onDropTask,
    required this.onDropBlock,
    required this.onNudgeBlock,
    required this.onDeleteBlock,
    required this.onSelectDay,
  });

  final ({DateTime from, DateTime to}) range;
  final List<CalendarEntry> entries;
  final PlanningProfile profile;
  final ScrollController scrollController;
  final Future<void> Function(CalendarEntry entry) onOpenEntry;
  final Future<void> Function(
    PlannableCalendarTask task,
    DateTime day,
    int minute,
  )
  onDropTask;
  final Future<void> Function(TaskScheduleBlock block, DateTime day, int minute)
  onDropBlock;
  final Future<void> Function(
    TaskScheduleBlock block,
    int minutes, {
    required bool resize,
  })
  onNudgeBlock;
  final Future<void> Function(TaskScheduleBlock block) onDeleteBlock;
  final ValueChanged<DateTime> onSelectDay;

  @override
  State<_WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<_WeekView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.scrollController.hasClients) return;
      widget.scrollController.jumpTo(
        (widget.profile.dayStartMinute / 60 * _hourHeight - 8).clamp(
          0,
          _hourHeight * 24,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = [
      for (var offset = 0; offset < 7; offset++)
        DayMath.addDays(widget.range.from, offset),
    ];
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: _gutterWidth),
            for (final day in days)
              Expanded(
                child: InkWell(
                  onTap: () => widget.onSelectDay(day),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('EEE').format(day),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        Text(
                          '${day.day}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight:
                                    DayMath.dateOnly(day) ==
                                        DayMath.dateOnly(widget.range.from)
                                    ? FontWeight.w700
                                    : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(
          height: _allDayHeight,
          child: Row(
            children: [
              const SizedBox(width: _gutterWidth),
              for (final day in days)
                Expanded(
                  child: _AllDayCell(
                    entries: entriesForDay(
                      widget.entries,
                      day,
                    ).where((entry) => entry.allDay).toList(),
                    onTap: widget.onOpenEntry,
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: widget.scrollController,
            child: SizedBox(
              height: _hourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HourGutter(),
                  for (final day in days)
                    Expanded(
                      child: _TimeGridDay(
                        day: day,
                        entries: entriesForDay(widget.entries, day),
                        profile: widget.profile,
                        onOpenEntry: widget.onOpenEntry,
                        onDropTask: widget.onDropTask,
                        onDropBlock: widget.onDropBlock,
                        onNudgeBlock: widget.onNudgeBlock,
                        onDeleteBlock: widget.onDeleteBlock,
                        showDayDivider: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayView extends StatelessWidget {
  const _DayView({
    required this.day,
    required this.entries,
    required this.profile,
    required this.scrollController,
    required this.onOpenEntry,
    required this.onDropTask,
    required this.onDropBlock,
    required this.onNudgeBlock,
    required this.onDeleteBlock,
  });

  final DateTime day;
  final List<CalendarEntry> entries;
  final PlanningProfile profile;
  final ScrollController scrollController;
  final Future<void> Function(CalendarEntry entry) onOpenEntry;
  final Future<void> Function(
    PlannableCalendarTask task,
    DateTime day,
    int minute,
  )
  onDropTask;
  final Future<void> Function(TaskScheduleBlock block, DateTime day, int minute)
  onDropBlock;
  final Future<void> Function(
    TaskScheduleBlock block,
    int minutes, {
    required bool resize,
  })
  onNudgeBlock;
  final Future<void> Function(TaskScheduleBlock block) onDeleteBlock;

  @override
  Widget build(BuildContext context) {
    final allDay = entries.where((entry) => entry.allDay).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allDay.isNotEmpty)
          Container(
            constraints: const BoxConstraints(minHeight: _allDayHeight),
            padding: const EdgeInsets.only(bottom: 4),
            child: _AllDayCell(entries: allDay, onTap: onOpenEntry),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            child: SizedBox(
              height: _hourHeight * 24,
              child: Row(
                children: [
                  const _HourGutter(),
                  Expanded(
                    child: _TimeGridDay(
                      day: day,
                      entries: entries.where((entry) => !entry.allDay).toList(),
                      profile: profile,
                      onOpenEntry: onOpenEntry,
                      onDropTask: onDropTask,
                      onDropBlock: onDropBlock,
                      onNudgeBlock: onNudgeBlock,
                      onDeleteBlock: onDeleteBlock,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AllDayCell extends StatelessWidget {
  const _AllDayCell({required this.entries, required this.onTap});

  final List<CalendarEntry> entries;
  final Future<void> Function(CalendarEntry entry) onTap;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries.take(2))
            InkWell(
              onTap: () => onTap(entry),
              child: Container(
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HourGutter extends StatelessWidget {
  const _HourGutter();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _gutterWidth,
      child: Column(
        children: [
          for (var hour = 0; hour < 24; hour++)
            SizedBox(
              height: _hourHeight,
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    '${hour.toString().padLeft(2, '0')}:00',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeGridDay extends StatefulWidget {
  const _TimeGridDay({
    required this.day,
    required this.entries,
    required this.profile,
    required this.onOpenEntry,
    required this.onDropTask,
    required this.onDropBlock,
    required this.onNudgeBlock,
    required this.onDeleteBlock,
    this.showDayDivider = false,
  });

  final DateTime day;
  final List<CalendarEntry> entries;
  final PlanningProfile profile;
  final Future<void> Function(CalendarEntry entry) onOpenEntry;
  final Future<void> Function(
    PlannableCalendarTask task,
    DateTime day,
    int minute,
  )
  onDropTask;
  final Future<void> Function(TaskScheduleBlock block, DateTime day, int minute)
  onDropBlock;
  final Future<void> Function(
    TaskScheduleBlock block,
    int minutes, {
    required bool resize,
  })
  onNudgeBlock;
  final Future<void> Function(TaskScheduleBlock block) onDeleteBlock;
  final bool showDayDivider;

  @override
  State<_TimeGridDay> createState() => _TimeGridDayState();
}

class _TimeGridDayState extends State<_TimeGridDay> {
  BuildContext? _gridContext;

  int _minuteAt(Offset globalOffset) {
    final box = _gridContext?.findRenderObject() as RenderBox?;
    if (box == null) return 0;
    final local = box.globalToLocal(globalOffset);
    final raw = (local.dy / box.size.height * 1440).round();
    return (raw ~/ 15) * 15;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayStart = DayMath.dateOnly(widget.day);
    final dayEnd = DayMath.addDays(dayStart, 1);
    final conflicts = conflictingEntryKeys(widget.entries);
    final timed = widget.entries.where((entry) => !entry.allDay).toList();

    // A simple greedy lane assignment keeps overlapping cards side by side
    // instead of hiding each other.
    final laneEnds = <DateTime>[];
    final lanes = <String, int>{};
    for (final entry in timed) {
      var lane = laneEnds.indexWhere((end) => !end.isAfter(entry.start));
      if (lane == -1) {
        lane = laneEnds.length;
        laneEnds.add(entry.end);
      } else {
        laneEnds[lane] = entry.end;
      }
      lanes[entry.key] = lane;
    }
    final laneCount = laneEnds.isEmpty ? 1 : laneEnds.length;

    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) =>
          details.data is PlannableCalendarTask ||
          details.data is TaskScheduleBlock,
      onAcceptWithDetails: (details) {
        final minute = _minuteAt(details.offset);
        final data = details.data;
        if (data is PlannableCalendarTask) {
          unawaited(widget.onDropTask(data, widget.day, minute));
        } else if (data is TaskScheduleBlock) {
          unawaited(widget.onDropBlock(data, widget.day, minute));
        }
      },
      builder: (context, candidate, rejected) {
        return LayoutBuilder(
          builder: (context, constraints) {
            _gridContext = context;
            return Container(
              decoration: BoxDecoration(
                color: candidate.isEmpty
                    ? null
                    : theme.colorScheme.primary.withValues(alpha: 0.05),
                border: widget.showDayDivider
                    ? Border(
                        left: BorderSide(
                          color: theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.55,
                          ),
                        ),
                      )
                    : null,
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      for (var hour = 0; hour < 24; hour++)
                        Container(
                          height: _hourHeight,
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (final entry in timed)
                    _PositionedEntry(
                      entry: entry,
                      dayStart: dayStart,
                      dayEnd: dayEnd,
                      lane: lanes[entry.key] ?? 0,
                      laneCount: laneCount,
                      availableWidth: constraints.maxWidth,
                      conflict: conflicts.contains(entry.key),
                      onTap: () => widget.onOpenEntry(entry),
                      onNudge: widget.onNudgeBlock,
                      onDelete: widget.onDeleteBlock,
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _PositionedEntry extends StatelessWidget {
  const _PositionedEntry({
    required this.entry,
    required this.dayStart,
    required this.dayEnd,
    required this.lane,
    required this.laneCount,
    required this.availableWidth,
    required this.conflict,
    required this.onTap,
    required this.onNudge,
    required this.onDelete,
  });

  final CalendarEntry entry;
  final DateTime dayStart;
  final DateTime dayEnd;
  final int lane;
  final int laneCount;
  final double availableWidth;
  final bool conflict;
  final VoidCallback onTap;
  final Future<void> Function(
    TaskScheduleBlock block,
    int minutes, {
    required bool resize,
  })
  onNudge;
  final Future<void> Function(TaskScheduleBlock block) onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = entry.start.isBefore(dayStart) ? dayStart : entry.start;
    final end = entry.end.isAfter(dayEnd) ? dayEnd : entry.end;
    final top = start.difference(dayStart).inMinutes / 60 * _hourHeight;
    final height = ((end.difference(start).inMinutes / 60) * _hourHeight).clamp(
      20.0,
      _hourHeight * 24,
    );
    final color = conflict
        ? theme.colorScheme.errorContainer
        : entry.kind == CalendarEntryKind.block
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.tertiaryContainer;
    final laneWidth = availableWidth / laneCount;

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: conflict
            ? Border.all(color: theme.colorScheme.error, width: 1.4)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.title,
            maxLines: height > 44 ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (height > 30)
            Text(
              '${DateFormat('HH:mm').format(entry.start)}–'
              '${DateFormat('HH:mm').format(entry.end)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
        ],
      ),
    );

    final block = entry.block;
    final interactive = block == null
        ? InkWell(onTap: onTap, child: card)
        : Focus(
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final shift = HardwareKeyboard.instance.isShiftPressed;
              if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                unawaited(onNudge(block, -15, resize: shift));
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                unawaited(onNudge(block, 15, resize: shift));
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.enter ||
                  event.logicalKey == LogicalKeyboardKey.space) {
                onTap();
                return KeyEventResult.handled;
              }
              if (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace) {
                unawaited(onDelete(block));
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Draggable<TaskScheduleBlock>(
              data: block,
              feedback: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 180,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(entry.title, maxLines: 2),
                  ),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: card),
              child: InkWell(onTap: onTap, child: card),
            ),
          );

    return Positioned(
      top: top,
      height: height,
      left: laneWidth * lane,
      width: laneWidth,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: interactive,
      ),
    );
  }
}

// ==================== AGENDA ====================

class _AgendaView extends StatelessWidget {
  const _AgendaView({
    required this.range,
    required this.entries,
    required this.onOpenEntry,
    required this.onSelectDay,
  });

  final ({DateTime from, DateTime to}) range;
  final List<CalendarEntry> entries;
  final Future<void> Function(CalendarEntry entry) onOpenEntry;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final days = [
      for (
        var offset = 0;
        offset <= range.to.difference(range.from).inDays;
        offset++
      )
        DayMath.addDays(range.from, offset),
    ];
    return ListView.builder(
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        final dayEntries = entriesForDay(entries, day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => onSelectDay(day),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Text(
                  dayHeading(day),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ),
            if (dayEntries.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 12, bottom: 10),
                child: Text('No events or blocks.'),
              )
            else
              for (final entry in dayEntries)
                ListTile(
                  dense: true,
                  leading: Icon(
                    entry.kind == CalendarEntryKind.block
                        ? Icons.work_outline
                        : Icons.event_outlined,
                    size: 18,
                  ),
                  title: Text(entry.title),
                  subtitle: Text(
                    entry.allDay
                        ? 'All day'
                        : '${DateFormat('HH:mm').format(entry.start)} – '
                              '${DateFormat('HH:mm').format(entry.end)}',
                  ),
                  onTap: () => onOpenEntry(entry),
                ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

// ==================== SIDE PANEL ====================

class _CalendarSidePanel extends ConsumerWidget {
  const _CalendarSidePanel({
    required this.profile,
    required this.entries,
    required this.selectedDay,
    required this.plannable,
    required this.onScheduleAtDefault,
    required this.onOpenEntry,
  });

  final PlanningProfile profile;
  final List<CalendarEntry> entries;
  final DateTime selectedDay;
  final List<PlannableCalendarTask> plannable;
  final Future<void> Function(PlannableCalendarTask task) onScheduleAtDefault;
  final Future<void> Function(CalendarEntry entry) onOpenEntry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskViews =
        ref.watch(savedFiltersProvider('tasks')).valueOrNull ??
        const <SavedFilter>[];
    final projectViews =
        ref.watch(savedFiltersProvider('projects')).valueOrNull ??
        const <SavedFilter>[];
    final dayEntries = entriesForDay(entries, selectedDay);
    final blocks = dayEntries
        .where((entry) => entry.block != null)
        .map(
          (entry) => BookedInterval(
            taskKey: entry.taskKey,
            start: entry.start,
            end: entry.end,
          ),
        )
        .toList();
    final busyEvents = dayEntries
        .where(
          (entry) => entry.kind == CalendarEntryKind.event && !entry.allDay,
        )
        .map((entry) => (start: entry.start, end: entry.end))
        .toList();
    final capacity = CapacityService.summarize(
      CapacityInput(
        day: selectedDay,
        workingHours: profile.windowsFor(selectedDay.weekday),
        breaks: profile.breaksFor(selectedDay.weekday),
        busyEvents: busyEvents,
        blocks: blocks,
        bufferMinutes: profile.bufferMinutes,
      ),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capacity · ${DateFormat('EEE d MMM').format(selectedDay)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                _CapacityBar(summary: capacity),
                const SizedBox(height: 8),
                Text(
                  '${capacity.availableMinutes ~/ 60}h '
                  '${capacity.availableMinutes % 60}m available · '
                  '${capacity.plannedMinutes ~/ 60}h '
                  '${capacity.plannedMinutes % 60}m planned',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (capacity.isOvercommitted) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Overcommitted by ${capacity.overcommittedBy} min. '
                    'Plans are advisory; nothing is blocked.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Unscheduled (${plannable.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: plannable.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Everything in this view is scheduled.'),
                  )
                : ListView.builder(
                    itemCount: plannable.length,
                    itemBuilder: (context, index) {
                      final task = plannable[index];
                      return Draggable<PlannableCalendarTask>(
                        data: task,
                        feedback: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 240,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.4,
                          child: _TaskTile(
                            task: task,
                            onSchedule: () => onScheduleAtDefault(task),
                          ),
                        ),
                        child: _TaskTile(
                          task: task,
                          onSchedule: () => onScheduleAtDefault(task),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved views',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'New saved view',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => SavedViewDialog.show(context),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 170,
            child: taskViews.isEmpty && projectViews.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Create a smart view for tasks or projects. Filters '
                      'are validated and never run as raw SQL.',
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (final filter in [...taskViews, ...projectViews])
                        _SavedViewTile(filter: filter),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CapacityBar extends StatelessWidget {
  const _CapacityBar({required this.summary});

  final CapacitySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planned = summary.plannedMinutes;
    final total = summary.availableMinutes;
    final ratio = total == 0
        ? (planned > 0 ? 1.0 : 0.0)
        : (planned / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 10,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        color: summary.isOvercommitted
            ? theme.colorScheme.error
            : theme.colorScheme.primary,
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task, required this.onSchedule});

  final PlannableCalendarTask task;
  final VoidCallback onSchedule;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (task.projectName != null) task.projectName!,
          if (task.estimatedMinutes != null) '${task.estimatedMinutes} min',
        ].join(' · '),
      ),
      trailing: IconButton(
        tooltip: 'Schedule at day start',
        icon: const Icon(Icons.playlist_add, size: 18),
        onPressed: onSchedule,
      ),
    );
  }
}

class _SavedViewTile extends ConsumerWidget {
  const _SavedViewTile({required this.filter});

  final SavedFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: Icon(
        filter.isPinned ? Icons.push_pin : Icons.filter_alt_outlined,
        size: 18,
      ),
      title: Text(filter.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(filter.entityScope),
      onTap: () => SavedViewResultsDialog.show(context, filter),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, size: 18),
        onSelected: (action) {
          final repository = ref.read(savedFilterRepositoryProvider);
          if (action == 'apply') {
            SavedViewResultsDialog.show(context, filter);
          } else if (action == 'pin') {
            repository.setPinned(filter, !filter.isPinned);
          } else if (action == 'delete') {
            repository.delete(filter);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'apply', child: Text('Apply')),
          PopupMenuItem(
            value: 'pin',
            child: Text(filter.isPinned ? 'Unpin' : 'Pin'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
