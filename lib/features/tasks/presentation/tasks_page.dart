import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/task_metadata.dart';
import '../data/task_repository.dart';
import '../../../core/db/app_database.dart';
import '../../../core/domain/project_model.dart';
import '../../../core/providers/command_action_provider.dart';
import '../../../core/utils/date_picker_range.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/utils/md1_plain.dart';
import '../../../core/utils/recurrence.dart';
import '../../../core/widgets/attachment_strip.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/notes_field.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/user_action_error.dart';
import '../../../core/widgets/dispose_with.dart';
import '../../../core/utils/app_clock.dart';
import '../../my_day/data/my_day_repository.dart';
import '../../projects/data/project_repository.dart';

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
      final action = ref.read(commandActionProvider);
      if (action == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).clear();
        _showTaskDialog();
      } else if (action == CommandAction.newTaskForToday) {
        ref.read(commandActionProvider.notifier).clear();
        final today = DayMath.dateOnly(AppClock.now());
        _showTaskDialog(initialDueDate: today, planForDay: today);
      }
    });
  }

  final TextEditingController _titleController = TextEditingController();
  final FocusNode _taskFocusNode = FocusNode();
  DateTime? _selectedDueDate;
  TaskFilter _filter = TaskFilter.all;
  final Set<String> _collapsed = <String>{};

  @override
  void dispose() {
    _titleController.dispose();
    _taskFocusNode.dispose();
    super.dispose();
  }

  // ==================== ADD / EDIT TO-DO ====================

  /// Reads the current projects before showing the editor, so the very first
  /// task dialog can link to a project even if the Projects page was never
  /// opened in this session.
  Future<List<ProjectModel>> _loadProjects() async {
    try {
      return await ref.read(projectsStreamProvider.future);
    } catch (_) {
      return const <ProjectModel>[];
    }
  }

  /// Opens the editor. [parent] creates a nested subtask, [existing] edits an
  /// existing task and preserves every field that is not on screen.
  /// [initialDueDate] pre-fills the due date, and [planForDay] additionally
  /// adds a newly created task to that day's My Day plan.
  Future<void> _showTaskDialog({
    TodoItem? existing,
    TodoItem? parent,
    DateTime? initialDueDate,
    DateTime? planForDay,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var notesFormat = existing?.notesFormat ?? 'plain';
    final tagsController = TextEditingController(
      text: TaskTags.toInput(TaskTags.decode(existing?.tags)),
    );
    final projects = await _loadProjects();
    if (!mounted) return;
    final completions = existing == null
        ? const <TodoCompletion>[]
        : await ref.read(taskRepositoryProvider).completionsFor(existing.id);
    if (!mounted) return;
    final parentId = existing?.parentId ?? parent?.id;
    var startDate = existing?.startDate;
    DateTime? dueDate = existing?.dueDate ?? initialDueDate;
    DateTime? reminderAt = existing?.reminderAt;
    var priority = TaskPriority.fromStorage(existing?.priority);
    var recurrenceRule = existing?.recurrenceRule ?? Recurrence.none;
    var projectId = existing?.projectId ?? parent?.projectId;

    await showDialog(
      context: context,
      builder: (ctx) => DisposeWith(
        disposables: [titleController, notesController, tagsController],
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final tags = TaskTags.fromInput(tagsController.text);
            final scheduled = startDate != null || dueDate != null;

            Future<void> pickDate({required bool start}) async {
              final current = start ? startDate : dueDate;
              final range = datePickerRange(
                current: current,
                today: AppClock.now(),
              );
              final picked = await showDatePicker(
                context: context,
                initialDate: range.initial,
                firstDate: range.first,
                lastDate: range.last,
              );
              if (picked == null) return;
              setDialogState(() {
                if (start) {
                  startDate = picked;
                } else {
                  dueDate = picked;
                }
              });
            }

            Future<void> pickReminder() async {
              final now = AppClock.now();
              final initial = reminderAt ?? dueDate ?? startDate ?? now;
              final range = datePickerRange(current: initial, today: now);
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: range.initial,
                firstDate: range.first,
                lastDate: range.last,
              );
              if (pickedDate == null || !context.mounted) return;
              final pickedTime = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(initial),
              );
              final time = pickedTime ?? TimeOfDay.fromDateTime(initial);
              setDialogState(() {
                reminderAt = DateTime(
                  pickedDate.year,
                  pickedDate.month,
                  pickedDate.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            Future<bool> save() => _saveTask(
              ctx,
              existing: existing,
              title: titleController.text.trim(),
              notes: notesController.text.trim(),
              notesFormat: notesFormat,
              startDate: startDate,
              dueDate: dueDate,
              priority: priority,
              tags: tags,
              recurrenceRule: recurrenceRule,
              parentId: parentId,
              projectId: projectId,
              reminderAt: reminderAt,
              planForDay: planForDay,
            );

            return AlertDialog(
              title: Text(
                existing != null
                    ? 'Edit to-do'
                    : parent != null
                    ? 'Add subtask'
                    : 'Add to-do',
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (parent != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Inside “${parent.title}”',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      if (completions.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Completed ${completions.length} '
                                  'time${completions.length == 1 ? '' : 's'}, '
                                  'last on ${DateFormat.yMMMd().format(completions.first.completedAt)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  completions
                                      .take(3)
                                      .map(
                                        (item) => DateFormat.yMMMd().format(
                                          item.occurrenceDue ??
                                              item.completedAt,
                                        ),
                                      )
                                      .join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
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
                      const SizedBox(height: 12),
                      NotesField(
                        controller: notesController,
                        format: notesFormat,
                        onFormatChanged: (value) =>
                            setDialogState(() => notesFormat = value),
                        hint: 'Details, links, next steps…',
                        minLines: 2,
                        maxLines: 5,
                      ),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      AttachmentStrip(todoId: existing?.id),
                      const SizedBox(height: 8),
                      _DateField(
                        label: 'Start date',
                        value: startDate,
                        onPick: () => pickDate(start: true),
                        onClear: () => setDialogState(() => startDate = null),
                      ),
                      _DateField(
                        label: 'Due date',
                        value: dueDate,
                        onPick: () => pickDate(start: false),
                        onClear: () => setDialogState(() => dueDate = null),
                        helper: Recurrence.isRecurring(recurrenceRule)
                            ? 'A due date is required for repeats'
                            : null,
                      ),
                      const SizedBox(height: 4),
                      _ReminderField(
                        value: reminderAt,
                        onPick: pickReminder,
                        onClear: () => setDialogState(() => reminderAt = null),
                      ),
                      if (projects.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String?>(
                          initialValue: projectId,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('No project'),
                            ),
                            for (final project in projects)
                              DropdownMenuItem<String?>(
                                value: project.id,
                                child: Text(project.name),
                              ),
                          ],
                          onChanged: (value) =>
                              setDialogState(() => projectId = value),
                          decoration: const InputDecoration(
                            labelText: 'Project',
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          scheduled
                              ? 'Scheduled task'
                              : 'Unscheduled task · add a start or due date '
                                    'to schedule it',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
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
    required String? notes,
    required String notesFormat,
    required DateTime? startDate,
    required DateTime? dueDate,
    required TaskPriority priority,
    required List<String> tags,
    required String? recurrenceRule,
    required String? parentId,
    required String? projectId,
    required DateTime? reminderAt,
    DateTime? planForDay,
  }) async {
    if (Recurrence.isRecurring(recurrenceRule) && dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set a due date before repeating this to-do.'),
        ),
      );
      return false;
    }
    if (startDate != null &&
        dueDate != null &&
        DayMath.calendarDaysBetween(startDate, dueDate) < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The start date must be before the due date.'),
        ),
      );
      return false;
    }

    final repository = ref.read(taskRepositoryProvider);
    final normalizedNotes = (notes == null || notes.isEmpty) ? null : notes;
    if (existing == null) {
      return runUserMutation(context, () async {
        final id = await repository.add(
          title: title,
          notes: normalizedNotes,
          notesFormat: notesFormat,
          startDate: startDate,
          dueDate: dueDate,
          priority: priority,
          tags: tags,
          recurrenceRule: recurrenceRule,
          parentId: parentId,
          projectId: projectId,
          reminderAt: reminderAt,
        );
        if (planForDay != null) {
          await ref
              .read(myDayRepositoryProvider)
              .addTodo(day: planForDay, todoId: id);
        }
      }, failureMessage: 'Could not add the to-do.');
    }
    return runUserMutation(
      context,
      () => repository.update(
        id: existing.id,
        title: title,
        notes: normalizedNotes,
        notesFormat: notesFormat,
        startDate: startDate,
        dueDate: dueDate,
        priority: priority,
        tags: tags,
        recurrenceRule: recurrenceRule,
        parentId: parentId,
        projectId: projectId,
        reminderAt: reminderAt,
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

  Future<void> _toggle(TodoItem task, bool value) async {
    final repository = ref.read(taskRepositoryProvider);
    DateTime? nextDue;
    final success = await runUserMutation(context, () async {
      nextDue = await repository.toggle(task.id, value);
    }, failureMessage: 'Could not update the to-do.');
    if (!success || nextDue == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Repeated to-do moved to '
          '${DateFormat('MMM dd, yyyy').format(nextDue!)}',
        ),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => ref.read(undoServiceProvider).undo(),
        ),
      ),
    );
  }

  Future<void> _addToMyDay(TodoItem task) async {
    final day = DayMath.dateOnly(AppClock.now());
    final success = await runUserMutation(
      context,
      () =>
          ref.read(myDayRepositoryProvider).addTodo(day: day, todoId: task.id),
      failureMessage: 'Could not add the to-do to My Day.',
    );
    if (!success || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('“${task.title}” added to My Day')),
      );
  }

  Future<void> _delete(TodoItem task) async {
    final repository = ref.read(taskRepositoryProvider);
    final success = await runUserMutation(
      context,
      () => repository.deleteWithUndo(task),
      failureMessage: 'Could not delete the to-do.',
    );
    if (!success || !mounted) return;
    UndoSnackbar.show(
      context,
      message: 'To-do deleted',
      service: ref.read(undoServiceProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attachmentCounts =
        ref.watch(attachmentCountsProvider).valueOrNull?.todos ??
        const <String, int>{};
    // Command Palette support
    ref.listen<CommandAction>(commandActionProvider, (previous, next) {
      if (next == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showTaskDialog();
        });
      } else if (next == CommandAction.newTaskForToday) {
        ref.read(commandActionProvider.notifier).clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final today = DayMath.dateOnly(AppClock.now());
          _showTaskDialog(initialDueDate: today, planForDay: today);
        });
      }
    });

    final projects =
        ref.watch(projectsStreamProvider).valueOrNull ?? const <ProjectModel>[];
    final projectNames = {for (final p in projects) p.id: p.name};

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

          _FilterBar(
            selected: _filter,
            onSelected: (filter) => setState(() => _filter = filter),
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
                            'Add a personal to-do. Project checklist items live under Projects.\n'
                            'You can also use Ctrl+K → New to-do',
                        buttonLabel: 'Add to-do',
                        onButtonPressed: _showTaskDialog,
                      );
                    }

                    final now = AppClock.now();
                    final roots = buildTaskTree(
                      tasks,
                      include: (task) => _filter.matches(task, now),
                    );
                    if (roots.isEmpty) {
                      return Center(
                        child: Text(
                          'No tasks match ${_filter.label}.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }

                    final showGroups = _filter == TaskFilter.all;
                    final scheduled = [
                      for (final node in roots)
                        if (TaskSchedule.isScheduled(node.task)) node,
                    ];
                    final unscheduled = [
                      for (final node in roots)
                        if (!TaskSchedule.isScheduled(node.task)) node,
                    ];

                    final children = <Widget>[];
                    if (showGroups && scheduled.isNotEmpty) {
                      children.add(const _GroupHeader('Scheduled'));
                      for (final node in scheduled) {
                        children.addAll(
                          _buildNode(
                            context,
                            node,
                            0,
                            projectNames,
                            attachmentCounts,
                          ),
                        );
                      }
                    }
                    if (showGroups && unscheduled.isNotEmpty) {
                      children.add(const _GroupHeader('Unscheduled'));
                      for (final node in unscheduled) {
                        children.addAll(
                          _buildNode(
                            context,
                            node,
                            0,
                            projectNames,
                            attachmentCounts,
                          ),
                        );
                      }
                    }
                    if (!showGroups) {
                      for (final node in roots) {
                        children.addAll(
                          _buildNode(
                            context,
                            node,
                            0,
                            projectNames,
                            attachmentCounts,
                          ),
                        );
                      }
                    }

                    return ListView(
                      padding: const EdgeInsets.all(12),
                      children: children,
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  /// Flattens a node and its expanded children into indented rows.
  List<Widget> _buildNode(
    BuildContext context,
    TaskNode node,
    int depth,
    Map<String, String> projectNames,
    Map<String, int> attachmentCounts,
  ) {
    final collapsed = _collapsed.contains(node.task.id);
    final result = <Widget>[
      Padding(
        padding: EdgeInsets.only(left: depth * 20.0),
        child: _TaskCard(
          task: node.task,
          depth: depth,
          projectName: projectNames[node.task.projectId],
          attachmentCount: attachmentCounts[node.task.id] ?? 0,
          hasChildren: node.hasChildren,
          collapsed: collapsed,
          onToggleExpanded: () => setState(() {
            if (!_collapsed.remove(node.task.id)) {
              _collapsed.add(node.task.id);
            }
          }),
          onToggleCompleted: (value) => _toggle(node.task, value),
          onEdit: () => _showTaskDialog(existing: node.task),
          onAddSubtask: () => _showTaskDialog(parent: node.task),
          onAddToMyDay: () => _addToMyDay(node.task),
          onDelete: () => _delete(node.task),
        ),
      ),
    ];
    if (!collapsed) {
      for (final child in node.children) {
        result.addAll(
          _buildNode(context, child, depth + 1, projectNames, attachmentCounts),
        );
      }
    }
    return result;
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelected});

  final TaskFilter selected;
  final ValueChanged<TaskFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final filter in TaskFilter.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(filter.label),
                selected: selected == filter,
                onSelected: (_) => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onPick,
    required this.onClear,
    this.helper,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        value == null
            ? 'No ${label.toLowerCase()}'
            : '$label: ${DateFormat('MMM dd, yyyy').format(value!)}',
      ),
      subtitle: helper == null ? null : Text(helper!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            IconButton(
              tooltip: 'Clear $label',
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
          const Icon(Icons.calendar_today),
        ],
      ),
      onTap: onPick,
    );
  }
}

