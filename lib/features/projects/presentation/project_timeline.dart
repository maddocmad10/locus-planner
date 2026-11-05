import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import 'status_settings_dialog.dart';

enum TimelineZoom {
  day(28, 'Day'),
  week(12, 'Week'),
  month(5, 'Month');

  const TimelineZoom(this.pixelsPerDay, this.label);
  final double pixelsPerDay;
  final String label;
}

/// Read-only project timeline. Bar positions, dependency connectors and the
/// visible range are all derived; nothing here is persisted.
class ProjectTimeline extends StatefulWidget {
  const ProjectTimeline({
    super.key,
    required this.tasks,
    required this.milestones,
    required this.dependencies,
    required this.statuses,
    required this.onOpenTask,
    required this.onOpenMilestone,
    this.today,
  });

  final List<Task> tasks;
  final List<ProjectMilestone> milestones;
  final List<TaskDependency> dependencies;
  final List<ProjectStatus> statuses;
  final ValueChanged<Task> onOpenTask;
  final ValueChanged<ProjectMilestone> onOpenMilestone;
  final DateTime? today;

  @override
  State<ProjectTimeline> createState() => _ProjectTimelineState();
}

class _ProjectTimelineState extends State<ProjectTimeline> {
  TimelineZoom _zoom = TimelineZoom.week;

  static const _headerHeight = 30.0;
  static const _rowHeight = 34.0;
  static const _labelWidth = 172.0;

