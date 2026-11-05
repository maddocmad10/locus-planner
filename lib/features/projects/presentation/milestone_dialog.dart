import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/project_workflow_repository.dart';

Future<void> showMilestoneEditor({
  required BuildContext context,
  required String projectId,
  ProjectMilestone? milestone,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _MilestoneEditorDialog(projectId: projectId, milestone: milestone),
  );
}

class _MilestoneEditorDialog extends ConsumerStatefulWidget {
  const _MilestoneEditorDialog({required this.projectId, this.milestone});

  final String projectId;
  final ProjectMilestone? milestone;

  @override
  ConsumerState<_MilestoneEditorDialog> createState() =>
      _MilestoneEditorDialogState();
}

class _MilestoneEditorDialogState
    extends ConsumerState<_MilestoneEditorDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  DateTime? _targetDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.milestone?.title ?? '');
    _description = TextEditingController(
      text: widget.milestone?.description ?? '',
    );
    _targetDate = widget.milestone?.targetDate;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.milestone != null;
    return AlertDialog(
      title: Text(editing ? 'Edit milestone' : 'New milestone'),
      content: SizedBox(
        width: 420,
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
              TextField(
                controller: _description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Target date',
                    border: const OutlineInputBorder(),
                    suffixIcon: _targetDate == null
                        ? const Icon(Icons.calendar_today_outlined, size: 18)
                        : IconButton(
                            tooltip: 'Clear target date',
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => _targetDate = null),
                          ),
                  ),
                  child: Text(
                    _targetDate == null
                        ? 'Not set'
                        : DateFormat('MMM d, yyyy').format(_targetDate!),
                    style: TextStyle(
                      color: _targetDate == null
                          ? Theme.of(context).hintColor
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (editing)
          TextButton(
            onPressed: _saving ? null : _delete,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(editing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final today = DayMath.dateOnly(AppClock.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? today,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _targetDate = DayMath.dateOnly(picked));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repository = ref.read(projectWorkflowRepositoryProvider);
    final milestone = widget.milestone;
    final success = await runUserMutation(context, () async {
      if (milestone == null) {
        await repository.addMilestone(
          projectId: widget.projectId,
          title: _title.text,
          description: _description.text,
          targetDate: _targetDate,
        );
      } else {
        await repository.updateMilestone(
          milestone,
          title: _title.text,
          description: _description.text,
          targetDate: _targetDate,
        );
      }
    }, failureMessage: 'Could not save the milestone.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final milestone = widget.milestone;
    if (milestone == null) return;
    final success = await runUserMutation(
      context,
      () => ref
          .read(projectWorkflowRepositoryProvider)
          .deleteMilestone(milestone),
      failureMessage: 'Could not delete the milestone.',
    );
    if (!success || !mounted) return;
    UndoSnackbar.show(
      context,
      message: 'Milestone deleted',
      service: ref.read(undoServiceProvider),
    );
    Navigator.pop(context);
  }
}
