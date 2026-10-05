import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../events/data/event_repository.dart';
import '../../../core/services/notification_service.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _showReview(BuildContext context, WidgetRef ref) {
    final winCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final tomorrowCtrl = TextEditingController();

    showDialog(
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
              final db = ref.read(databaseProvider);
              final now = DateTime.now();
              final dayStart = DateTime(now.year, now.month, now.day);
              final newContent =
                  'Win: ${winCtrl.text}\nBlocker: ${blockCtrl.text}\nTomorrow: ${tomorrowCtrl.text}';

              final existing = await db.entryForDate(dayStart);

              if (existing == null) {
                await db
                    .into(db.diaryEntries)
                    .insert(
                      DiaryEntriesCompanion(
                        id: drift.Value(const Uuid().v4()),
                        date: drift.Value(dayStart),
                        mood: const drift.Value(3),
                        content: drift.Value(newContent),
                      ),
                    );
              } else {
                await (db.update(
                  db.diaryEntries,
                )..where((t) => t.id.equals(existing.id))).write(
                  DiaryEntriesCompanion(
                    content: drift.Value('${existing.content}\n\n$newContent'),
                  ),
                );
              }

              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              await NotificationService.instance.showNow(
                title: 'Review Saved',
                body: 'Saved to diary',
              );

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Saved to diary. Great job!')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

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
          // ==================== STATS ROW ====================
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              FutureBuilder<int>(
                future: db.focusMinutesToday(),
                builder: (c, s) => _StatCard(
                  title: 'Focus Today',
                  value: '${s.data ?? 0} min',
                  icon: Icons.timer_outlined,
                ),
              ),
              StreamBuilder<List<Habit>>(
                stream: db.watchHabits(),
                builder: (c, s) => _StatCard(
                  title: 'Active Habits',
                  value: '${s.data?.length ?? 0}',
                  icon: Icons.check_circle_outline,
                ),
              ),
              StreamBuilder<List<EventOccurrence>>(
                stream: ref.watch(eventRepositoryProvider).watchForDay(DateTime.now()),
                builder: (c, s) => _StatCard(
                  title: 'Events Today',
                  value: '${s.data?.length ?? 0}',
                  icon: Icons.event_outlined,
                ),
              ),
              FutureBuilder<int>(
                future: db.diaryStreak(),
                builder: (c, s) => _StatCard(
                  title: 'Diary Streak',
                  value: '${s.data ?? 0} days',
                  icon: Icons.local_fire_department_outlined,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // ==================== TODAY'S SCHEDULE ====================
          Text(
            "Today's Schedule",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<EventOccurrence>>(
            stream: ref.watch(eventRepositoryProvider).watchForDay(DateTime.now()),
            builder: (context, snapshot) {
              final events = snapshot.data ?? [];
              if (events.isEmpty) {
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
                children: events.map((occurrence) {
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
                          ? const Icon(
                              Icons.notifications_active,
                              color: Colors.orange,
                            )
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 32),

          // ==================== ACTIVE PROJECTS ====================
          Text(
            'Active Projects',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Project>>(
            stream: db.watchProjects(),
            builder: (context, snapshot) {
              final projects = snapshot.data?.take(4).toList() ?? [];

              if (projects.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No projects yet. Create one in the Projects tab.',
                    ),
                  ),
                );
              }

              return Column(
                children: projects.map((project) {
                  return FutureBuilder<double>(
                    future: db.projectProgressPercent(project.id),
                    builder: (context, progressSnapshot) {
                      final progress = progressSnapshot.data ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.name,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (project.description != null &&
                                  project.description!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 4,
                                    bottom: 8,
                                  ),
                                  child: Text(
                                    project.description!,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress / 100,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${progress.toStringAsFixed(0)}% complete',
                                  ),
                                  if (project.targetDate != null)
                                    Text(
                                      'Target: ${project.targetDate!.day}/${project.targetDate!.month}/${project.targetDate!.year}',
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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

// ==================== REUSABLE STAT CARD ====================
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

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
              Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}
