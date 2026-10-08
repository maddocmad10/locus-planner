import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/widgets/hover_card.dart';
import '../../../core/widgets/dispose_with.dart';
import '../../diary/data/diary_repository.dart';
import '../providers/dashboard_providers.dart';

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

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final date = '${_weekday(now.weekday)}, ${now.day} ${_month(now.month)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          date,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  String _weekday(int day) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][day - 1];

  String _month(int month) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][month - 1];
}

class _DashboardBento extends StatelessWidget {
  const _DashboardBento({required this.data, required this.compact});

  final DashboardStats data;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final focusProgress = (data.focusMinutes / 120).clamp(0.0, 1.0);

    final focus = HoverCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: focusProgress,
                  strokeWidth: 9,
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Center(
                  child: Text(
                    '${data.focusMinutes}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Focus today',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${data.focusMinutes} min focused · 120 min daily target',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final habits = HoverCard(
      padding: const EdgeInsets.all(20),
      child: _MetricTile(
        icon: Icons.check_circle_outline,
        label: 'Habits',
        value: '${data.habitsDone}/${data.habitsTotal}',
        detail: data.habitsTotal == 0
            ? 'No habits yet'
            : '${(data.habitsDone / data.habitsTotal * 100).round()}% complete',
      ),
    );

    final diary = HoverCard(
      padding: const EdgeInsets.all(20),
      child: _MetricTile(
        icon: Icons.local_fire_department_outlined,
        label: 'Diary streak',
        value: '${data.diaryStreak} days',
        detail: data.diaryStreak > 0 ? 'Keep the rhythm going' : 'Start today',
      ),
    );

    final events = HoverCard(
      padding: const EdgeInsets.all(20),
      child: _MetricTile(
        icon: Icons.event_outlined,
        label: 'On the calendar',
        value: '${data.eventsToday}',
        detail: data.eventsToday == 1 ? 'event today' : 'events today',
      ),
    );

    if (compact) {
      return Column(
        children: [
          focus,
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: habits),
              const SizedBox(width: 12),
              Expanded(child: diary),
            ],
          ),
          const SizedBox(height: 12),
          events,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: focus),
        const SizedBox(width: 12),
        Expanded(child: Column(children: [habits, const SizedBox(height: 12), events])),
        const SizedBox(width: 12),
        Expanded(child: diary),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: scheme.primary, size: 25),
        const SizedBox(height: 14),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.name,
    required this.description,
    required this.percent,
    required this.now,
    required this.targetDate,
  });

  final String name;
  final String? description;
  final double percent;
  final DateTime now;
  final DateTime? targetDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = targetDate != null && targetDate!.isBefore(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (overdue)
              Chip(
                label: const Text('Overdue'),
                visualDensity: VisualDensity.compact,
                backgroundColor: scheme.errorContainer,
                labelStyle: TextStyle(color: scheme.onErrorContainer),
              ),
          ],
        ),
        if (description?.isNotEmpty ?? false) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        if (targetDate != null) ...[
          const SizedBox(height: 10),
          Text(
            'Target ${targetDate!.day}/${targetDate!.month}/${targetDate!.year}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: overdue
                      ? scheme.error
                      : scheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      );
}

class _TimelineDot extends StatelessWidget {
  const _TimelineDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => HoverCard(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(
              icon,
              size: 28,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(message)),
          ],
        ),
      );
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