  @override
  Widget build(BuildContext context) {
    final today = DayMath.dateOnly(widget.today ?? AppClock.now());
    final scheduledTasks =
        widget.tasks
            .where((task) => task.startDate != null || task.dueDate != null)
            .toList()
          ..sort((a, b) {
            final aDate = a.startDate ?? a.dueDate!;
            final bDate = b.startDate ?? b.dueDate!;
            final byDate = aDate.compareTo(bDate);
            return byDate != 0
                ? byDate
                : a.title.toLowerCase().compareTo(b.title.toLowerCase());
          });
    final unscheduledTasks =
        widget.tasks
            .where((task) => task.startDate == null && task.dueDate == null)
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final scheduledMilestones =
        widget.milestones
            .where((milestone) => milestone.targetDate != null)
            .toList()
          ..sort((a, b) => a.targetDate!.compareTo(b.targetDate!));
    final unscheduledMilestones = widget.milestones
        .where((milestone) => milestone.targetDate == null)
        .toList();

    final dates = <DateTime>[
      today,
      for (final task in scheduledTasks) ...[
        if (task.startDate != null) task.startDate!,
        if (task.dueDate != null) task.dueDate!,
      ],
      for (final milestone in scheduledMilestones) milestone.targetDate!,
    ];
    var rangeStart = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    var rangeEnd = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    rangeStart = DayMath.addDays(rangeStart, -3);
    rangeEnd = DayMath.addDays(rangeEnd, 7);
    if (DayMath.calendarDaysBetween(rangeStart, rangeEnd) < 20) {
      rangeEnd = DayMath.addDays(rangeStart, 20);
    }
    final totalDays = DayMath.calendarDaysBetween(rangeStart, rangeEnd) + 1;
    final px = _zoom.pixelsPerDay;
    final rows = <_TimelineRow>[
      for (final task in scheduledTasks)
        _TimelineRow.task(task: task, status: _statusFor(task.statusKey)),
      for (final milestone in scheduledMilestones)
        _TimelineRow.milestone(milestone),
    ];
    final rowIndex = <String, _TimelineRow>{};
    for (var index = 0; index < rows.length; index++) {
      rows[index].index = index;
      final key = rows[index].key;
      if (key != null) rowIndex[key] = rows[index];
    }
    final connectors = <_Connector>[];
    for (final dependency in widget.dependencies) {
      final from = rowIndex['task:${dependency.predecessorTaskId}'];
      final to = rowIndex['task:${dependency.successorTaskId}'];
      if (from == null || to == null) continue;
      connectors.add(_Connector(from: from, to: to));
    }

    final timelineHeight =
        _headerHeight + rows.length * _rowHeight + _rowHeight;
    final timelineWidth = totalDays * px + 24;

    Widget positionedRow(_TimelineRow row, int index) {
      final top = _headerHeight + index * _rowHeight + 5;
      if (row.milestone != null) {
        final date = row.milestone!.targetDate!;
        final left =
            DayMath.calendarDaysBetween(rangeStart, date) * px + px / 2 + 8;
        final completed = row.milestone!.completedAt != null;
        final overdue = !completed && DayMath.dateOnly(date).isBefore(today);
        final color = completed
            ? Colors.green.shade600
            : overdue
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.primary;
        return Positioned(
          left: left - 8,
          top: top + 5,
          child: Tooltip(
            message:
                '${row.milestone!.title} · ${DateFormat('MMM d').format(date)}',
            child: InkWell(
              onTap: () => widget.onOpenMilestone(row.milestone!),
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        );
      }
      final task = row.task!;
      final start = task.startDate ?? task.dueDate!;
      final end = task.dueDate ?? task.startDate!;
      final left = DayMath.calendarDaysBetween(rangeStart, start) * px + 6;
      final width = ((DayMath.calendarDaysBetween(start, end) + 1) * px)
          .clamp(px, double.infinity)
          .toDouble();
      final overdue =
          task.dueDate != null &&
          DayMath.dateOnly(task.dueDate!).isBefore(today) &&
          !task.completed;
      final color = row.status == null
          ? Theme.of(context).colorScheme.primary
          : projectStatusColor(context, row.status!.colorToken);
      return Positioned(
        left: left,
        top: top,
        child: Tooltip(
          message:
              '${task.title} · ${DateFormat('MMM d').format(start)}'
              '${task.dueDate == null ? '' : ' – ${DateFormat('MMM d').format(end)}'}',
          child: InkWell(
            onTap: () => widget.onOpenTask(task),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              height: _rowHeight - 10,
              width: width,
              constraints: BoxConstraints(minWidth: 14),
              decoration: BoxDecoration(
                color: overdue
                    ? Theme.of(context).colorScheme.error.withValues(alpha: 0.8)
                    : color.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: width >= 42
                  ? Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Timeline', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            SegmentedButton<TimelineZoom>(
              segments: [
                for (final zoom in TimelineZoom.values)
                  ButtonSegment(value: zoom, label: Text(zoom.label)),
              ],
              selected: {_zoom},
              onSelectionChanged: (value) =>
                  setState(() => _zoom = value.first),
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty && unscheduledTasks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Add start or due dates to show project tasks on the timeline.',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _labelWidth + timelineWidth,
                  height: timelineHeight,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        top: 0,
                        width: _labelWidth,
                        height: timelineHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: _headerHeight),
                            for (final row in rows)
                              SizedBox(
                                height: _rowHeight,
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 8,
                                    top: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        row.milestone == null
                                            ? Icons.task_alt
                                            : Icons.flag_outlined,
                                        size: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          row.milestone?.title ??
                                              row.task!.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: _labelWidth,
                        top: 0,
                        child: SizedBox(
                          width: timelineWidth,
                          height: timelineHeight,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _TimelinePainter(
                                    rangeStart: rangeStart,
                                    totalDays: totalDays,
                                    pixelsPerDay: px,
                                    today: today,
                                    rowHeight: _rowHeight,
                                    headerHeight: _headerHeight,
                                    rows: rows,
                                    connectors: connectors,
                                  ),
                                ),
                              ),
                              for (var index = 0; index < rows.length; index++)
                                positionedRow(rows[index], index),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        if (unscheduledTasks.isNotEmpty ||
            unscheduledMilestones.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Unscheduled', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final task in unscheduledTasks)
                ActionChip(
                  avatar: const Icon(Icons.task_alt, size: 16),
                  label: Text(task.title),
                  onPressed: () => widget.onOpenTask(task),
                ),
              for (final milestone in unscheduledMilestones)
                ActionChip(
                  avatar: const Icon(Icons.flag_outlined, size: 16),
                  label: Text(milestone.title),
                  onPressed: () => widget.onOpenMilestone(milestone),
                ),
            ],
          ),
        ],
      ],
    );
  }

  ProjectStatus? _statusFor(String key) {
    for (final status in widget.statuses) {
      if (status.statusKey == key) return status;
    }
    return null;
  }
}

class _TimelineRow {
  _TimelineRow.task({required this.task, this.status}) : milestone = null;
  _TimelineRow.milestone(this.milestone) : task = null, status = null;

  final Task? task;
  final ProjectMilestone? milestone;
  final ProjectStatus? status;
  int index = 0;

  String? get key => task == null ? null : 'task:${task!.id}';

  DateTime? get barStart =>
      task == null ? milestone?.targetDate : (task!.startDate ?? task!.dueDate);

  DateTime? get barEnd =>
      task == null ? milestone?.targetDate : (task!.dueDate ?? task!.startDate);
}

class _Connector {
  const _Connector({required this.from, required this.to});
  final _TimelineRow from;
  final _TimelineRow to;
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.rangeStart,
    required this.totalDays,
    required this.pixelsPerDay,
    required this.today,
    required this.rowHeight,
    required this.headerHeight,
    required this.rows,
    required this.connectors,
  });

