part of 'projects_page.dart';

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.today,
    required this.project,
    required this.progress,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final DateTime today;
  final ProjectModel project;
  final double progress;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final targetDate = project.targetDate;
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetOnly = targetDate == null
        ? null
        : DateTime(targetDate.year, targetDate.month, targetDate.day);
    final goal = project.targetProgress.clamp(0, 100);
    final overdue =
        targetOnly != null && targetOnly.isBefore(todayDate) && progress < goal;
    final done = progress >= goal;

    return HoverCard(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    project.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Project actions',
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (project.description != null &&
                project.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                project.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ] else
              const SizedBox(height: 8),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress / 100,
                        strokeWidth: 5,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${progress.toStringAsFixed(0)}%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        done
                            ? 'Checklist complete'
                            : '${progress.toStringAsFixed(0)}% of $goal%',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          value: progress / 100,
                          minHeight: 6,
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                  size: 16,
                  color: overdue
                      ? colorScheme.error
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    targetDate == null
                        ? 'No target date'
                        : overdue
                        ? 'Overdue · ${DateFormat('MMM d').format(targetDate)}'
                        : 'Target · ${DateFormat('MMM d').format(targetDate)}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdue
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                      fontWeight: overdue ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== TASKS WIDGET ====================
class _TasksSection extends ConsumerStatefulWidget {
  final String projectId;

  const _TasksSection({required this.projectId});

  @override
  ConsumerState<_TasksSection> createState() => _TasksSectionState();
}

enum _ProjectView { list, board, timeline }

class _TasksSectionState extends ConsumerState<_TasksSection> {
  final TextEditingController _taskController = TextEditingController();
  _ProjectView _view = _ProjectView.list;

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  Future<void> _toggle(Task task, bool value) async {
    await runUserMutation(
      context,
      () => ref.read(projectWorkflowRepositoryProvider).toggleTask(task, value),
      failureMessage: 'Could not update the checklist item.',
    );
  }

  Future<void> _move(Task task, String statusKey) async {
    await runUserMutation(
      context,
      () => ref
          .read(projectWorkflowRepositoryProvider)
          .moveTaskToStatus(task, statusKey),
      failureMessage: 'Could not move the task.',
    );
  }

  void _openTask(Task task) {
    showProjectTaskEditor(
      context: context,
      projectId: widget.projectId,
      task: task,
    );
  }

  void _openMilestone(ProjectMilestone milestone) {
    showMilestoneEditor(
      context: context,
      projectId: widget.projectId,
      milestone: milestone,
    );
  }

  void _setView(_ProjectView view) {
    setState(() => _view = view);
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final tasks = ref.watch(projectTasksProvider(projectId));
    final statusesAsync = ref.watch(projectStatusesProvider(projectId));
    final dependenciesAsync = ref.watch(projectDependenciesProvider(projectId));
    final milestonesAsync = ref.watch(projectMilestonesProvider(projectId));
    final repository = ref.read(projectRepositoryProvider);
    final statuses = statusesAsync.valueOrNull ?? const <ProjectStatus>[];
    final dependencies =
        dependenciesAsync.valueOrNull ?? const <TaskDependency>[];
    final milestones =
        milestonesAsync.valueOrNull ?? const <ProjectMilestone>[];
    final statusByKey = {
      for (final status in statuses) status.statusKey: status,
    };

    return Column(
      children: [
        Row(
          children: [
            Text('Checklist', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: 'Customize statuses',
              icon: const Icon(Icons.tune, size: 20),
              onPressed: () =>
                  showStatusSettings(context: context, projectId: projectId),
            ),
            _ViewButton(
              tooltip: 'List view',
              icon: Icons.view_list_outlined,
              selected: _view == _ProjectView.list,
              onPressed: () => _setView(_ProjectView.list),
            ),
            _ViewButton(
              tooltip: 'Kanban board',
              icon: Icons.view_kanban_outlined,
              selected: _view == _ProjectView.board,
              onPressed: () => _setView(_ProjectView.board),
            ),
            _ViewButton(
              tooltip: 'Timeline',
              icon: Icons.timeline_outlined,
              selected: _view == _ProjectView.timeline,
              onPressed: () => _setView(_ProjectView.timeline),
            ),
          ],
        ),
        tasks.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Could not load the checklist.'),
          data: (items) {
            final blockedSuccessors = {
              for (final dependency in dependencies)
                if (items
                        .where(
                          (task) => task.id == dependency.predecessorTaskId,
                        )
                        .firstOrNull
                        ?.completed ==
                    false)
                  dependency.successorTaskId,
            };
            return switch (_view) {
              _ProjectView.list => Card(
                child: items.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No checklist items yet.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0) const Divider(height: 1),
                            _ProjectTaskTile(
                              task: items[i],
                              status: statusByKey[items[i].statusKey],
                              blocked: blockedSuccessors.contains(items[i].id),
                              onToggle: (value) => _toggle(items[i], value),
                              onOpen: () => _openTask(items[i]),
                            ),
                          ],
                        ],
                      ),
              ),
              _ProjectView.board => _KanbanBoard(
                statuses: statuses,
                tasks: items,
                blockedSuccessors: blockedSuccessors,
                onMove: _move,
                onToggle: _toggle,
                onOpen: _openTask,
              ),
              _ProjectView.timeline => ProjectTimeline(
                tasks: items,
                milestones: milestones,
                dependencies: dependencies,
                statuses: statuses,
                onOpenTask: _openTask,
                onOpenMilestone: _openMilestone,
              ),
            };
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  decoration: const InputDecoration(
                    hintText: 'Add project task...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) async {
                    final title = value.trim();
                    if (title.isEmpty) return;
                    final success = await runUserMutation(
                      context,
                      () => repository.addTask(
                        projectId: projectId,
                        title: title,
                      ),
                      failureMessage: 'Could not add the checklist item.',
                    );
                    if (!success || !mounted) return;
                    _taskController.clear();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? scheme.primary.withValues(alpha: 0.12)
            : null,
        foregroundColor: selected ? scheme.primary : null,
      ),
      onPressed: onPressed,
    );
  }
}

