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
    final overdue =
        targetOnly != null && targetOnly.isBefore(todayDate) && progress < 100;

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
                        progress >= 100 ? 'Completed' : 'In progress',
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

class _TasksSectionState extends ConsumerState<_TasksSection> {
  final TextEditingController _taskController = TextEditingController();

  @override
  void dispose() {
    _taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final projectId = widget.projectId;
    final tasks = ref.watch(projectTasksProvider(projectId));
    final repository = ref.read(projectRepositoryProvider);

    return Column(
      children: [
        tasks.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Could not load tasks.'),
          data: (items) => Column(
            children: items.map((task) {
              return CheckboxListTile(
                title: Text(task.title),
                value: task.completed,
                onChanged: (val) async {
                  await runUserMutation(
                    context,
                    () => repository.toggleTask(task, val ?? false),
                    failureMessage: 'Could not update the project task.',
                  );
                },
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _taskController,
                  decoration: const InputDecoration(
                    hintText: 'Add new task...',
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
                      failureMessage: 'Could not add the project task.',
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
            TextField(
              controller: valueController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Progress Value (0-100)',
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
                    failureMessage: 'Could not log project progress.',
                  );

                  if (!success || !context.mounted) return;
                  valueController.clear();
                  noteController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Progress logged!')),
                  );
                },
                child: const Text('Log Progress'),
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
