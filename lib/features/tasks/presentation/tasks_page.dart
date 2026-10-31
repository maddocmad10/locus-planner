import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/task_metadata.dart';
import '../data/task_repository.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/command_action_provider.dart';
import '../../../core/utils/date_picker_range.dart';
import '../../../core/utils/recurrence.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/user_action_error.dart';
import '../../../core/widgets/dispose_with.dart';
import '../../../core/utils/app_clock.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  @override
  void initState() {
    super.initState();
    // The palette sets the action just before navigating here, i.e. before this
    // page subscribed to the provider, so ref.listen in build() never sees it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(commandActionProvider) == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).clear();
        _showTaskDialog();
      }
    });
  }

  final TextEditingController _titleController = TextEditingController();
  final FocusNode _taskFocusNode = FocusNode();
  DateTime? _selectedDueDate;

  // ==================== ADD / EDIT TO-DO ====================
  Future<void> _showTaskDialog({TodoItem? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final tagsController = TextEditingController(
      text: TaskTags.toInput(TaskTags.decode(existing?.tags)),
    );
    DateTime? dueDate = existing?.dueDate;
    var priority = TaskPriority.fromStorage(existing?.priority);
    var recurrenceRule = existing?.recurrenceRule ?? Recurrence.none;

    await showDialog(
      context: context,
      builder: (ctx) => DisposeWith(
        disposables: [titleController, tagsController],
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final tags = TaskTags.fromInput(tagsController.text);

            Future<bool> save() => _saveTask(
              ctx,
              existing: existing,
              title: titleController.text.trim(),
              dueDate: dueDate,
              priority: priority,
              tags: tags,
              recurrenceRule: recurrenceRule,
            );

            return AlertDialog(
              title: Text(existing == null ? 'Add to-do' : 'Edit to-do'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                        autofocus: true,
                        onSubmitted: (_) async {
                          if (titleController.text.trim().isEmpty) return;
                          final saved = await save();
                          if (saved && ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<TaskPriority>(
                              initialValue: priority,
                              items: TaskPriority.values
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item,
                                      child: Text(item.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => priority = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Priority',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: recurrenceRule,
                              items: Recurrence.values
                                  .map(
                                    (rule) => DropdownMenuItem(
                                      value: rule,
                                      child: Text(Recurrence.label(rule)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setDialogState(() => recurrenceRule = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Repeat',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: tagsController,
                        decoration: const InputDecoration(
                          labelText: 'Tags (comma separated)',
                          hintText: 'work, errand, home',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final tag in tags)
                                  Chip(
                                    label: Text(tag),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          dueDate == null
                              ? 'No due date'
                              : 'Due: ${DateFormat('MMM dd, yyyy').format(dueDate!)}',
                        ),
                        subtitle: Recurrence.isRecurring(recurrenceRule)
                            ? const Text('A due date is required for repeats')
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (dueDate != null)
                              IconButton(
                                tooltip: 'Clear due date',
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setDialogState(() => dueDate = null),
                              ),
                            const Icon(Icons.calendar_today),
                          ],
                        ),
                        onTap: () async {
                          final range = datePickerRange(
                            current: dueDate,
                            today: AppClock.now(),
                          );
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: range.initial,
                            firstDate: range.first,
                            lastDate: range.last,
                          );
                          if (picked != null) {
                            setDialogState(() => dueDate = picked);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (titleController.text.trim().isEmpty) return;
                    final saved = await save();
                    if (saved && ctx.mounted) Navigator.pop(ctx);
                  },
                  child: Text(existing == null ? 'Add' : 'Save'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<bool> _saveTask(
    BuildContext context, {
    required TodoItem? existing,
    required String title,
    required DateTime? dueDate,
    required TaskPriority priority,
    required List<String> tags,
    required String? recurrenceRule,
  }) async {
    if (Recurrence.isRecurring(recurrenceRule) && dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set a due date before repeating this to-do.'),
        ),
      );
      return false;
    }

    final repository = ref.read(taskRepositoryProvider);
    if (existing == null) {
      return runUserMutation(
        context,
        () => repository.add(
          title: title,
          dueDate: dueDate,
          priority: priority,
          tags: tags,
          recurrenceRule: recurrenceRule,
        ),
        failureMessage: 'Could not add the to-do.',
      );
    }
    return runUserMutation(
      context,
      () => repository.update(
        id: existing.id,
        title: title,
        dueDate: dueDate,
        priority: priority,
        tags: tags,
        recurrenceRule: recurrenceRule,
      ),
      failureMessage: 'Could not update the to-do.',
    );
  }

  // Quick add from the top bar
  Future<void> _quickAddTask() async {
    if (_titleController.text.trim().isEmpty) return;

    final repository = ref.read(taskRepositoryProvider);
    final success = await runUserMutation(
      context,
      () => repository.add(
        title: _titleController.text.trim(),
        dueDate: _selectedDueDate,
      ),
      failureMessage: 'Could not add the to-do.',
    );
    if (!success || !mounted) return;

    _titleController.clear();
    setState(() => _selectedDueDate = null);
    _taskFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taskFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(taskRepositoryProvider);

    // Command Palette support
    ref.listen<CommandAction>(commandActionProvider, (previous, next) {
      if (next == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTaskDialog();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('To-do'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showTaskDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Quick Add Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    focusNode: _taskFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Quick add a to-do...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _quickAddTask(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Set due date',
                  onPressed: () async {
                    final range = datePickerRange(
                      current: _selectedDueDate,
                      today: AppClock.now(),
                    );
                    final date = await showDatePicker(
                      context: context,
                      initialDate: range.initial,
                      firstDate: range.first,
                      lastDate: range.last,
                    );
                    if (date != null) {
                      setState(() => _selectedDueDate = date);
                    }
                  },
                ),
                FilledButton(
                  onPressed: _quickAddTask,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          if (_selectedDueDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text(
                    'Due: ${DateFormat('MMM dd').format(_selectedDueDate!)}',
                  ),
                  onDeleted: () => setState(() => _selectedDueDate = null),
                ),
              ),
            ),

          const Divider(height: 1),

          // Tasks List
          Expanded(
            child: ref
                .watch(tasksStreamProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) =>
                      const Center(child: Text('Could not load tasks.')),
                  data: (tasks) {
                    if (tasks.isEmpty) {
                      return EmptyState(
                        icon: Icons.checklist_outlined,
                        title: 'No to-dos yet',
                        subtitle:
                            'Add a personal to-do. Project checklist items live under Projects.\nYou can also use Ctrl+K → New to-do',
                        buttonLabel: 'Add to-do',
                        onButtonPressed: _showTaskDialog,
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final priority = TaskPriority.fromStorage(
                          task.priority,
                        );
                        final tags = TaskTags.decode(task.tags);
                        final repeats = Recurrence.isRecurring(
                          task.recurrenceRule,
                        );
                        final hasDetails =
                            task.dueDate != null || tags.isNotEmpty || repeats;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Checkbox(
                              value: task.completed,
                              onChanged: (val) async {
                                DateTime? nextDue;
                                final success = await runUserMutation(
                                  context,
                                  () async {
                                    nextDue = await repository.toggle(
                                      task.id,
                                      val ?? false,
                                    );
                                  },
                                  failureMessage: 'Could not update the to-do.',
                                );
                                if (!success ||
                                    nextDue == null ||
                                    !context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Repeated to-do moved to '
                                      '${DateFormat('MMM dd, yyyy').format(nextDue!)}',
                                    ),
                                  ),
                                );
                              },
                            ),
                            title: Row(
                              children: [
                                if (priority != TaskPriority.none) ...[
                                  Tooltip(
                                    message: '${priority.label} priority',
                                    child: Container(
                                      width: 9,
                                      height: 9,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: switch (priority) {
                                          TaskPriority.high => Colors.red,
                                          TaskPriority.medium => Colors.orange,
                                          TaskPriority.low => Colors.blue,
                                          TaskPriority.none => Colors.grey,
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    task.title,
                                    style: TextStyle(
                                      decoration: task.completed
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: task.completed
                                          ? Colors.grey
                                          : null,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: hasDetails
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (task.dueDate != null)
                                          Text(
                                            'Due: ${DateFormat('MMM dd').format(task.dueDate!)}'
                                            '${repeats ? ' · ${Recurrence.label(task.recurrenceRule)}' : ''}',
                                          ),
                                        if (tags.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            child: Wrap(
                                              spacing: 4,
                                              runSpacing: 4,
                                              children: [
                                                for (final tag in tags)
                                                  Chip(
                                                    label: Text(tag),
                                                    labelStyle: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                  ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () =>
                                      _showTaskDialog(existing: task),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete,
                                    color: Colors.red,
                                  ),
                                  onPressed: () async {
                                    final success = await runUserMutation(
                                      context,
                                      () => repository.deleteWithUndo(task),
                                      failureMessage:
                                          'Could not delete the to-do.',
                                    );
                                    if (!success || !context.mounted) return;
                                    UndoSnackbar.show(
                                      context,
                                      message: 'To-do deleted',
                                      service: ref.read(undoServiceProvider),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}
