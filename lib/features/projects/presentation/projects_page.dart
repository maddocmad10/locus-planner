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

part 'projects_widgets.dart';

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
              final horizontalPadding = constraints.maxWidth >= 900
                  ? 24.0
                  : 16.0;
              final gap = 16.0;
              final cardWidth =
                  (constraints.maxWidth -
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
                    onEdit: () =>
                        _showAddEditProjectDialog(existingProject: project),
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
