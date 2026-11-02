import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/day_math.dart';
import '../../../../core/widgets/user_action_error.dart';
import '../../data/my_day_models.dart';
import '../../providers/my_day_providers.dart';

/// Opens the searchable picker for to-dos and project checklist tasks.
Future<PlannableTaskView?> showMyDayTaskPicker(
  BuildContext context,
  WidgetRef ref,
  DateTime day,
) {
  return showDialog<PlannableTaskView>(
    context: context,
    builder: (_) => _MyDayTaskPickerDialog(day: day),
  );
}

class _MyDayTaskPickerDialog extends ConsumerStatefulWidget {
  const _MyDayTaskPickerDialog({required this.day});

  final DateTime day;

  @override
  ConsumerState<_MyDayTaskPickerDialog> createState() =>
      _MyDayTaskPickerDialogState();
}

class _MyDayTaskPickerDialogState
    extends ConsumerState<_MyDayTaskPickerDialog> {
  late Future<List<PlannableTaskView>> _tasks;
  String _query = '';
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _tasks = ref.read(myDayControllerProvider).plannableTasks(widget.day);
  }

  void _reload() {
    setState(() {
      _tasks = ref.read(myDayControllerProvider).plannableTasks(widget.day);
    });
  }

  Future<void> _create(String title) async {
    setState(() => _creating = true);
    final created = await runUserMutation(
      context,
      () =>
          ref.read(myDayControllerProvider).createTodoForDay(widget.day, title),
      failureMessage: 'Could not create the task.',
    );
    if (!mounted) return;
    setState(() => _creating = false);
    if (!created) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Created “${title.trim()}”')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    return AlertDialog(
      title: Row(
        children: [
          const Text('Add to My Day'),
          const Spacer(),
          Text(
            DateFormat('EEE d MMM').format(widget.day),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search tasks',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) _create(value);
              },
            ),
            const SizedBox(height: 8),
            if (query.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _creating ? null : () => _create(_query),
                  icon: _creating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text('Create “${_query.trim()}” for this day'),
                ),
              ),
            Expanded(
              child: FutureBuilder<List<PlannableTaskView>>(
                future: _tasks,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Could not load tasks: ${snapshot.error}'),
                    );
                  }
                  final all = snapshot.data ?? const <PlannableTaskView>[];
                  final visible = query.isEmpty
                      ? all
                      : all
                            .where(
                              (task) =>
                                  task.title.toLowerCase().contains(query) ||
                                  (task.projectName?.toLowerCase().contains(
                                        query,
                                      ) ??
                                      false),
                            )
                            .toList();
                  if (visible.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? 'Nothing left to plan. Create a task above.'
                            : 'No matching tasks.',
                        style: theme.textTheme.bodySmall,
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final task = visible[index];
                      return ListTile(
                        enabled: !task.alreadyPlanned,
                        title: Text(task.title),
                        subtitle: _subtitle(context, task),
                        trailing: task.alreadyPlanned
                            ? const Chip(label: Text('Planned'))
                            : const Icon(Icons.add_circle_outline),
                        onTap: task.alreadyPlanned
                            ? null
                            : () => Navigator.pop(context, task),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(onPressed: _reload, child: const Text('Refresh')),
      ],
    );
  }

  Widget? _subtitle(BuildContext context, PlannableTaskView task) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (task.projectName != null) task.projectName!,
      if (task.dueDate != null)
        'Due ${DateFormat.MMMd().format(task.dueDate!)}',
      if (task.source == PlannedTaskSource.projectTask) 'Project checklist',
    ];
    if (parts.isEmpty) return null;
    return Text(
      parts.join(' · '),
      style: theme.textTheme.bodySmall?.copyWith(
        color:
            task.dueDate != null &&
                DayMath.calendarDaysBetween(task.dueDate!, widget.day) > 0
            ? theme.colorScheme.error
            : null,
      ),
    );
  }
}
