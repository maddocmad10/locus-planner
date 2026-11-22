part of '../mobile_app.dart';

/// Compact retry surface for shared files that did not become attachments.
/// Names come from the still-pending native manifest so a user can recognise
/// the file after an app restart.
class _ShareIntakeIssuesCard extends StatelessWidget {
  const _ShareIntakeIssuesCard({
    required this.issues,
    required this.onRetry,
    required this.onDiscard,
  });

  final List<ShareIntakeIssue> issues;
  final Future<void> Function() onRetry;
  final Future<void> Function(ShareIntakeIssue issue) onDiscard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = issues.take(5).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.attach_file,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Shared files need attention',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final issue in shown)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Icon(
                        issue.retryable
                            ? Icons.sync_problem
                            : Icons.error_outline,
                        size: 18,
                        color: issue.retryable
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issue.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              issue.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (issue.retryable)
                      TextButton(
                        onPressed: () => onRetry(),
                        child: const Text('Retry'),
                      ),
                    TextButton(
                      onPressed: () => onDiscard(issue),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              ),
            if (issues.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: Text(
                  '+${issues.length - shown.length} more',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (shown.any((issue) => issue.retryable))
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 4),
                child: Text(
                  'Retry only imports files that are still missing; existing '
                  'attachments are left unchanged.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
