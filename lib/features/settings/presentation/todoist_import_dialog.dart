import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/domain/project_model.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/todoist_import_service.dart';
import '../../projects/data/project_repository.dart';
import '../../tasks/data/task_repository.dart';

class TodoistImportDialog extends ConsumerStatefulWidget {
  const TodoistImportDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const TodoistImportDialog(),
  );

  @override
  ConsumerState<TodoistImportDialog> createState() =>
      _TodoistImportDialogState();
}

class _TodoistImportDialogState extends ConsumerState<TodoistImportDialog> {
  List<ProjectModel> _projects = const [];
  String? _destinationId;
  String? _proposedProjectId;
  final _newProject = TextEditingController();
  TodoistPreview? _preview;
  String? _fileName;
  String? _csv;
  final Map<int, String> _decisions = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  @override
  void dispose() {
    _newProject.dispose();
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await ref.read(projectsStreamProvider.future);
      if (mounted) setState(() => _projects = projects);
    } catch (_) {
      // The picker still allows creating a new project.
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      dialogTitle: 'Select a Todoist project CSV',
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final csv = utf8.decode(bytes);
      if (!mounted) return;
      setState(() {
        _csv = csv;
        _fileName = picked!.files.single.name;
        _preview = null;
        _decisions.clear();
      });
      await _buildPreview();
    } catch (error) {
      _message('Could not read the CSV: $error');
    }
  }

  Future<void> _buildPreview() async {
    final csv = _csv;
    if (csv == null) return;
    final existing = _destinationId;
    final name = _newProject.text.trim();
    if ((existing == null || existing.isEmpty) && name.isEmpty) {
      _message('Choose a project or enter a new project name.');
      return;
    }
    final proposedId = existing == null || existing.isEmpty
        ? (_proposedProjectId ??= const Uuid().v4())
        : null;
    setState(() => _busy = true);
    try {
      final preview =
          await TodoistImportService(
            ref.read(databaseProvider),
            ref.read(taskRepositoryProvider),
          ).preview(
            fileName: _fileName ?? 'todoist.csv',
            csv: csv,
            destinationId: existing,
            proposedProjectId: proposedId,
            proposedProjectName: proposedId == null ? null : name,
          );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _decisions.clear();
        for (final row in preview.rows) {
          if (row.disposition == TodoistDisposition.review) {
            _decisions[row.rowNumber] = row.candidateTargetId == null
                ? 'skip'
                : 'reuse';
          }
        }
      });
    } catch (error) {
      _message('Could not preview the CSV: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commit() async {
    final preview = _preview;
    if (preview == null) return;
    final existing = _destinationId;
    final name = _newProject.text.trim();
    final destination = existing == null || existing.isEmpty
        ? _proposedProjectId
        : existing;
    if (destination == null) return;
    if (existing == null || existing.isEmpty) {
      if (name.isEmpty) {
        _message('Name the new destination project.');
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final result =
          await TodoistImportService(
            ref.read(databaseProvider),
            ref.read(taskRepositoryProvider),
          ).commit(
            preview: preview,
            destinationId: destination,
            decisions: _decisions,
          );
      await _loadProjects();
      if (!mounted) return;
      if (existing == null || existing.isEmpty) {
        setState(() => _destinationId = result.destinationId);
      }
      _message(
        'Imported ${result.imported} task${result.imported == 1 ? '' : 's'}; '
        'skipped ${result.skipped}.',
      );
      Navigator.pop(context);
    } catch (error) {
      _message('Import failed; the project was left unchanged. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Import Todoist CSV'),
      content: SizedBox(
        width: 640,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Imported tasks use the normal task list, hierarchy, notes, due '
              'dates, priority and a project link. Nothing is written until '
              'you approve the preview.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _destinationId,
                    decoration: const InputDecoration(
                      labelText: 'Destination project',
                    ),
                    items: [
                      for (final project in _projects)
                        DropdownMenuItem(
                          value: project.id,
                          child: Text(project.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _destinationId = value),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _newProject,
                    decoration: const InputDecoration(
                      labelText: 'Or create a new project',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: Text(_fileName ?? 'Choose CSV'),
                ),
                const SizedBox(width: 12),
                if (_csv != null)
                  TextButton(
                    onPressed: _busy ? null : _buildPreview,
                    child: const Text('Preview'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (preview != null)
              Text(
                '${preview.importable} import · ${preview.review} review · '
                '${preview.skipped} skip · ${preview.errors} error'
                '${preview.missingColumns.isEmpty ? '' : ' · missing ${preview.missingColumns.join(', ')}'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Expanded(
              child: preview == null
                  ? const Center(child: Text('Choose a CSV to preview it.'))
                  : ListView.builder(
                      itemCount: preview.rows.length,
                      itemBuilder: (context, index) {
                        final row = preview.rows[index];
                        final review =
                            row.disposition == TodoistDisposition.review;
                        return ListTile(
                          dense: true,
                          leading: Icon(switch (row.disposition) {
                            TodoistDisposition.import => Icons.check_circle,
                            TodoistDisposition.skip => Icons.remove_circle,
                            TodoistDisposition.review => Icons.help_outline,
                            TodoistDisposition.error => Icons.error_outline,
                          }),
                          title: Text(
                            row.content.isEmpty ? '(no content)' : row.content,
                          ),
                          subtitle: Text(
                            [
                              if (row.parentRow != null)
                                'under row ${row.parentRow}',
                              if (row.dueDate != null)
                                'due ${row.dueDate!.toIso8601String().split('T').first}',
                              if (row.reason != null) row.reason!,
                              if (row.candidateTargetId != null)
                                'candidate ${row.candidateTargetId}',
                            ].join(' · '),
                          ),
                          trailing: review
                              ? DropdownButton<String>(
                                  value: _decisions[row.rowNumber] ?? 'skip',
                                  items: [
                                    if (row.candidateTargetId != null)
                                      const DropdownMenuItem(
                                        value: 'reuse',
                                        child: Text('Use existing match'),
                                      ),
                                    const DropdownMenuItem(
                                      value: 'create',
                                      child: Text('Create separately'),
                                    ),
                                    const DropdownMenuItem(
                                      value: 'skip',
                                      child: Text('Skip'),
                                    ),
                                  ],
                                  onChanged: (value) => setState(() {
                                    _decisions[row.rowNumber] = value ?? 'skip';
                                  }),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || preview == null ? null : _commit,
          child: Text(_busy ? 'Working…' : 'Import approved rows'),
        ),
      ],
    );
  }
}