class _ReminderField extends StatelessWidget {
  const _ReminderField({
    required this.value,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.notifications_outlined),
      title: Text(
        value == null
            ? 'No reminder'
            : 'Remind: ${DateFormat('MMM dd, yyyy · HH:mm').format(value!)}',
      ),
      trailing: value == null
          ? null
          : IconButton(
              tooltip: 'Clear reminder',
              icon: const Icon(Icons.clear),
              onPressed: onClear,
            ),
      onTap: onPick,
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.depth,
    required this.projectName,
    required this.attachmentCount,
    required this.hasChildren,
    required this.collapsed,
    required this.onToggleExpanded,
    required this.onToggleCompleted,
    required this.onEdit,
    required this.onAddSubtask,
    required this.onAddToMyDay,
    required this.onDelete,
  });

  final TodoItem task;
  final int depth;
  final String? projectName;
  final int attachmentCount;
  final bool hasChildren;
  final bool collapsed;
  final VoidCallback onToggleExpanded;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onEdit;
  final VoidCallback onAddSubtask;
  final VoidCallback onAddToMyDay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final priority = TaskPriority.fromStorage(task.priority);
    final tags = TaskTags.decode(task.tags);
    final repeats = Recurrence.isRecurring(task.recurrenceRule);
    final scheduled = TaskSchedule.isScheduled(task);
    final now = AppClock.now();
    final overdue = TaskSchedule.isOverdue(task, now);
    final dueLabel = task.dueDate == null
        ? null
        : 'Due: ${DateFormat('MMM dd, yyyy').format(task.dueDate!)}';
    final startLabel = task.startDate == null
        ? null
        : 'Starts: ${DateFormat('MMM dd, yyyy').format(task.startDate!)}';
    final reminder = task.reminderAt;
    final hasDetails =
        task.notes != null ||
        startLabel != null ||
        dueLabel != null ||
        reminder != null ||
        tags.isNotEmpty ||
        repeats ||
        projectName != null ||
        !scheduled;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: ListTile(
          leading: Checkbox(
            value: task.completed,
            onChanged: (val) => onToggleCompleted(val ?? false),
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
                    color: task.completed ? Colors.grey : null,
                  ),
                ),
              ),
              if (attachmentCount > 0)
                Semantics(
                  label:
                      '$attachmentCount attachment'
                      '${attachmentCount == 1 ? '' : 's'}',
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.attach_file,
                          size: 14,
                          color: Colors.grey,
                        ),
                        Text(
                          '$attachmentCount',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (overdue)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Text(
                    'Overdue',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: hasDetails
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (task.notes != null && task.notes!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            task.notesFormat == 'md1'
                                ? plainTextFromMd1(task.notes!, maxChars: 240)
                                : task.notes!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (startLabel != null) Text(startLabel),
                      if (dueLabel != null)
                        Text(
                          '$dueLabel'
                          '${repeats ? ' · ${Recurrence.label(task.recurrenceRule)}' : ''}',
                        ),
                      if (reminder != null)
                        Text(
                          'Reminder: '
                          '${DateFormat('MMM dd · HH:mm').format(reminder)}',
                        ),
                      if (!scheduled)
                        const Text(
                          'Unscheduled',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      if (projectName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              Chip(
                                avatar: const Icon(
                                  Icons.workspaces_outline,
                                  size: 14,
                                ),
                                label: Text(projectName!),
                                labelStyle: const TextStyle(fontSize: 11),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      if (tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              for (final tag in tags)
                                Chip(
                                  label: Text(tag),
                                  labelStyle: const TextStyle(fontSize: 11),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
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
              if (hasChildren)
                IconButton(
                  tooltip: collapsed ? 'Expand subtasks' : 'Collapse subtasks',
                  icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
                  onPressed: onToggleExpanded,
                ),
              PopupMenuButton<String>(
                tooltip: 'Task actions',
                onSelected: (value) {
                  switch (value) {
                    case 'myDay':
                      onAddToMyDay();
                      break;
                    case 'subtask':
                      onAddSubtask();
                      break;
                    case 'edit':
                      onEdit();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'myDay',
                    child: ListTile(
                      leading: Icon(Icons.wb_sunny_outlined),
                      title: Text('Add to My Day'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'subtask',
                    child: ListTile(
                      leading: Icon(Icons.subdirectory_arrow_right),
                      title: Text('Add subtask'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete, color: Colors.red),
                      title: Text('Delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
