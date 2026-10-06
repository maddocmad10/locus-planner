import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/service_providers.dart';
import '../../diary/data/diary_repository.dart';
import '../providers/dashboard_providers.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  Future<void> _showReview(BuildContext context, WidgetRef ref) async {
    final winCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final tomorrowCtrl = TextEditingController();

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('End of Day Review'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: winCtrl,
                  decoration: const InputDecoration(labelText: '1 win today?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: blockCtrl,
                  decoration: const InputDecoration(labelText: '1 blocker?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tomorrowCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Top 1 priority for tomorrow?',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await ref.read(diaryRepositoryProvider).saveReview(
                  win: winCtrl.text.trim(),
                  blocker: blockCtrl.text.trim(),
                  tomorrow: tomorrowCtrl.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                await ref.read(notificationServiceProvider).showNow(
                  title: 'Review Saved',
                  body: 'Saved to diary',
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved to diary. Great job!')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      winCtrl.dispose();
      blockCtrl.dispose();
      tomorrowCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final events = ref.watch(todayEventsProvider);
    final projects = ref.watch(activeProjectsProvider);
    final progress = ref.watch(projectProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _showReview(context, ref),
              icon: const Icon(Icons.nightlight_round),
              label: const Text('End of Day Review'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          stats.when(
            loading: () => const _DashboardLoading(height: 100),
            error: (_, _) => const _DashboardError(),
            data: (data) => Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _StatCard(
                  title: 'Focus Today',
                  value: '${data.focusMinutes} min',
                  icon: Icons.timer_outlined,
                ),
                _StatCard(
                  title: 'Active Habits',
                  value: '${data.habitsTotal}',
                  icon: Icons.check_circle_outline,
                ),
                _StatCard(
                  title: 'Events Today',
                  value: '${data.eventsToday}',
                  icon: Icons.event_outlined,
                ),
                _StatCard(
                  title: 'Diary Streak',
                  value: '${data.diaryStreak} days',
                  icon: Icons.local_fire_department_outlined,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Text(
            "Today's Schedule",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          events.when(
            loading: () => const _DashboardLoading(height: 100),
            error: (_, _) => const _DashboardError(),
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No events scheduled for today. Add some in the Events tab.',
                    ),
                  ),
                );
              }
              return Column(
                children: items.map((occurrence) {
                  final event = occurrence.event;
                  final time = occurrence.start;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(event.title),
                      subtitle: Text(
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} • ${event.category}',
                      ),
                      trailing: event.hasReminder
                          ? const Icon(Icons.notifications_active, color: Colors.orange)
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 32),
          Text(
            'Active Projects',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          projects.when(
            loading: () => const _DashboardLoading(height: 180),
            error: (_, _) => const _DashboardError(),
            data: (items) {
              final visible = items.take(4).toList();
              if (visible.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No projects yet. Create one in the Projects tab.'),
                  ),
                );
              }
              final values = progress.valueOrNull ?? const <String, double>{};
              return Column(
                children: visible.map((project) {
                  final percent = values[project.id] ?? 0.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          if (project.description?.isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 4, bottom: 8),
                              child: Text(project.description!, style: const TextStyle(color: Colors.grey)),
                            ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (percent / 100).clamp(0.0, 1.0),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${percent.toStringAsFixed(0)}% complete'),
                              if (project.targetDate != null)
                                Text(
                                  'Target: ${project.targetDate!.day}/${project.targetDate!.month}/${project.targetDate!.year}',
                                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DashboardLoading extends StatelessWidget {
  const _DashboardLoading({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: const Center(child: CircularProgressIndicator()),
      );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Could not load dashboard data.'),
        ),
      );
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
