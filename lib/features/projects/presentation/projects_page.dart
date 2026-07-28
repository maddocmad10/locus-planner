import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/widgets/empty_state.dart';

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditProjectDialog(),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Project>>(
        stream: db.watchProjects(),
        builder: (context, snapshot) {
          final projects = snapshot.data ?? [];

          if (projects.isEmpty) {
            return EmptyState(
  icon: Icons.folder_outlined,
  title: 'No projects yet',
  subtitle: 'Create a project to track progress and tasks.',
  buttonLabel: 'Create Project',
  onButtonPressed: () => _showAddEditProjectDialog(),
);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return FutureBuilder<double>(
                future: db.projectProgressPercent(project.id),
                builder: (context, progressSnapshot) {
                  final progress = progressSnapshot.data ?? 0.0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    child: InkWell(
                      onTap: () => _showProjectDetail(project),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    project.name,
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 20),
                                  onPressed: () => _showAddEditProjectDialog(existingProject: project),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                  onPressed: () => _deleteProject(project),
                                ),
                              ],
                            ),
                            if (project.description != null && project.description!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 12),
                                child: Text(project.description!, style: const TextStyle(color: Colors.grey)),
                              ),
                            LinearProgressIndicator(
                              value: progress / 100,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${progress.toStringAsFixed(0)}% complete'),
                                if (project.targetDate != null)
                                  Text(
                                    'Target: ${DateFormat('MMM dd').format(project.targetDate!)}',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
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
  void _showAddEditProjectDialog({Project? existingProject}) {
    final isEditing = existingProject != null;

    final nameController = TextEditingController(text: existingProject?.name ?? '');
    final descController = TextEditingController(text: existingProject?.description ?? '');
    DateTime? targetDate = existingProject?.targetDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Project' : 'Create New Project'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Project Name*'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    title: Text(targetDate == null
                        ? 'No target date set'
                        : 'Target Date: ${DateFormat('MMM dd, yyyy').format(targetDate!)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: targetDate ?? DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2035),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty) return;

                  final db = ref.read(databaseProvider);

                  if (isEditing && existingProject != null) {
                    await (db.update(db.projects)
                          ..where((t) => t.id.equals(existingProject.id)))
                        .write(ProjectsCompanion(
                      name: drift.Value(nameController.text.trim()),
                      description: drift.Value(descController.text.trim()),
                      targetDate: drift.Value(targetDate),
                    ));
                  } else {
                    await db.into(db.projects).insert(ProjectsCompanion(
                      id: drift.Value(Uuid().v4()),
                      name: drift.Value(nameController.text.trim()),
                      description: drift.Value(descController.text.trim()),
                      createdAt: drift.Value(DateTime.now()),
                      targetDate: drift.Value(targetDate),
                    ));
                  }
                  Navigator.pop(context);
                },
                child: Text(isEditing ? 'Update' : 'Create Project'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== DELETE PROJECT ====================
  Future<void> _deleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Project?'),
        content: Text('Delete "${project.name}" and all its tasks & progress logs?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await db.deleteProject(project.id);
    }
  }

  // ==================== PROJECT DETAIL SHEET ====================
  void _showProjectDetail(Project project) {
    final db = ref.read(databaseProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                      Expanded(child: Text(project.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  if (project.description != null && project.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(project.description!),
                    ),

                  // ==================== TASKS SECTION ====================
                  const Text('Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _TasksSection(projectId: project.id),

                  const SizedBox(height: 24),

                  // ==================== LOG PROGRESS SECTION ====================
                  const Text('Log Progress', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _ProgressLogSection(projectId: project.id),

                  const SizedBox(height: 24),

                  // ==================== PROGRESS HISTORY ====================
                  const Text('Progress History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

// ==================== TASKS WIDGET ====================
class _TasksSection extends ConsumerWidget {
  final String projectId;

  const _TasksSection({required this.projectId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Column(
      children: [
        StreamBuilder<List<Task>>(
          stream: db.watchTasksForProject(projectId),
          builder: (context, snapshot) {
            final tasks = snapshot.data ?? [];

            return Column(
              children: tasks.map((task) {
                return CheckboxListTile(
                  title: Text(task.title),
                  value: task.completed,
                  onChanged: (val) async {
                    await db.toggleTask(task.id, val ?? false);
                  },
                );
              }).toList(),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Add new task...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) async {
                    if (value.trim().isNotEmpty) {
                      final db = ref.read(databaseProvider);
                      await db.addTask(projectId, value.trim());
                    }
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
  ConsumerState<_ProgressLogSection> createState() => _ProgressLogSectionState();
}

class _ProgressLogSectionState extends ConsumerState<_ProgressLogSection> {
  final valueController = TextEditingController();
  final noteController = TextEditingController();

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
                      const SnackBar(content: Text('Please enter a number between 0 and 100')),
                    );
                    return;
                  }

                  final db = ref.read(databaseProvider);
                  await db.logProjectProgress(
                    widget.projectId,
                    value,
                    noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                  );

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
    final db = ref.watch(databaseProvider);

    return FutureBuilder<List<ProgressLog>>(
      future: db.getProgressLogs(projectId),
      builder: (context, snapshot) {
        final logs = snapshot.data ?? [];

        if (logs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No progress logged yet.', style: TextStyle(color: Colors.grey)),
          );
        }

        // Prepare data for chart
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
            ...logs.take(5).map((log) => ListTile(
                  leading: CircleAvatar(child: Text('${log.value}%')),
                  title: Text(log.note ?? 'Progress update'),
                  subtitle: Text(DateFormat('MMM dd, hh:mm a').format(log.timestamp)),
                )),
          ],
        );
      },
    );
  }
}
