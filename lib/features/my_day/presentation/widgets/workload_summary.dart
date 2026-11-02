import 'package:flutter/material.dart';

import '../../data/my_day_models.dart';

/// Planned workload. Only estimates the user provided are summed; unknown
/// durations are counted separately instead of being treated as zero.
class WorkloadSummary extends StatelessWidget {
  const WorkloadSummary({super.key, required this.plan});

  final DailyPlanView plan;

  /// A display reference, not an enforced capacity. My Day never blocks adding
  /// work; it only points out when the day looks unusually full.
  static const _referenceMinutes = 8 * 60;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final known = plan.knownMinutes;
    final unknown = plan.unknownEstimateCount;
    final overloaded = known > _referenceMinutes;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Workload', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(_durationLabel(known), style: theme.textTheme.headlineSmall),
            const SizedBox(height: 2),
            Text(
              'planned across ${plan.items.length} '
              'task${plan.items.length == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 6,
                value: known == 0
                    ? 0
                    : (known / _referenceMinutes).clamp(0.0, 1.0),
                color: overloaded
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            _SummaryRow(
              label: 'Completed',
              value:
                  '${plan.completedCount} task'
                  '${plan.completedCount == 1 ? '' : 's'}'
                  ' · ${_durationLabel(plan.completedMinutes)}',
            ),
            _SummaryRow(
              label: 'Unfinished',
              value:
                  '${plan.unfinishedCount} task'
                  '${plan.unfinishedCount == 1 ? '' : 's'}',
            ),
            if (unknown > 0)
              _SummaryRow(
                label: 'Unknown duration',
                value: '$unknown task${unknown == 1 ? '' : 's'}',
              ),
            _SummaryRow(label: 'Events', value: '${plan.events.length}'),
            if (overloaded) ...[
              const SizedBox(height: 8),
              Text(
                'More than 8 hours of planned work. Move something to another '
                'day if needed.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _durationLabel(int minutes) {
    if (minutes <= 0) return '0 min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest min';
    if (rest == 0) return '${hours}h';
    return '${hours}h ${rest}m';
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