  final DateTime rangeStart;
  final int totalDays;
  final double pixelsPerDay;
  final DateTime today;
  final double rowHeight;
  final double headerHeight;
  final List<_TimelineRow> rows;
  final List<_Connector> connectors;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.grey.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    final strong = Paint()
      ..color = Colors.grey.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var day = 0; day < totalDays; day++) {
      final x = day * pixelsPerDay + 6;
      final isWeekStart =
          DayMath.addDays(rangeStart, day).weekday == DateTime.monday;
      canvas.drawLine(
        Offset(x, headerHeight),
        Offset(x, size.height),
        isWeekStart ? strong : grid,
      );
    }
    final todayOffset =
        DayMath.calendarDaysBetween(rangeStart, today) * pixelsPerDay + 6;
    final todayPaint = Paint()
      ..color = Colors.redAccent.withValues(alpha: 0.6)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(todayOffset, headerHeight),
      Offset(todayOffset, size.height),
      todayPaint,
    );

    final connectorPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.75)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    final arrow = Paint()
      ..color = Colors.grey.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    for (final connector in connectors) {
      final from = connector.from;
      final to = connector.to;
      final fromStart = from.barStart;
      final fromEnd = from.barEnd;
      final toStart = to.barStart;
      if (fromStart == null || fromEnd == null || toStart == null) continue;
      final fromX =
          (DayMath.calendarDaysBetween(rangeStart, fromEnd) + 1) *
              pixelsPerDay +
          6;
      final toX =
          DayMath.calendarDaysBetween(rangeStart, toStart) * pixelsPerDay + 6;
      final fromY = headerHeight + from.index * rowHeight + rowHeight / 2;
      final toY = headerHeight + to.index * rowHeight + rowHeight / 2;
      final midX = (fromX + toX) / 2;
      final path = Path()
        ..moveTo(fromX, fromY)
        ..lineTo(midX, fromY)
        ..lineTo(midX, toY)
        ..lineTo(toX, toY);
      canvas.drawPath(path, connectorPaint);
      final direction = toX >= midX ? 1.0 : -1.0;
      final arrowPath = Path()
        ..moveTo(toX, toY)
        ..lineTo(toX - 5 * direction, toY - 3)
        ..lineTo(toX - 5 * direction, toY + 3)
        ..close();
      canvas.drawPath(arrowPath, arrow);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.totalDays != totalDays ||
      oldDelegate.pixelsPerDay != pixelsPerDay ||
      oldDelegate.rangeStart != rangeStart ||
      oldDelegate.today != today ||
      oldDelegate.rows.length != rows.length ||
      oldDelegate.connectors.length != connectors.length;
}
