import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/day_math.dart';
import '../data/planning_preferences_repository.dart';

/// Local working-hours and planning defaults. Everything here is advisory: it
/// shapes capacity calculations and the calendar's default slot, never a hard
/// constraint on the user.
class WorkingHoursDialog extends ConsumerStatefulWidget {
  const WorkingHoursDialog({super.key, required this.profile});

  final PlanningProfile profile;

  static Future<void> show(BuildContext context, PlanningProfile profile) {
    return showDialog<void>(
      context: context,
      builder: (_) => WorkingHoursDialog(profile: profile),
    );
  }

  @override
  ConsumerState<WorkingHoursDialog> createState() => _WorkingHoursDialogState();
}

class _WorkingHoursDialogState extends ConsumerState<WorkingHoursDialog> {
  late int _slot;
  late int _weekStart;
  late int _buffer;
  late TimeOfDay _dayStart;
  late TimeOfDay _dayEnd;
  late List<WorkingWindowDraft> _hours;
  late List<WorkingWindowDraft> _breaks;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final profile = widget.profile;
    _slot = profile.defaultSlotMinutes;
    _weekStart = profile.weekStartDay;
    _buffer = profile.bufferMinutes;
    _dayStart = _timeOf(profile.dayStartMinute);
    _dayEnd = _timeOf(profile.dayEndMinute);
    _hours = [...profile.workingHours];
    _breaks = [...profile.breaks];
  }

  static TimeOfDay _timeOf(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  static int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<TimeOfDay?> _pick(TimeOfDay initial) =>
      showTimePicker(context: context, initialTime: initial);

  Future<void> _editWindow(
    WorkingWindowDraft row, {
    required bool isBreak,
  }) async {
    final start = await _pick(_timeOf(row.startMinute));
    if (start == null || !mounted) return;
    final end = await _pick(_timeOf(row.endMinute));
    if (end == null || !mounted) return;
    final updated = row.copyWith(
      startMinute: _minutesOf(start),
      endMinute: _minutesOf(end),
    );
    setState(() {
      if (isBreak) {
        _breaks = [
          for (final current in _breaks)
            if (identical(current, row)) updated else current,
        ];
      } else {
        _hours = [
          for (final current in _hours)
            if (identical(current, row)) updated else current,
        ];
      }
      _error = null;
    });
  }

  Future<void> _addWindow(int weekday, {required bool isBreak}) async {
    if (isBreak) {
      final draft = await _BreakDialog.show(context, weekday: weekday);
      if (draft == null || !mounted) return;
      setState(() => _breaks = [..._breaks, draft]);
      return;
    }
    final start = await _pick(const TimeOfDay(hour: 9, minute: 0));
    if (start == null || !mounted) return;
    final end = await _pick(const TimeOfDay(hour: 17, minute: 0));
    if (end == null || !mounted) return;
    setState(() {
      _hours = [
        ..._hours,
        WorkingWindowDraft(
          weekday: weekday,
          startMinute: _minutesOf(start),
          endMinute: _minutesOf(end),
        ),
      ];
    });
  }

  void _toggleDay(int weekday, bool enabled) {
    setState(() {
      final existing = _hours.where((row) => row.weekday == weekday).toList();
      if (!enabled) {
        _hours = [
          for (final row in _hours)
            if (row.weekday == weekday) row.copyWith(enabled: false) else row,
        ];
        return;
      }
      if (existing.isEmpty) {
        _hours = [
          ..._hours,
          WorkingWindowDraft(
            weekday: weekday,
            startMinute: _minutesOf(_dayStart),
            endMinute: _minutesOf(_dayEnd),
          ),
        ];
      } else {
        _hours = [
          for (final row in _hours)
            if (row.weekday == weekday) row.copyWith(enabled: true) else row,
        ];
      }
    });
  }

  Future<void> _save() async {
    final dayStart = _minutesOf(_dayStart);
    final dayEnd = _minutesOf(_dayEnd);
    if (dayEnd <= dayStart) {
      setState(() => _error = 'Day end must be after day start.');
      return;
    }
    for (final row in [..._hours, ..._breaks]) {
      if (row.endMinute <= row.startMinute) {
        setState(() {
          _error =
              'Every interval must end after it starts ('
              '${_weekdayName(row.weekday)}).';
        });
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(planningPreferencesRepositoryProvider);
    try {
      await repository.savePreferences(
        timezoneId: widget.profile.timezoneId,
        defaultSlotMinutes: _slot,
        weekStartDay: _weekStart,
        dayStartMinute: dayStart,
        dayEndMinute: dayEnd,
        bufferMinutes: _buffer,
      );
      await repository.replaceWorkingHours(_hours);
      await repository.replaceBreaks(_breaks);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Working hours & planning'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              Text('Defaults', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Dropdown(
                    label: 'Slot',
                    value: _slot,
                    values: const [15, 30, 45, 60, 90, 120],
                    labelFor: (value) => '$value min',
                    onChanged: (value) => setState(() => _slot = value),
                  ),
                  _Dropdown(
                    label: 'Week starts',
                    value: _weekStart,
                    values: const [1, 2, 3, 4, 5, 6, 7],
                    labelFor: _weekdayName,
                    onChanged: (value) => setState(() => _weekStart = value),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await _pick(_dayStart);
                      if (picked != null) setState(() => _dayStart = picked);
                    },
                    child: Text('Day start ${_dayStart.format(context)}'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final picked = await _pick(_dayEnd);
                      if (picked != null) setState(() => _dayEnd = picked);
                    },
                    child: Text('Day end ${_dayEnd.format(context)}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Transition buffer'),
                  Expanded(
                    child: Slider(
                      value: _buffer.toDouble(),
                      min: 0,
                      max: 60,
                      divisions: 12,
                      label: '$_buffer min',
                      onChanged: (value) =>
                          setState(() => _buffer = value.round()),
                    ),
                  ),
                  Text('$_buffer min'),
                ],
              ),
              const Divider(height: 28),
              Text('Working hours', style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Capacity is working time minus breaks and busy events. '
                'These are preferences, not restrictions.',
              ),
              const SizedBox(height: 8),
              for (var weekday = 1; weekday <= 7; weekday++)
                _WeekdaySection(
                  weekday: weekday,
                  enabled: _hours.any(
                    (row) => row.weekday == weekday && row.enabled,
                  ),
                  rows: _hours
                      .where((row) => row.weekday == weekday)
                      .toList(growable: false),
                  onToggle: (enabled) => _toggleDay(weekday, enabled),
                  onAdd: () => _addWindow(weekday, isBreak: false),
                  onEdit: (row) => _editWindow(row, isBreak: false),
                  onDelete: (row) {
                    setState(() {
                      _hours = [
                        for (final current in _hours)
                          if (!identical(current, row)) current,
                      ];
                    });
                  },
                ),
              const Divider(height: 28),
              Text('Breaks', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (_breaks.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No recurring breaks.'),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var index = 0; index < _breaks.length; index++)
                    InputChip(
                      label: Text(
                        '${_weekdayName(_breaks[index].weekday)} '
                        '${_timeOf(_breaks[index].startMinute).format(context)}–'
                        '${_timeOf(_breaks[index].endMinute).format(context)}'
                        '${_breaks[index].label == null ? '' : ' · ${_breaks[index].label}'}',
                      ),
                      onPressed: () =>
                          _editWindow(_breaks[index], isBreak: true),
                      onDeleted: () {
                        setState(() => _breaks = [..._breaks]..removeAt(index));
                      },
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _addWindow(DateTime.monday, isBreak: true),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add break'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  static String _weekdayName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}

class _BreakDialog extends StatefulWidget {
  const _BreakDialog({required this.initialWeekday});

  final int initialWeekday;

  static Future<WorkingWindowDraft?> show(
    BuildContext context, {
    required int weekday,
  }) {
    return showDialog<WorkingWindowDraft>(
      context: context,
      builder: (_) => _BreakDialog(initialWeekday: weekday),
    );
  }

  @override
  State<_BreakDialog> createState() => _BreakDialogState();
}

class _BreakDialogState extends State<_BreakDialog> {
  late int _weekday;
  TimeOfDay _start = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 13, minute: 0);
  final _label = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _weekday = widget.initialWeekday;
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add break'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(labelText: 'Weekday'),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text(_WorkingHoursDialogState._weekdayName(day)),
                  ),
              ],
              onChanged: (value) => setState(() => _weekday = value ?? 1),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _start,
                      );
                      if (picked != null) setState(() => _start = picked);
                    },
                    child: Text('Start ${_start.format(context)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _end,
                      );
                      if (picked != null) setState(() => _end = picked);
                    },
                    child: Text('End ${_end.format(context)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final start = _start.hour * 60 + _start.minute;
            final end = _end.hour * 60 + _end.minute;
            if (end <= start) {
              setState(() => _error = 'End must be after start.');
              return;
            }
            Navigator.of(context).pop(
              WorkingWindowDraft(
                weekday: _weekday,
                startMinute: start,
                endMinute: end,
                label: _label.text.trim().isEmpty ? null : _label.text.trim(),
              ),
            );
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelFor,
    required this.onChanged,
  });

  final String label;
  final int value;
  final List<int> values;
  final String Function(int value) labelFor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<int>(
      value: value,
      underline: const SizedBox.shrink(),
      items: [
        for (final option in values)
          DropdownMenuItem(
            value: option,
            child: Text('$label: ${labelFor(option)}'),
          ),
      ],
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _WeekdaySection extends StatelessWidget {
  const _WeekdaySection({
    required this.weekday,
    required this.enabled,
    required this.rows,
    required this.onToggle,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  final int weekday;
  final bool enabled;
  final List<WorkingWindowDraft> rows;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAdd;
  final ValueChanged<WorkingWindowDraft> onEdit;
  final ValueChanged<WorkingWindowDraft> onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Row(
              children: [
                Checkbox(
                  value: enabled,
                  onChanged: (value) => onToggle(value ?? false),
                ),
                Text(_WorkingHoursDialogState._weekdayName(weekday)),
              ],
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (rows.isEmpty)
                  const Text('Off')
                else
                  for (var index = 0; index < rows.length; index++)
                    InputChip(
                      label: Text(
                        '${TimeOfDay(hour: rows[index].startMinute ~/ 60, minute: rows[index].startMinute % 60).format(context)}'
                        '–${TimeOfDay(hour: rows[index].endMinute ~/ 60, minute: rows[index].endMinute % 60).format(context)}',
                      ),
                      onPressed: () => onEdit(rows[index]),
                      onDeleted: () => onDelete(rows[index]),
                    ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Add interval',
            icon: const Icon(Icons.add, size: 18),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Small helper used by the calendar header to describe a window.
String describeMinuteRange(int startMinute, int endMinute) {
  final start = DayMath.dateOnly(
    DateTime(2000),
  ).add(Duration(minutes: startMinute));
  final end = DayMath.dateOnly(
    DateTime(2000),
  ).add(Duration(minutes: endMinute));
  return '${start.hour.toString().padLeft(2, '0')}:'
      '${start.minute.toString().padLeft(2, '0')}–'
      '${end.hour.toString().padLeft(2, '0')}:'
      '${end.minute.toString().padLeft(2, '0')}';
}
