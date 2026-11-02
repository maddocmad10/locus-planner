import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/utils/recurrence.dart';
import '../../data/my_day_models.dart';

/// Today's calendar events shown next to the plan. Occurrences are already
/// expanded by the shared agenda helper, so repeats appear on every day they
/// happen.
class DailySchedule extends StatelessWidget {
  const DailySchedule({super.key, required this.plan});

  final DailyPlanView plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.event_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Schedule', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text(
                  '${plan.events.length} event${plan.events.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (plan.events.isEmpty)
              Text('No events on this day.', style: theme.textTheme.bodySmall)
            else
              for (final entry in plan.events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 68,
                        child: Text(
                          DateFormat('h:mm a').format(entry.start),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.event.title),
                            if (entry.isRecurring)
                              Text(
                                Recurrence.label(entry.event.recurrenceRule),
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      if (entry.event.hasReminder)
                        const Icon(
                          Icons.notifications_active_outlined,
                          size: 18,
                        ),
                    ],
                  ),
                ),
            if (plan.events.isNotEmpty && plan.knownMinutes > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Events and planned tasks may overlap. Adjust the plan '
                      'if the day looks too full.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