class _ProjectTaskTile extends StatelessWidget {
  const _ProjectTaskTile({
    required this.task,
    required this.status,
    required this.blocked,
    required this.onToggle,
    required this.onOpen,
  });

  final Task task;
  final ProjectStatus? status;
  final bool blocked;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final due = task.dueDate;
    final overdue =
        due != null &&
        DayMath.dateOnly(due).isBefore(DayMath.dateOnly(AppClock.now())) &&
        !task.completed;
    final priority = TaskPriority.fromStorage(task.priority);
    final details = <String>[
      if (status != null) status!.name,
      if (due != null)
        '${overdue ? 'Overdue' : 'Due'} ${DateFormat('MMM d').format(due)}',
      if (task.estimatedMinutes != null) '${task.estimatedMinutes} min',
      if (priority != TaskPriority.none) priority.label,
      if (blocked) 'Blocked',
    ];
    return ListTile(
      dense: true,
      leading: Checkbox(
        value: task.completed,
        onChanged: (value) => onToggle(value ?? false),
      ),
      title: Text(
        task.title,
        style: task.completed
            ? const TextStyle(
                decoration: TextDecoration.lineThrough,
                color: Colors.grey,
              )
            : null,
      ),
      subtitle: Text(
        details.join(' · '),
        style: TextStyle(
          fontSize: 11,
          color: overdue ? theme.colorScheme.error : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blocked)
            Tooltip(
              message: 'Waiting for a predecessor task',
              child: Icon(
                Icons.link_off,
                size: 16,
                color: theme.colorScheme.error,
              ),
            ),
          if (status != null) ...[
            const SizedBox(width: 6),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: projectStatusColor(context, status!.colorToken),
                shape: BoxShape.circle,
              ),
            ),
          ],
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Edit task',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onOpen,
          ),
        ],
      ),
      onTap: onOpen,
    );
  }
}

class _KanbanBoard extends StatelessWidget {
  const _KanbanBoard({
    required this.statuses,
    required this.tasks,
    required this.blockedSuccessors,
    required this.onMove,
    required this.onToggle,
    required this.onOpen,
  });

