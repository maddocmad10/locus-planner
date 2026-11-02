import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/day_math.dart';
import '../../../../core/widgets/user_action_error.dart';
import '../../data/my_day_models.dart';
import '../../providers/my_day_providers.dart';
import 'task_picker_dialog.dart';

/// The tasks explicitly planned for the selected day, in the user's manual
/// order. Completing one writes through to the original task.
class PlannedTasksList extends ConsumerWidget {
  const PlannedTasksList({super.key, required this.plan});

  final DailyPlanView plan;

  Future<void> _pickTask(BuildContext context, WidgetRef ref) async {
    final picked = await showMyDayTaskPicker(context, ref, plan.day);
    if (picked == null || !context.mounted) return;
    final added = await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).addTask(plan.day, picked),
      failureMessage: 'Could not add the task to My Day.',
    );
    if (added && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added “${picked.title}”')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (plan.items.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(
                Icons.event_note_outlined,
                size: 32,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 8),
              const Text('No tasks planned for this day yet.'),
              const SizedBox(height: 4),
              Text(
                'Pick a few things you intend to work on. Suggested tasks '
                'stay out of the plan until you add them.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: () => _pickTask(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add a task'),
              ),
            ],
          ),
        ),
      );
    }

    final controller = ref.read(myDayControllerProvider);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Text('Planned tasks', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                Text(
                  '${plan.completedCount}/${plan.items.length} done',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _pickTask(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: plan.items.length,
            onReorderItem: (oldIndex, newIndex) {
              final reordered = [...plan.items];
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              runUserMutation(
                context,
                () => controller.reorder(reordered),
                failureMessage: 'Could not save the new order.',
              );
            },
            itemBuilder: (context, index) {
              final item = plan.items[index];
              return _PlannedTaskRow(
                key: ValueKey(item.planItemId),
                item: item,
                day: plan.day,
                index: index,
                onToggleCompleted: (value) => runUserMutation(
                  context,
                  () => controller.setCompleted(item, value),
                  failureMessage: 'Could not update the task.',
                ),
                onEstimate: () => _editEstimate(context, ref, item),
                onRemove: () => runUserMutation(
                  context,
                  () => controller.removeItem(item),
                  failureMessage: 'Could not remove the task from My Day.',
                ),
                onMoveToTomorrow: () => _moveToTomorrow(context, ref, item),
                onMoveToDay: (day) => runUserMutation(
                  context,
                  () => controller.moveToDay(item, day),
                  failureMessage: 'Could not move the task.',
                ),
              );
            },
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Future<void> _moveToTomorrow(
    BuildContext context,
    WidgetRef ref,
    PlannedTaskView item,
  ) async {
    final controller = ref.read(myDayControllerProvider);
    final moved = await runUserMutation(
      context,
      () => controller.moveToTomorrow(plan.day, item),
      failureMessage: 'Could not move the task to tomorrow.',
    );
    if (!moved || !context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${item.title}” moved to tomorrow'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => runUserMutation(
              context,
              () => controller.moveToDay(item, plan.day),
              failureMessage: 'Could not move the task back.',
            ),
          ),
        ),
      );
  }

  Future<void> _editEstimate(
    BuildContext context,
    WidgetRef ref,
    PlannedTaskView item,
  ) async {
    final controller = TextEditingController(
      text: item.plannedMinutes?.toString() ?? '',
    );
    // -1 means the user cancelled; 0 means "clear the estimate". A plain null
    // result cannot tell those apart because dismissing the dialog also
    // returns null.
    const cancel = -1;
    final minutes = await showDialog<int>(
      context: context,
      builder: (ctx) {
        int readValue() => int.tryParse(controller.text.trim()) ?? 0;
        return AlertDialog(
          title: const Text('Planned duration'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutes',
              helperText: 'Leave empty when the duration is unknown.',
            ),
            onSubmitted: (_) => Navigator.pop(ctx, readValue()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, cancel),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, readValue()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    if (minutes == null || minutes == cancel) return;
    final value = minutes <= 0 ? null : minutes;
    if (value == item.plannedMinutes) return;
    await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).updateEstimate(item, value),
      failureMessage: 'Could not save the planned duration.',
    );
  }
}

class _PlannedTaskRow extends StatelessWidget {
  const _PlannedTaskRow({
    super.key,
    required this.item,
    required this.day,
    required this.index,
    required this.onToggleCompleted,
    required this.onEstimate,
    required this.onRemove,
    required this.onMoveToTomorrow,
    required this.onMoveToDay,
  });

  final PlannedTaskView item;
  final DateTime day;
  final int index;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onEstimate;
  final VoidCallback onRemove;
  final VoidCallback onMoveToTomorrow;
  final ValueChanged<DateTime> onMoveToDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = item.dueDate;
    final overdue = due != null && DayMath.calendarDaysBetween(day, due) < 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDayPicker(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: item.completed,
                onChanged: (value) => onToggleCompleted(value ?? false),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text(
                      item.title,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: item.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.completed
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (item.priority > 0)
                          _MetaLabel(
                            icon: Icons.flag_outlined,
                            text: item.priority >= 3 ? 'High' : 'Priority',
                            color: item.priority >= 3
                                ? theme.colorScheme.error
                                : theme.colorScheme.tertiary,
                          ),
                        if (item.projectName != null)
                          _MetaLabel(
                            icon: Icons.folder_outlined,
                            text: item.projectName!,
                          ),
                        if (due != null)
                          _MetaLabel(
                            icon: Icons.calendar_today_outlined,
                            text: 'Due ${DateFormat.MMMd().format(due)}',
                            color: overdue ? theme.colorScheme.error : null,
                          ),
                        _MetaLabel(
                          icon: Icons.schedule,
                          text: item.plannedMinutes == null
                              ? 'No estimate'
                              : '${item.plannedMinutes} min',
                          color: item.plannedMinutes == null
                              ? theme.colorScheme.outline
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Planned task actions',
                onSelected: (value) {
                  switch (value) {
                    case 'estimate':
                      onEstimate();
                      break;
                    case 'tomorrow':
                      onMoveToTomorrow();
                      break;
                    case 'remove':
                      onRemove();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'estimate',
                    child: Text('Set planned duration'),
                  ),
                  PopupMenuItem(
                    value: 'tomorrow',
                    child: Text('Move to tomorrow'),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Keep in backlog'),
                  ),
                ],
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 10, right: 4),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDayPicker(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && DayMath.dateOnly(picked) != DayMath.dateOnly(day)) {
      onMoveToDay(picked);
    }
  }
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: effective),
        const SizedBox(width: 3),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(color: effective),
        ),
      ],
    );
  }
}
