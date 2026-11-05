import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/project_status.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/project_repository.dart';
import '../data/project_workflow_repository.dart';
import '../../tasks/data/task_metadata.dart';

Future<void> showProjectTaskEditor({
  required BuildContext context,
  required String projectId,
  required Task task,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ProjectTaskEditorDialog(projectId: projectId, task: task),
  );
}

class _ProjectTaskEditorDialog extends ConsumerStatefulWidget {
  const _ProjectTaskEditorDialog({required this.projectId, required this.task});

  final String projectId;
  final Task task;

  @override
  ConsumerState<_ProjectTaskEditorDialog> createState() =>
      _ProjectTaskEditorDialogState();
}

class _ProjectTaskEditorDialogState
    extends ConsumerState<_ProjectTaskEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _estimate;
  late String _statusKey;
  late int _priority;
  DateTime? _startDate;
  DateTime? _dueDate;
  String? _newPredecessorId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.task.title);
    _estimate = TextEditingController(
      text: widget.task.estimatedMinutes?.toString() ?? '',
    );
    _statusKey = ProjectStatusCatalog.normalize(widget.task.statusKey);
    _priority = widget.task.priority.clamp(0, 3);
    _startDate = widget.task.startDate;
    _dueDate = widget.task.dueDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _estimate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statuses =
        ref.watch(projectStatusesProvider(widget.projectId)).valueOrNull ??
        const <ProjectStatus>[];
    final tasks =
        ref.watch(projectTasksProvider(widget.projectId)).valueOrNull ??
        const <Task>[];
    final dependencies =
        ref.watch(projectDependenciesProvider(widget.projectId)).valueOrNull ??
        const <TaskDependency>[];
    final repository = ref.read(projectWorkflowRepositoryProvider);
    final taskById = {for (final task in tasks) task.id: task};
    final predecessors = [
      for (final dependency in dependencies)
        if (dependency.successorTaskId == widget.task.id)
          taskById[dependency.predecessorTaskId],
    ].whereType<Task>().toList();
    final warnings = repository.dependencyWarnings(
      task: widget.task,
      projectTasks: tasks,
      dependencies: dependencies,
    );
    final existingPredecessorIds = predecessors.map((task) => task.id).toSet();
    final eligiblePredecessors =
        tasks
            .where(
              (task) =>
                  task.id != widget.task.id &&
                  !existingPredecessorIds.contains(task.id),
            )
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    final statusOptions = statuses.isEmpty
        ? [
            for (final spec in ProjectStatusCatalog.all)
              ProjectStatus(
                id: spec.key,
                projectId: widget.projectId,
                statusKey: spec.key,
                name: spec.label,
                colorToken: spec.colorToken,
                position: spec.position,
                isDone: spec.isDone,
                isDefault: true,
                createdAt: DateTime(2000),
                updatedAt: DateTime(2000),
              ),
          ]
        : statuses;

    return AlertDialog(
      title: const Text('Edit project task'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    statusOptions.any(
                      (status) => status.statusKey == _statusKey,
                    )
                    ? _statusKey
                    : statusOptions.first.statusKey,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final status in statusOptions)
                    DropdownMenuItem(
                      value: status.statusKey,
                      child: Text(status.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _statusKey = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Start date',
                      value: _startDate,
                      onPick: () => _pickDate(_startDate, (value) {
                        setState(() => _startDate = value);
                      }),
                      onClear: () => setState(() => _startDate = null),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DateField(
                      label: 'Due date',
                      value: _dueDate,
                      onPick: () => _pickDate(_dueDate, (value) {
                        setState(() => _dueDate = value);
                      }),
                      onClear: () => setState(() => _dueDate = null),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _estimate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimate (minutes)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final priority in TaskPriority.values)
                          DropdownMenuItem(
                            value: priority.value,
                            child: Text(priority.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _priority = value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Dependencies (finish to start)',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (predecessors.isEmpty)
                const Text(
                  'No blockers. Dependencies are advisory in Phase 3 and never '
                  'move dates automatically.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final predecessor in predecessors)
                      InputChip(
                        label: Text(predecessor.title),
                        onDeleted: () async {
                          final dependency = dependencies.firstWhere(
                            (value) =>
                                value.successorTaskId == widget.task.id &&
                                value.predecessorTaskId == predecessor.id,
                          );
                          await runUserMutation(
                            context,
                            () => ref
                                .read(projectWorkflowRepositoryProvider)
                                .removeDependency(dependency),
                            failureMessage: 'Could not remove the dependency.',
                          );
                        },
                      ),
                  ],
                ),
              if (eligiblePredecessors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _newPredecessorId,
                        decoration: const InputDecoration(
                          labelText: 'Add blocker',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final task in eligiblePredecessors)
                            DropdownMenuItem(
                              value: task.id,
                              child: Text(
                                task.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _newPredecessorId = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Add dependency',
                      onPressed: _newPredecessorId == null
                          ? null
                          : () async {
                              final predecessorId = _newPredecessorId!;
                              final success = await runUserMutation(
                                context,
                                () => ref
                                    .read(projectWorkflowRepositoryProvider)
                                    .addDependency(
                                      predecessorTaskId: predecessorId,
                                      successorTaskId: widget.task.id,
                                    ),
                                failureMessage:
                                    'Could not add the dependency. A task '
                                    'cannot depend on itself or form a cycle.',
                              );
                              if (success && mounted) {
                                setState(() => _newPredecessorId = null);
                              }
                            },
                      icon: const Icon(Icons.add_link),
                    ),
                  ],
                ),
              ],
              if (warnings.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (final warning in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            warning,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving ? null : _delete,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('Delete task'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _pickDate(
    DateTime? current,
    void Function(DateTime?) apply,
  ) async {
    final today = DayMath.dateOnly(AppClock.now());
    final initial = current ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) apply(DayMath.dateOnly(picked));
  }

  Future<void> _save() async {
    final estimateText = _estimate.text.trim();
    final estimate = estimateText.isEmpty ? null : int.tryParse(estimateText);
    if (estimateText.isNotEmpty && estimate == null) {
      _showError('The estimate must be a whole number of minutes.');
      return;
    }
    setState(() => _saving = true);
    final success = await runUserMutation(
      context,
      () => ref
          .read(projectWorkflowRepositoryProvider)
          .updateTask(
            widget.task,
            title: _title.text,
            statusKey: _statusKey,
            startDate: _startDate,
            dueDate: _dueDate,
            estimatedMinutes: estimate,
            priority: _priority,
          ),
      failureMessage: 'Could not save the task.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final success = await runUserMutation(
      context,
      () => ref
          .read(projectWorkflowRepositoryProvider)
          .deleteTaskWithUndo(widget.task),
      failureMessage: 'Could not delete the task.',
    );
    if (!success || !mounted) return;
    UndoSnackbar.show(
      context,
      message: 'Project task deleted',
      service: ref.read(undoServiceProvider),
    );
    Navigator.pop(context);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value == null
              ? const Icon(Icons.calendar_today_outlined, size: 18)
              : IconButton(
                  tooltip: 'Clear $label',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: onClear,
                ),
        ),
        child: Text(
          value == null ? 'Not set' : DateFormat('MMM d, yyyy').format(value!),
          style: TextStyle(
            color: value == null ? Theme.of(context).hintColor : null,
          ),
        ),
      ),
    );
  }
}