  final List<ProjectStatus> statuses;
  final List<Task> tasks;
  final Set<String> blockedSuccessors;
  final Future<void> Function(Task task, String statusKey) onMove;
  final Future<void> Function(Task task, bool value) onToggle;
  final ValueChanged<Task> onOpen;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Loading workflow statuses...'),
      );
    }
    return SizedBox(
      height: 360,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final status in statuses) ...[
              _KanbanColumn(
                status: status,
                tasks:
                    tasks
                        .where((task) => task.statusKey == status.statusKey)
                        .toList()
                      ..sort((a, b) {
                        final byOrder = a.sortOrder.compareTo(b.sortOrder);
                        return byOrder != 0
                            ? byOrder
                            : a.title.toLowerCase().compareTo(
                                b.title.toLowerCase(),
                              );
                      }),
                blockedSuccessors: blockedSuccessors,
                onMove: onMove,
                onToggle: onToggle,
                onOpen: onOpen,
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({
    required this.status,
    required this.tasks,
    required this.blockedSuccessors,
    required this.onMove,
    required this.onToggle,
    required this.onOpen,
  });

  final ProjectStatus status;
  final List<Task> tasks;
  final Set<String> blockedSuccessors;
  final Future<void> Function(Task task, String statusKey) onMove;
  final Future<void> Function(Task task, bool value) onToggle;
  final ValueChanged<Task> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = projectStatusColor(context, status.colorToken);
    return DragTarget<Task>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onMove(details.data, status.statusKey),
      builder: (context, candidates, rejected) {
        return Container(
          width: 228,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: candidates.isEmpty
                  ? Colors.transparent
                  : color.withValues(alpha: 0.7),
              width: 2,
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${status.name} (${tasks.length})',
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: tasks.isEmpty
                    ? Center(
                        child: Text(
                          'Drop tasks here',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: tasks.length,
                        itemBuilder: (context, index) {
                          final task = tasks[index];
                          final card = _KanbanCard(
                            task: task,
                            blocked: blockedSuccessors.contains(task.id),
                            onToggle: (value) => onToggle(task, value),
                            onOpen: () => onOpen(task),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: LongPressDraggable<Task>(
                              data: task,
                              feedback: Material(
                                elevation: 6,
                                borderRadius: BorderRadius.circular(10),
                                child: SizedBox(width: 210, child: card),
                              ),
                              childWhenDragging: Opacity(
                                opacity: 0.35,
                                child: card,
                              ),
                              child: card,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({
    required this.task,
    required this.blocked,
    required this.onToggle,
    required this.onOpen,
  });

  final Task task;
  final bool blocked;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final priority = TaskPriority.fromStorage(task.priority);
    final due = task.dueDate;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: task.completed,
                      onChanged: (value) => onToggle(value ?? false),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: task.completed
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              if (due != null || priority != TaskPriority.none || blocked)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 4),
                  child: Row(
                    children: [
                      if (due != null)
                        Text(
                          DateFormat('MMM d').format(due),
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      if (priority != TaskPriority.none) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.flag,
                          size: 12,
                          color: priority == TaskPriority.high
                              ? Colors.red
                              : Colors.amber.shade700,
                        ),
                      ],
                      if (blocked) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.link_off, size: 12),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== MILESTONES ====================
class _MilestonesSection extends ConsumerWidget {
  const _MilestonesSection({required this.projectId});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final milestones = ref.watch(projectMilestonesProvider(projectId));
    return milestones.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => const Text('Could not load milestones.'),
      data: (items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'No milestones yet. Add a checkpoint for a date that matters.',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        leading: Checkbox(
                          value: items[i].completedAt != null,
                          onChanged: (value) async {
                            await runUserMutation(
                              context,
                              () => ref
                                  .read(projectWorkflowRepositoryProvider)
                                  .setMilestoneCompleted(
                                    items[i],
                                    value ?? false,
                                  ),
                              failureMessage: 'Could not update the milestone.',
                            );
                          },
                        ),
                        title: Text(
                          items[i].title,
                          style: items[i].completedAt == null
                              ? null
                              : const TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: Colors.grey,
                                ),
                        ),
                        subtitle: Text(
                          [
                            if (items[i].targetDate != null)
                              'Target ${DateFormat('MMM d, yyyy').format(items[i].targetDate!)}',
                            if (items[i].description != null)
                              items[i].description!,
                          ].join(' · '),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit milestone',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () => showMilestoneEditor(
                            context: context,
                            projectId: projectId,
                            milestone: items[i],
                          ),
                        ),
                        onTap: () => showMilestoneEditor(
                          context: context,
                          projectId: projectId,
                          milestone: items[i],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    showMilestoneEditor(context: context, projectId: projectId),
                icon: const Icon(Icons.add),
                label: const Text('Add milestone'),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ==================== LOG PROGRESS WIDGET ====================
class _ProgressLogSection extends ConsumerStatefulWidget {
  final String projectId;

  const _ProgressLogSection({required this.projectId});

  @override
  ConsumerState<_ProgressLogSection> createState() =>
      _ProgressLogSectionState();
}

class _ProgressLogSectionState extends ConsumerState<_ProgressLogSection> {
  final valueController = TextEditingController();
  final noteController = TextEditingController();

  @override
  void dispose() {
    valueController.dispose();
    noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Notes only. This journal does not change the checklist percentage.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valueController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Journal value (0-100)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  final value = int.tryParse(valueController.text);
                  if (value == null || value < 0 || value > 100) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Please enter a number between 0 and 100',
                        ),
                      ),
                    );
                    return;
                  }

                  final success = await runUserMutation(
                    context,
                    () => ref
                        .read(projectRepositoryProvider)
                        .logProgress(
                          projectId: widget.projectId,
                          value: value,
                          note: noteController.text.trim().isEmpty
                              ? null
                              : noteController.text.trim(),
                        ),
                    failureMessage: 'Could not save the progress note.',
                  );

                  if (!success || !context.mounted) return;
                  valueController.clear();
                  noteController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Progress note saved')),
                  );
                },
                child: const Text('Save note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== PROGRESS HISTORY + CHART ====================
class _ProgressHistorySection extends ConsumerWidget {
  final String projectId;

  const _ProgressHistorySection({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(projectProgressLogsProvider(projectId));

    return logsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Text('Could not load progress history.'),
      data: (logs) {
        if (logs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No progress logged yet.',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final spots = logs.reversed.toList().asMap().entries.map((entry) {
          return FlSpot(entry.key.toDouble(), entry.value.value.toDouble());
        }).toList();

        return Column(
          children: [
            SizedBox(
              height: 180,
              child: LineChart(
                LineChartData(
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Theme.of(context).colorScheme.primary,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                    ),
                  ],
                  titlesData: const FlTitlesData(show: false),
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ...logs
                .take(5)
                .map(
                  (log) => ListTile(
                    leading: CircleAvatar(child: Text('${log.value}%')),
                    title: Text(log.note ?? 'Progress update'),
                    subtitle: Text(
                      DateFormat('MMM dd, hh:mm a').format(log.timestamp),
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
