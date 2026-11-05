import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/project_status.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/project_workflow_repository.dart';

Future<void> showStatusSettings({
  required BuildContext context,
  required String projectId,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _StatusSettingsDialog(projectId: projectId),
  );
}

class _StatusSettingsDialog extends ConsumerStatefulWidget {
  const _StatusSettingsDialog({required this.projectId});

  final String projectId;

  @override
  ConsumerState<_StatusSettingsDialog> createState() =>
      _StatusSettingsDialogState();
}

class _StatusSettingsDialogState extends ConsumerState<_StatusSettingsDialog> {
  final _controllers = <String, TextEditingController>{};
  final _colors = <String, String>{};
  List<ProjectStatus>? _ordered;
  bool _saving = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _load(List<ProjectStatus> statuses) {
    _ordered ??= [...statuses];
    for (final status in _ordered!) {
      _controllers.putIfAbsent(
        status.id,
        () => TextEditingController(text: status.name),
      );
      _colors.putIfAbsent(status.id, () => status.colorToken);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusesAsync = ref.watch(projectStatusesProvider(widget.projectId));
    return AlertDialog(
      title: const Text('Customize statuses'),
      content: SizedBox(
        width: 460,
        child: statusesAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => const Text('Could not load the statuses.'),
          data: (statuses) {
            _load(statuses);
            final ordered = _ordered!;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'The five status keys stay fixed for sync and backups. '
                    'Names, colours and order are local to this project.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  for (var index = 0; index < ordered.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Move up',
                            onPressed: index == 0
                                ? null
                                : () => setState(() {
                                    final item = ordered.removeAt(index);
                                    ordered.insert(index - 1, item);
                                  }),
                            icon: const Icon(Icons.arrow_upward, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Move down',
                            onPressed: index == ordered.length - 1
                                ? null
                                : () => setState(() {
                                    final item = ordered.removeAt(index);
                                    ordered.insert(index + 1, item);
                                  }),
                            icon: const Icon(Icons.arrow_downward, size: 18),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controllers[ordered[index].id],
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _colors[ordered[index].id],
                            items: [
                              for (final token
                                  in ProjectStatusCatalog.colorTokens)
                                DropdownMenuItem(
                                  value: token,
                                  child: _ColorDot(token: token),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(
                                  () => _colors[ordered[index].id] = value,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save changes'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final ordered = _ordered;
    if (ordered == null) return;
    setState(() => _saving = true);
    final repository = ref.read(projectWorkflowRepositoryProvider);
    final success = await runUserMutation(context, () async {
      for (final status in ordered) {
        await repository.updateStatus(
          status,
          name: _controllers[status.id]?.text,
          colorToken: _colors[status.id],
        );
      }
      await repository.reorderStatuses(widget.projectId, [
        for (final status in ordered) status.id,
      ]);
    }, failureMessage: 'Could not save the status settings.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) Navigator.pop(context);
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: projectStatusColor(context, token),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(token),
      ],
    );
  }
}

Color projectStatusColor(BuildContext context, String token) {
  final scheme = Theme.of(context).colorScheme;
  return switch (token) {
    'grey' => scheme.outline,
    'amber' => Colors.amber.shade700,
    'purple' => Colors.purple.shade400,
    'green' => Colors.green.shade600,
    'red' => scheme.error,
    'teal' => Colors.teal.shade500,
    _ => scheme.primary,
  };
}
