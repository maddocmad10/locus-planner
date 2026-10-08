import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/hover_card.dart';
import '../../../core/widgets/dispose_with.dart';
import '../../diary/data/diary_repository.dart';
import '../providers/dashboard_providers.dart';

part 'dashboard_widgets.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  Future<void> _showReview(BuildContext context, WidgetRef ref) async {
    final winCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final tomorrowCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => DisposeWith(
        disposables: [winCtrl, blockCtrl, tomorrowCtrl],
        child: AlertDialog(
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
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(dashboardStatsProvider);
    final events = ref.watch(todayEventsProvider);
    final projects = ref.watch(activeProjectsProvider);
    final progress = ref.watch(projectProgressProvider);
    final now = ref.watch(clockProvider)();

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final horizontal = compact ? 20.0 : 28.0;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
            children: [
              _Greeting(now: now),
              const SizedBox(height: 20),
              stats.when(
                loading: () => const _DashboardLoading(height: 240),
                error: (_, _) => const _DashboardError(),
                data: (data) => _DashboardBento(
                  data: data,
                  compact: compact,
                ),
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                title: "Today's timeline",
                subtitle: 'What is on deck next',
              ),
              const SizedBox(height: 12),
              events.when(
                loading: () => const _DashboardLoading(height: 160),
                error: (_, _) => const _DashboardError(),
                data: (items) {
                  if (items.isEmpty) {
                    return const _EmptyCard(
                      icon: Icons.event_available_outlined,
                      message:
                          'No events scheduled for today. Add some in the Events tab.',
                    );
                  }
                  return Column(
                    children: items.map((occurrence) {
                      final event = occurrence.event;
                      final time = occurrence.start;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: HoverCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              _TimelineDot(color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 58,
                                child: Text(
                                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      event.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context).textTheme.titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      event.category,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              if (event.hasReminder)
                                Icon(
                                  Icons.notifications_active_outlined,
                                  size: 19,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                title: 'Active projects',
                subtitle: 'Keep the important work moving',
              ),
              const SizedBox(height: 12),
              projects.when(
                loading: () => const _DashboardLoading(height: 180),
                error: (_, _) => const _DashboardError(),
                data: (items) {
                  final visible = items.take(4).toList();
                  if (visible.isEmpty) {
                    return const _EmptyCard(
                      icon: Icons.folder_open_outlined,
                      message: 'No projects yet. Create one in the Projects tab.',
                    );
                  }
                  final values = progress.valueOrNull ?? const <String, double>{};
                  return LayoutBuilder(
                    builder: (context, projectConstraints) {
                      final columns = projectConstraints.maxWidth >= 1100
                          ? 2
                          : 1;
                      final width = columns == 2
                          ? (projectConstraints.maxWidth - 12) / 2
                          : projectConstraints.maxWidth;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: visible.map((project) {
                          final percent = (values[project.id] ?? 0.0)
                              .clamp(0.0, 100.0);
                          return SizedBox(
                            width: width,
                            child: HoverCard(
                              padding: const EdgeInsets.all(18),
                              child: _ProjectCard(
                                name: project.name,
                                description: project.description,
                                percent: percent,
                                now: now,
                                targetDate: project.targetDate,
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
