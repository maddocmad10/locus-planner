import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart'
    show BooleanExpressionOperators, ComparableExpr;

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/utils/day_math.dart';

class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ==================== SUMMARY STATS ====================
          Text(
            'Overview',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: Future.wait([
              db.focusMinutesToday(),
              db.diaryStreak(),
              db.watchHabits().first,
              db.watchProjects().first,
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final focusToday = snapshot.data![0] as int;
              final diaryStreak = snapshot.data![1] as int;
              final habits = snapshot.data![2] as List<Habit>;
              final projects = snapshot.data![3] as List<Project>;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _StatCard(
                    title: 'Focus Today',
                    value: '$focusToday min',
                    icon: Icons.timer_outlined,
                    color: Colors.blue,
                  ),
                  _StatCard(
                    title: 'Diary Streak',
                    value: '$diaryStreak days',
                    icon: Icons.local_fire_department,
                    color: Colors.orange,
                  ),
                  _StatCard(
                    title: 'Active Habits',
                    value: '${habits.length}',
                    icon: Icons.check_circle_outline,
                    color: Colors.green,
                  ),
                  _StatCard(
                    title: 'Projects',
                    value: '${projects.length}',
                    icon: Icons.folder_outlined,
                    color: Colors.purple,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 32),

          // ==================== FOCUS TIME TREND ====================
          Text(
            'Focus Time (Last 14 Days)',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: FutureBuilder<List<FocusSession>>(
              future: db.watchFocusSessions().first,
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];
                final dailyMinutes = _buildDailyFocusMap(sessions, 14);

                if (dailyMinutes.every((m) => m == 0)) {
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
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= 14)
                                  return const SizedBox();
                                final date = DayMath.addDays(
                                  DateTime.now(),
                                  -(13 - index),
                                );
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
                              (i) => FlSpot(
                                i.toDouble(),
                                dailyMinutes[i].toDouble(),
                              ),
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
              },
            ),
          ),

          const SizedBox(height: 32),

          // ==================== HABIT COMPLETION THIS WEEK ====================
          Text(
            'Habits This Week',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FutureBuilder(
            future: _getHabitWeeklyStats(db),
            builder: (context, snapshot) {
              final stats = snapshot.data ?? [];

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
                      final progress = s.target == 0
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
                            LinearProgressIndicator(
                              value: progress,
                              minHeight: 8,
                              backgroundColor: Colors.grey.shade200,
                              color: progress >= 1.0
                                  ? Colors.green
                                  : Theme.of(context).colorScheme.primary,
                            ),
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

          // ==================== DIARY MOOD TREND ====================
          Text(
            'Mood Trend (Last 14 Days)',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: FutureBuilder<List<DiaryEntry>>(
              future: db.watchDiaryEntries().first,
              builder: (context, snapshot) {
                final entries = snapshot.data ?? [];
                final moodData = _buildMoodMap(entries, 14);

                if (moodData.every((m) => m == 0)) {
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
                        gridData: const FlGridData(
                          show: true,
                          drawVerticalLine: false,
                        ),
                        titlesData: FlTitlesData(
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= 14)
                                  return const SizedBox();
                                final date = DayMath.addDays(
                                  DateTime.now(),
                                  -(13 - index),
                                );
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
                                const emojis = [
                                  '',
                                  '😞',
                                  '😐',
                                  '🙂',
                                  '😊',
                                  '🤩',
                                ];
                                final i = value.toInt();
                                if (i < 1 || i > 5) return const SizedBox();
                                return Text(
                                  emojis[i],
                                  style: const TextStyle(fontSize: 14),
                                );
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
                            spots: List.generate(
                              14,
                              (i) =>
                                  FlSpot(i.toDouble(), moodData[i].toDouble()),
                            ),
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
              },
            ),
          ),

          const SizedBox(height: 32),

          // ==================== PROJECT PROGRESS ====================
          Text(
            'Project Progress',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          StreamBuilder<List<Project>>(
            stream: db.watchProjects(),
            builder: (context, snapshot) {
              final projects = snapshot.data ?? [];

              if (projects.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No projects yet.'),
                  ),
                );
              }

              return Column(
                children: projects.take(5).map((project) {
                  return FutureBuilder<double>(
                    future: db.projectProgressPercent(project.id),
                    builder: (context, progSnap) {
                      final progress = progSnap.data ?? 0.0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                project.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: progress / 100,
                                minHeight: 8,
                                backgroundColor: Colors.grey.shade200,
                              ),
                              const SizedBox(height: 4),
                              Text('${progress.toStringAsFixed(0)}% complete'),
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

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ==================== HELPERS ====================

  List<int> _buildDailyFocusMap(List<FocusSession> sessions, int days) {
    final result = List<int>.filled(days, 0);
    final today = DateTime.now();

    for (final session in sessions) {
      final dayDiff = DayMath.calendarDaysBetween(session.startTime, today);

      if (dayDiff >= 0 && dayDiff < days) {
        final index = days - 1 - dayDiff;
        result[index] += session.durationMinutes;
      }
    }
    return result;
  }

  List<double> _buildMoodMap(List<DiaryEntry> entries, int days) {
    final result = List<double>.filled(days, 0);
    final today = DateTime.now();

    for (final entry in entries) {
      final dayDiff = DayMath.calendarDaysBetween(entry.date, today);

      if (dayDiff >= 0 && dayDiff < days) {
        final index = days - 1 - dayDiff;
        result[index] = entry.mood.toDouble();
      }
    }
    return result;
  }

  Future<List<_HabitWeekStat>> _getHabitWeeklyStats(AppDatabase db) async {
    final habits = await db.watchHabits().first;
    final now = DateTime.now();
    final start = DayMath.startOfWeek(now);

    final stats = <_HabitWeekStat>[];

    for (final habit in habits) {
      final logs =
          await (db.select(db.habitLogs)..where(
                (t) =>
                    t.habitId.equals(habit.id) &
                    t.date.isBiggerOrEqualValue(start) &
                    t.completed.equals(true),
              ))
              .get();

      stats.add(
        _HabitWeekStat(
          name: habit.name,
          icon: habit.icon,
          completed: logs.length,
          target: habit.targetPerWeek,
        ),
      );
    }

    return stats;
  }
}

// ==================== SUPPORTING CLASSES ====================

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
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
}

class _HabitWeekStat {
  final String name;
  final String icon;
  final int completed;
  final int target;

  _HabitWeekStat({
    required this.name,
    required this.icon,
    required this.completed,
    required this.target,
  });
}
