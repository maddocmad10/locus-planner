import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/day_math.dart';
import '../../../../core/widgets/user_action_error.dart';
import '../../data/my_day_models.dart';
import '../../providers/my_day_providers.dart';

/// Summary card that opens the explicit end-of-day review. Unfinished tasks are
/// never carried forward automatically.
class EndOfDayReviewCard extends StatelessWidget {
  const EndOfDayReviewCard({super.key, required this.plan});

  final DailyPlanView plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = plan.items.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.nights_stay_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('End of day', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (hasItems)
                  Text(
                    '${plan.completedCount}/${plan.items.length} done',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasItems
                  ? 'Review what got done and decide what happens to the rest. '
                        'Nothing moves to tomorrow unless you say so.'
                  : 'Plan a few tasks and the review will appear here.',
              style: theme.textTheme.bodySmall,
            ),
            if (hasItems) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => showEndOfDayReview(context, plan),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Review unfinished tasks'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the review dialog. It watches the live plan so an action immediately
/// removes the row from the unfinished list.
Future<void> showEndOfDayReview(BuildContext context, DailyPlanView plan) {
  return showDialog<void>(
    context: context,
    builder: (_) => _EndOfDayReviewDialog(day: plan.day),
  );
}

class _EndOfDayReviewDialog extends ConsumerWidget {
  const _EndOfDayReviewDialog({required this.day});

  final DateTime day;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() action,
    String failure,
  ) {
    return runUserMutation(context, action, failureMessage: failure);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(myDayDayViewProvider(day));
    return AlertDialog(
      title: Text('Review ${DateFormat('EEEE, d MMMM').format(day)}'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: view.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Could not load: $error')),
          data: (plan) {
            final unfinished = plan.items.where((item) => !item.completed);
            final completed = plan.items.where((item) => item.completed);
            return ListView(
              children: [
                Text(
                  '${plan.completedCount} of ${plan.items.length} tasks completed'
                  '${plan.completedMinutes > 0 ? ' · ${plan.completedMinutes} min completed' : ''}',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 12),
                if (completed.isNotEmpty) ...[
                  Text('Completed', style: theme.textTheme.labelLarge),
                  for (final item in completed)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle, size: 20),
                      title: Text(
                        item.title,
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        item.plannedMinutes == null
                            ? 'Duration unknown'
                            : '${item.plannedMinutes} min',
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                Text('Unfinished', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                if (unfinished.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Everything planned for this day is done.',
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  for (final item in unfinished)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(item.title)),
                                if (item.plannedMinutes != null)
                                  Text(
                                    '${item.plannedMinutes} min',
                                    style: theme.textTheme.bodySmall,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _run(
                                    context,
                                    ref,
                                    () => ref
                                        .read(myDayControllerProvider)
                                        .moveToDay(
                                          item,
                                          DayMath.addDays(day, 1),
                                        ),
                                    'Could not move the task to tomorrow.',
                                  ),
                                  child: const Text('Move to tomorrow'),
                                ),
                                TextButton(
                                  onPressed: () => _run(
                                    context,
                                    ref,
                                    () => ref
                                        .read(myDayControllerProvider)
                                        .removeItem(item),
                                    'Could not remove the task from the plan.',
                                  ),
                                  child: const Text('Keep in backlog'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context)
                                      ..hideCurrentSnackBar()
                                      ..showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Left in today’s historical plan.',
                                          ),
                                        ),
                                      );
                                  },
                                  child: const Text('Leave as is'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                Text(
                  'Historical plans are kept. Moving a task only changes which '
                  'day you plan to work on it.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
