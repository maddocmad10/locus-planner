import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/clock_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/mini_today_provider.dart';
import '../../../core/providers/navigation_provider.dart';
import '../../../core/providers/quick_capture_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/day_agenda.dart';
import '../../../core/utils/day_math.dart';
import '../../tasks/data/task_repository.dart';

final _miniEventsProvider = StreamProvider<List<Event>>(
  (ref) => ref.watch(databaseProvider).watchAllEvents(),
);
final _miniTasksProvider = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(databaseProvider).watchAllTodoItems(),
);

class MiniTodayPage extends ConsumerWidget {
  const MiniTodayPage({super.key});

  Future<void> _openFullPlanner(BuildContext context, WidgetRef ref) async {
    await ref.read(windowServiceProvider).exitMiniMode();
    ref.read(miniTodayModeProvider.notifier).state = false;
    ref.read(navigationIndexProvider.notifier).setIndex(NavPage.dashboard);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    final today = DayMath.dateOnly(now);
    final events = ref.watch(_miniEventsProvider).valueOrNull ?? const [];
    final tasks = ref.watch(_miniTasksProvider).valueOrNull ?? const [];
    final todayEvents = agendaForDay(events, today).take(3).toList();
    final dueTasks = tasks
        .where(
          (task) =>
              !task.completed &&
              task.dueDate != null &&
              DayMath.calendarDaysBetween(today, task.dueDate!) == 0,
        )
        .take(4)
        .toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(DateFormat('EEE d MMM').format(today)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Add',
            onPressed: () =>
                ref.read(quickCaptureRequestProvider.notifier).request(),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: 'Open full planner',
            onPressed: () => _openFullPlanner(context, ref),
            icon: const Icon(Icons.open_in_full),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text(
            DateFormat('EEEE').format(today),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (todayEvents.isEmpty)
            const _MiniEmpty('Nothing scheduled today.')
          else
            Card(
              child: Column(
                children: [
                  for (final entry in todayEvents)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.event_outlined, size: 20),
                      title: Text(entry.event.title),
                      subtitle: Text(
                        entry.event.allDay
                            ? 'All day'
                            : DateFormat('HH:mm').format(entry.start),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text('Tasks due today', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          if (dueTasks.isEmpty)
            const _MiniEmpty('No tasks due today.')
          else
            Card(
              child: Column(
                children: [
                  for (final task in dueTasks)
                    ListTile(
                      dense: true,
                      leading: Checkbox(
                        value: task.completed,
                        onChanged: (value) => ref
                            .read(taskRepositoryProvider)
                            .toggle(task.id, value ?? false),
                      ),
                      title: Text(task.title),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _openFullPlanner(context, ref),
            icon: const Icon(Icons.fullscreen),
            label: const Text('Open full planner'),
          ),
        ],
      ),
    );
  }
}

class _MiniEmpty extends StatelessWidget {
  const _MiniEmpty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(message, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
