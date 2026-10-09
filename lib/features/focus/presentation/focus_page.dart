import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/focus_timer_provider.dart';
import '../data/focus_repository.dart';
import '../../projects/data/project_repository.dart';

/// The countdown itself lives in [focusTimerProvider], so it keeps running
/// while the user visits other tabs. This page only displays and controls it.
class FocusPage extends ConsumerWidget {
  const FocusPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<int>(focusTimerProvider.select((s) => s.completedCount), (
      previous,
      next,
    ) {
      if (next > (previous ?? 0)) {
        final minutes = ref.read(focusTimerProvider).lastCompletedMinutes;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Great job! $minutes minute focus session completed.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Timer'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Today's Focus Summary (live: updates when a session is saved)
            ref
                .watch(focusSessionsTodayProvider)
                .when(
                  loading: () => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (_, _) => const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text("Could not load today's focus time."),
                    ),
                  ),
                  data: (sessions) {
                    final minutes = sessions.fold<int>(
                      0,
                      (sum, session) => sum + session.durationMinutes,
                    );
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.timer, size: 32),
                            const SizedBox(width: 12),
                            Text(
                              'Focus Today: $minutes minutes',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

            const SizedBox(height: 12),

            Consumer(
              builder: (context, ref, _) {
                final weekly = ref.watch(focusMinutesLast7DaysProvider);
                return weekly.when(
                  loading: () => const SizedBox(
                    height: 28,
                    child: Center(child: LinearProgressIndicator()),
                  ),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (minutes) => Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Last 7 days: $minutes minutes • ${(minutes / 60).toStringAsFixed(1)} hours',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            const _TimerDisplay(),

            const SizedBox(height: 32),

            const _DurationChips(),

            const SizedBox(height: 24),

            const _ProjectPicker(),

            const SizedBox(height: 32),

            const _TimerControls(),

            const SizedBox(height: 40),

            // Recent Focus Sessions
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Focus Sessions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),

            ref
                .watch(recentFocusSessionsProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) =>
                      const Text('Could not load recent sessions.'),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'No focus sessions yet. Complete your first session!',
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: sessions.map((session) {
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.timer_outlined),
                            title: Text('${session.durationMinutes} minutes'),
                            subtitle: Text(
                              '${session.startTime.day}/${session.startTime.month} • ${session.startTime.hour}:${session.startTime.minute.toString().padLeft(2, '0')}',
                            ),
                            trailing: session.projectId != null
                                ? const Chip(label: Text('Linked to Project'))
                                : null,
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(int seconds) {
  final minutes = seconds ~/ 60;
  final secs = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

/// Ring + countdown. Only this subtree rebuilds on every tick.
class _TimerDisplay extends ConsumerWidget {
  const _TimerDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(focusTimerProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 280,
          height: 280,
          child: CircularProgressIndicator(
            value: timer.progress,
            strokeWidth: 12,
            backgroundColor: Colors.grey.shade300,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Column(
          children: [
            Text(
              _formatTime(timer.remainingSeconds),
              style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w300),
            ),
            Text(
              '${timer.selectedMinutes} min session',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}

class _DurationChips extends ConsumerWidget {
  const _DurationChips();

  static const _presets = [25, 50, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(focusTimerProvider);
    final notifier = ref.read(focusTimerProvider.notifier);
    final isRestoring = ref.watch(
      focusTimerProvider.select((s) => s.isRestoring),
    );

    return Wrap(
      spacing: 12,
      children: _presets.map((minutes) {
        return ChoiceChip(
          label: Text('$minutes min'),
          selected: timer.selectedMinutes == minutes,
          // Disabled while running: changing the length would discard the session.
          onSelected: timer.isRunning || isRestoring
              ? null
              : (_) => notifier.setDuration(minutes),
        );
      }).toList(),
    );
  }
}

class _ProjectPicker extends ConsumerWidget {
  const _ProjectPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsStreamProvider);
    final selectedId = ref.watch(focusTimerProvider.select((s) => s.projectId));
    final isRunning = ref.watch(focusTimerProvider.select((s) => s.isRunning));
    final isRestoring = ref.watch(
      focusTimerProvider.select((s) => s.isRestoring),
    );

    return projects.when(
      loading: () =>
          const SizedBox(width: 320, child: LinearProgressIndicator()),
      error: (_, _) => const Text('Could not load projects.'),
      data: (items) {
        final value = items.any((p) => p.id == selectedId) ? selectedId : null;
        return SizedBox(
          width: 320,
          child: DropdownButtonFormField<String?>(
            initialValue: value,
            decoration: const InputDecoration(
              labelText: 'Link to Project (optional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No project'),
              ),
              ...items.map(
                (project) => DropdownMenuItem<String?>(
                  value: project.id,
                  child: Text(project.name),
                ),
              ),
            ],
            onChanged: isRunning || isRestoring
                ? null
                : (v) => ref.read(focusTimerProvider.notifier).setProject(v),
          ),
        );
      },
    );
  }
}

class _TimerControls extends ConsumerWidget {
  const _TimerControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(focusTimerProvider.select((s) => s.status));
    final notifier = ref.read(focusTimerProvider.notifier);
    final isRestoring = ref.watch(
      focusTimerProvider.select((s) => s.isRestoring),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (status != FocusTimerStatus.running)
          FilledButton.icon(
            onPressed: isRestoring ? null : notifier.start,
            icon: const Icon(Icons.play_arrow),
            label: Text(
              status == FocusTimerStatus.paused ? 'Resume' : 'Start Focus',
            ),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          )
        else
          FilledButton.icon(
            onPressed: isRestoring ? null : notifier.pause,
            icon: const Icon(Icons.pause),
            label: const Text('Pause'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: isRestoring ? null : notifier.reset,
          icon: const Icon(Icons.refresh),
          label: const Text('Reset'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
      ],
    );
  }
}
