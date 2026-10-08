import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/domain/project_model.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_picker_range.dart';
import '../data/project_repository.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/hover_card.dart';
import '../../../core/widgets/user_action_error.dart';
import '../../../core/widgets/dispose_with.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(projectsStreamProvider);
    final progressAsync = ref.watch(projectProgressStreamProvider);
    ref.watch(dayChangeProvider); // so "overdue" updates at midnight
    final today = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _showAddEditProjectDialog(),
              icon: const Icon(Icons.add),
              label: const Text('New project'),
            ),
          ),
        ],
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load projects.')),
        data: (projects) {
          if (projects.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              title: 'No projects yet',
              subtitle: 'Create a project to track progress and tasks.',
              buttonLabel: 'Create Project',
              onButtonPressed: () => _showAddEditProjectDialog(),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1280
                  ? 3
                  : constraints.maxWidth >= 760
                      ? 2
                      : 1;
              final horizontalPadding = constraints.maxWidth >= 900 ? 24.0 : 16.0;
              final gap = 16.0;
              final cardWidth = (constraints.maxWidth -
                      horizontalPadding * 2 -
                      gap * (columns - 1)) /
                  columns;

              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  96,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                  mainAxisExtent: cardWidth >= 360 ? 236 : 252,
                ),
                itemCount: projects.length,
                itemBuilder: (context, index) {
                  final project = projects[index];
                  final progress =
                      (progressAsync.valueOrNull?[project.id] ?? 0.0)
                          .clamp(0.0, 100.0)
                          .toDouble();
                  return _ProjectCard(
                    today: today,
                    project: project,
                    progress: progress,
                    onTap: () => _showProjectDetail(project),
                    onEdit: () => _showAddEditProjectDialog(
                      existingProject: project,
                    ),
                    onDelete: () => _deleteProject(project),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ==================== ADD / EDIT PROJECT ====================
  void _showAddEditProjectDialog({ProjectModel? existingProject}) {
    final isEditing = existingProject != null;

    final nameController = TextEditingController(
      text: existingProject?.name ?? '',
    );
    final descController = TextEditingController(
      text: existingProject?.description ?? '',
    );
    DateTime? targetDate = existingProject?.targetDate;

    showDialog(
      context: context,
      builder: (context) => DisposeWith(
        disposables: [nameController, descController],
        child: StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Project' : 'Create New Project'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Project Name*',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(
                      targetDate == null
                          ? 'No target date set'
                          : 'Target Date: ${DateFormat('MMM dd, yyyy').format(targetDate!)}',
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      // The range must contain the current value: an overdue
                      // project's target is before today.
                      final range = datePickerRange(
                        current: targetDate,
                        today: ref.read(clockProvider)(),
                      );
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: range.initial,
                        firstDate: range.first,
                        lastDate: range.last,
                      );
                      if (picked != null) {
                        setDialogState(() => targetDate = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;

                  final repository = ref.read(projectRepositoryProvider);
                  final success = await runUserMutation(
                    context,
                    () async {
                      if (isEditing) {
                        await repository.update(
                          existingProject.copyWith(
                            name: nameController.text.trim(),
                            description: descController.text.trim().isEmpty
                                ? null
                                : descController.text.trim(),
                            targetDate: targetDate,
                          ),
                        );
                      } else {
                        await repository.create(
                          name: nameController.text.trim(),
                          description: descController.text.trim().isEmpty
                              ? null
                              : descController.text.trim(),
                          targetDate: targetDate,
                        );
                      }
                    },
                    failureMessage: isEditing
                        ? 'Could not save the project.'
                        : 'Could not create the project.',
                  );

                  if (!success || !context.mounted) return;
                  Navigator.pop(context);
                },
                child: Text(isEditing ? 'Update' : 'Create Project'),
              ),
            ],
          );
        },
      ),
          ),
    );
  }

  // ==================== DELETE PROJECT ====================
  Future<void> _deleteProject(ProjectModel project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text(
          'Delete "${project.name}" and all its tasks & progress logs?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final success = await runUserMutation(
        context,
        () => ref.read(projectRepositoryProvider).deleteWithUndo(project.id),
        failureMessage: 'Could not delete the project.',
      );
      if (success && mounted) {
        UndoSnackbar.show(
          context,
          message: 'Project deleted',
          service: ref.read(undoServiceProvider),
        );
      }
    }
  }

  // ==================== PROJECT DETAIL SHEET ====================
  void _showProjectDetail(ProjectModel project) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          project.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  if (project.description != null &&
                      project.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(project.description!),
                    ),

                  // ==================== TASKS SECTION ====================
                  const Text(
                    'Tasks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _TasksSection(projectId: project.id),

                  const SizedBox(height: 24),

                  // ==================== LOG PROGRESS SECTION ====================
                  const Text(
                    'Log Progress',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _ProgressLogSection(projectId: project.id),

                  const SizedBox(height: 24),

                  // ==================== PROGRESS HISTORY ====================
                  const Text(
                    'Progress History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _ProgressHistorySection(projectId: project.id),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

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
    final overdue = targetOnly != null &&
        targetOnly.isBefore(todayDate) &&
        progress < 100;

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
                    () => ref.read(projectRepositoryProvider).logProgress(
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
            ...logs.take(5).map(
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
