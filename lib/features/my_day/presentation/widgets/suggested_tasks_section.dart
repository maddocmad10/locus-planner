import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/widgets/user_action_error.dart';
import '../../data/my_day_models.dart';
import '../../providers/my_day_providers.dart';

/// Tasks that might be worth planning. Nothing here enters the plan until the
/// user explicitly adds it.
class SuggestedTasksSection extends ConsumerStatefulWidget {
  const SuggestedTasksSection({super.key, required this.plan});

  final DailyPlanView plan;

  @override
  ConsumerState<SuggestedTasksSection> createState() =>
      _SuggestedTasksSectionState();
}

class _SuggestedTasksSectionState extends ConsumerState<SuggestedTasksSection> {
  static const _initialVisible = 6;
  bool _expanded = false;

  Future<void> _add(SuggestedTaskView task) async {
    final added = await runUserMutation(
      context,
      () =>
          ref.read(myDayControllerProvider).addSuggested(widget.plan.day, task),
      failureMessage: 'Could not add the task to My Day.',
    );
    if (!added || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Added “${task.title}”')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = widget.plan.suggestions;
    final visible = _expanded
        ? suggestions
        : suggestions.take(_initialVisible).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.lightbulb_outline,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 8),
                Text('Suggested tasks', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Overdue, due today, high-priority and undated tasks. Adding one '
              'is always your choice.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (suggestions.isEmpty)
              Text(
                'Nothing to suggest for this day.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final task in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              task.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Wrap(
                              spacing: 8,
                              children: [
                                _ReasonChip(reason: task.reason),
                                if (task.projectName != null)
                                  Text(
                                    task.projectName!,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                if (task.dueDate != null)
                                  Text(
                                    'Due ${DateFormat.MMMd().format(task.dueDate!)}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Add to My Day',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => _add(task),
                      ),
                    ],
                  ),
                ),
            if (suggestions.length > _initialVisible) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? 'Show fewer'
                      : 'Show ${suggestions.length - _initialVisible} more',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({required this.reason});

  final SuggestedReason reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (reason) {
      SuggestedReason.overdue => theme.colorScheme.error,
      SuggestedReason.dueToday => theme.colorScheme.primary,
      SuggestedReason.highPriority => theme.colorScheme.tertiary,
      SuggestedReason.noDate => theme.colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        reason.label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
