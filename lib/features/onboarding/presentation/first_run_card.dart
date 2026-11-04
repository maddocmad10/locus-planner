import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/navigation_provider.dart';
import '../data/onboarding_service.dart';

/// Local-first introduction shown on the dashboard while the database is empty
/// and the user has not dismissed it.
class FirstRunCard extends ConsumerWidget {
  const FirstRunCard({super.key});

  Future<void> _createSample(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(onboardingServiceProvider).createSampleData();
      ref.invalidate(shouldShowFirstRunProvider);
      if (!context.mounted) return;
      ref.read(navigationIndexProvider.notifier).setIndex(NavPage.myDay);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sample data added. Edit or delete anything you do not need.',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add sample data: $error')),
      );
    }
  }

  Future<void> _startBlank(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(onboardingServiceProvider).markComplete();
      ref.invalidate(shouldShowFirstRunProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dismiss the introduction: $error')),
      );
    }
  }

  void _openIcsImport(BuildContext context, WidgetRef ref) {
    ref.read(navigationIndexProvider.notifier).setIndex(NavPage.settings);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Open "Import Events from ICS" in Settings.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Welcome to Locus',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your planner data stays on this device. There is no account and '
              'no cloud. Optional LAN sync with the Android companion works '
              'only on your trusted local network.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _createSample(context, ref),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Create sample data'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _openIcsImport(context, ref),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Import .ics'),
                ),
                TextButton(
                  onPressed: () => _startBlank(context, ref),
                  child: const Text('Start blank'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
