import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/command_action_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/widgets/user_action_error.dart';
import '../../my_day/providers/my_day_providers.dart';
import 'widgets/daily_intention_card.dart';
import 'widgets/daily_schedule.dart';
import 'widgets/end_of_day_review.dart';
import 'widgets/planned_tasks_list.dart';
import 'widgets/suggested_tasks_section.dart';
import 'widgets/task_picker_dialog.dart';
import 'widgets/workload_summary.dart';

/// The Windows daily-planning workspace. Everything on this page is derived
/// from the selected day's plan; the original tasks stay authoritative.
class MyDayPage extends ConsumerStatefulWidget {
  const MyDayPage({super.key});

  @override
  ConsumerState<MyDayPage> createState() => _MyDayPageState();
}

class _MyDayPageState extends ConsumerState<MyDayPage> {
  @override
  void initState() {
    super.initState();
    // The palette can dispatch before this page subscribes when navigation is
    // restored at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleCommand(ref.read(commandActionProvider));
    });
  }

  void _handleCommand(CommandAction action) {
    if (!mounted) return;
    final notifier = ref.read(commandActionProvider.notifier);
    switch (action) {
      case CommandAction.addToMyDay:
        notifier.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _addTask();
        });
        break;
      case CommandAction.viewTomorrow:
        notifier.clear();
        ref
            .read(myDaySelectedDayProvider.notifier)
            .select(DayMath.addDays(DayMath.dateOnly(AppClock.now()), 1));
        break;
      default:
        break;
    }
  }

  Future<void> _addTask() async {
    final day = ref.read(myDaySelectedDayProvider);
    final picked = await showMyDayTaskPicker(context, ref, day);
    if (picked == null || !mounted) return;
    final added = await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).addTask(day, picked),
      failureMessage: 'Could not add the task to My Day.',
    );
    if (added && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added “${picked.title}”')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<CommandAction>(commandActionProvider, (previous, next) {
      if (next != previous) _handleCommand(next);
    });

    final selectedDay = ref.watch(myDaySelectedDayProvider);
    final view = ref.watch(myDayDayViewProvider(selectedDay));
    final notifier = ref.read(myDaySelectedDayProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Day'),
        automaticallyImplyLeading: false,
        actions: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => notifier.shift(-1),
              ),
              Text(
                DateFormat('EEE, d MMM yyyy').format(selectedDay),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              IconButton(
                tooltip: 'Next day',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => notifier.shift(1),
              ),
            ],
          ),
          if (view.valueOrNull?.isEmpty == false)
            TextButton.icon(
              onPressed: () => showEndOfDayReview(context, view.requireValue),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Review day'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _addTask,
            icon: const Icon(Icons.add),
            label: const Text('Add task'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: view.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load this day: $error'),
          ),
        ),
        data: (plan) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DailyIntentionCard(plan: plan),
                const SizedBox(height: 12),
                PlannedTasksList(plan: plan),
                const SizedBox(height: 12),
                SuggestedTasksSection(plan: plan),
              ],
            );
            final right = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DailySchedule(plan: plan),
                const SizedBox(height: 12),
                WorkloadSummary(plan: plan),
                const SizedBox(height: 12),
                EndOfDayReviewCard(plan: plan),
              ],
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: left),
                        const SizedBox(width: 16),
                        Expanded(flex: 2, child: right),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [left, const SizedBox(height: 12), right],
                    ),
            );
          },
        ),
      ),
    );
  }
}
