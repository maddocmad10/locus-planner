import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/utils/day_math.dart';
import '../providers/insights_providers.dart';
import '../../projects/data/project_repository.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(insightsSummaryProvider);
    final focus = ref.watch(focusLast14DaysProvider);
    final habits = ref.watch(habitWeekStatsProvider);
    final diary = ref.watch(diaryLast14DaysProvider);
    final projects = ref.watch(projectsStreamProvider);
    final progress = ref.watch(projectProgressStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Overview',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          summary.when(
            loading: () => const _LoadingBox(height: 100),
            error: (_, _) => const _ErrorBox(),
            data: (data) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatCard(
                  title: 'Focus Today',
                  value: '${data.focusToday} min',
                  icon: Icons.timer_outlined,
                  color: Colors.blue,
                ),
                _StatCard(
                  title: 'Diary Streak',
                  value: '${data.diaryStreak} days',
                  icon: Icons.local_fire_department,
                  color: Colors.orange,
                ),
                _StatCard(
                  title: 'Active Habits',
                  value: '${data.habits.length}',
                  icon: Icons.check_circle_outline,
                  color: Colors.green,
                ),
                _StatCard(
                  title: 'Projects',
                  value: '${data.projects.length}',
                  icon: Icons.folder_outlined,
                  color: Colors.purple,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _SectionTitle('Focus Time (Last 14 Days)'),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: focus.when(
              loading: () => const _LoadingBox(height: 220),
              error: (_, _) => const _ErrorBox(),
              data: (sessions) => _FocusChart(sessions: sessions),
            ),
          ),
          const SizedBox(height: 32),
          _SectionTitle('Habits This Week'),
          const SizedBox(height: 12),
          habits.when(
            loading: () => const _LoadingBox(height: 120),
            error: (_, _) => const _ErrorBox(),
            data: (stats) {
              if (stats.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No habits yet. Add some habits to track consistency.',
                    ),
                  ),
                );
              }
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: stats.map((s) {
                      final ratio = s.target <= 0
                          ? 0.0
                          : (s.completed / s.target).clamp(0.0, 1.0);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  s.icon,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    s.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text('${s.completed}/${s.target}'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(value: ratio, minHeight: 8),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 32),
          _SectionTitle('Mood Trend (Last 14 Days)'),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: diary.when(
              loading: () => const _LoadingBox(height: 200),
              error: (_, _) => const _ErrorBox(),
              data: (entries) => _MoodChart(entries: entries),
            ),
          ),
          const SizedBox(height: 32),
          _SectionTitle('Project Progress'),
          const SizedBox(height: 12),
          projects.when(
            loading: () => const _LoadingBox(height: 140),
            error: (_, _) => const _ErrorBox(),
            data: (items) {
              if (items.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No projects yet.'),
                  ),
                );
              }
              final values = progress.valueOrNull ?? const <String, double>{};
              return Column(
                children: items.take(5).map((project) {
                  final percent = values[project.id] ?? 0.0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: (percent / 100).clamp(0.0, 1.0),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 4),
                          Text('${percent.toStringAsFixed(0)}% complete'),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _FocusChart extends StatelessWidget {
  const _FocusChart({required this.sessions});
  final List<FocusSession> sessions;

  @override
  Widget build(BuildContext context) {
    final daily = List<int>.filled(14, 0);
    final today = DateTime.now();
    for (final session in sessions) {
      final diff = DayMath.calendarDaysBetween(session.startTime, today);
      if (diff >= 0 && diff < 14) daily[13 - diff] += session.durationMinutes;
    }
    if (daily.every((m) => m == 0)) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No focus sessions yet.\nComplete some Focus sessions to see trends.',
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= 14) return const SizedBox();
                    final date = DayMath.addDays(DateTime.now(), -(13 - index));
                    return Text(
                      DateFormat('E').format(date).substring(0, 1),
                      style: const TextStyle(fontSize: 11),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 36,
                  getTitlesWidget: (value, meta) => Text(
                    '${value.toInt()}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(
                  14,
                  (i) => FlSpot(i.toDouble(), daily[i].toDouble()),
                ),
                isCurved: true,
                color: Theme.of(context).colorScheme.primary,
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoodChart extends StatelessWidget {
  const _MoodChart({required this.entries});
  final List<DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final mood = List<double>.filled(14, 0);
    final today = DateTime.now();
    for (final entry in entries) {
      final diff = DayMath.calendarDaysBetween(entry.date, today);
      if (diff >= 0 && diff < 14) mood[13 - diff] = entry.mood.toDouble();
    }
    if (mood.every((m) => m == 0)) {
      return const Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No diary entries yet.\nWrite some diary entries to see mood trends.',
            ),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: 5,
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= 14) return const SizedBox();
                    final date = DayMath.addDays(DateTime.now(), -(13 - index));
                    return Text(
                      DateFormat('E').format(date).substring(0, 1),
                      style: const TextStyle(fontSize: 11),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    const emojis = ['', '😞', '😐', '🙂', '😊', '🤩'];
                    final i = value.toInt();
                    return i < 1 || i > 5
                        ? const SizedBox()
                        : Text(emojis[i], style: const TextStyle(fontSize: 14));
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: List.generate(14, (i) => FlSpot(i.toDouble(), mood[i])),
                isCurved: true,
                color: Colors.orange,
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.orange.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
  );
}

class _LoadingBox extends StatelessWidget {
  const _LoadingBox({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: const Center(child: CircularProgressIndicator()),
  );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(20),
      child: Text('Could not load insight data.'),
    ),
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 160,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}
