import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/planning_repository.dart';
import '../data/planning_snapshot_repository.dart';
import '../domain/planning_models.dart';

class PlanningPage extends ConsumerStatefulWidget {
  const PlanningPage({super.key});

  @override
  ConsumerState<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends ConsumerState<PlanningPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _dismissed = <String>{};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(planningResultProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Planning suggestions'),
            Text(
              'Local workload assistant · no cloud, no AI service',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Suggestions'),
            Tab(text: 'Eisenhower'),
            Tab(text: 'Weekly review'),
          ],
        ),
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not build planning suggestions.')),
        data: (value) => TabBarView(
          controller: _tabs,
          children: [
            _SuggestionsTab(
              result: value,
              dismissed: _dismissed,
              onDismiss: (id) => setState(() => _dismissed.add(id)),
              onOpenReview: () => _tabs.animateTo(2),
            ),
            _EisenhowerTab(matrix: value.matrix),
            _WeeklyReviewTab(review: value.weeklyReview),
          ],
        ),
      ),
    );
  }
}

class _SuggestionsTab extends ConsumerStatefulWidget {
  const _SuggestionsTab({
    required this.result,
    required this.dismissed,
    required this.onDismiss,
    required this.onOpenReview,
  });

  final PlanningResult result;
  final Set<String> dismissed;
  final ValueChanged<String> onDismiss;
  final VoidCallback onOpenReview;

  @override
  ConsumerState<_SuggestionsTab> createState() => _SuggestionsTabState();
}

class _SuggestionsTabState extends ConsumerState<_SuggestionsTab> {
  bool _applying = false;

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.result.suggestions
        .where((suggestion) => !widget.dismissed.contains(suggestion.id))
        .toList();
    if (suggestions.isEmpty) {
      return const EmptyState(
        icon: Icons.check_circle_outline,
        title: 'No suggestions right now',
        subtitle:
            'Suggestions appear when there is measurable workload, deadline '
            'or carry-forward work. Nothing is changed without Apply.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      itemCount: suggestions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _SuggestionCard(
        suggestion: suggestions[index],
        applying: _applying,
        onApply: _apply,
        onSkip: () => widget.onDismiss(suggestions[index].id),
        onOpenReview: widget.onOpenReview,
      ),
    );
  }

  Future<void> _apply(
    PlanningSuggestion suggestion, {
    DateTime? targetDay,
  }) async {
    if (_applying) return;
    setState(() => _applying = true);
    final success = await runUserMutation(
      context,
      () => ref
          .read(planningRepositoryProvider)
          .applySuggestion(suggestion, targetDay: targetDay),
      failureMessage: 'The suggestion is no longer applicable.',
    );
    if (!mounted) return;
    setState(() => _applying = false);
    if (!success) return;
    UndoSnackbar.show(
      context,
      message: 'Suggestion applied',
      service: ref.read(undoServiceProvider),
    );
    ref.invalidate(planningSnapshotProvider);
  }
}

class _SuggestionCard extends ConsumerWidget {
  const _SuggestionCard({
    required this.suggestion,
    required this.applying,
    required this.onApply,
    required this.onSkip,
    required this.onOpenReview,
  });

  final PlanningSuggestion suggestion;
  final bool applying;
  final Future<void> Function(PlanningSuggestion, {DateTime? targetDay})
  onApply;
  final VoidCallback onSkip;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon(suggestion.type), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    suggestion.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (suggestion.targetDate != null)
                  Text(
                    DateFormat('EEE d MMM').format(suggestion.targetDate!),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(suggestion.explanation),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final reason in suggestion.reasons)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      reason.message,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
            if (suggestion.operations.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Proposed changes',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              for (final operation in suggestion.operations)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _operationLabel(operation),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                if (suggestion.type == PlanningSuggestionType.weeklyReview)
                  FilledButton(
                    onPressed: onOpenReview,
                    child: const Text('Open review'),
                  )
                else if (suggestion.actionable &&
                    suggestion.operations.isNotEmpty)
                  FilledButton(
                    onPressed: applying ? null : () => onApply(suggestion),
                    child: const Text('Apply'),
                  ),
                if (suggestion.type == PlanningSuggestionType.carryForward) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: applying
                        ? null
                        : () => onApply(
                            suggestion,
                            targetDay: AppClock.now().add(
                              const Duration(days: 1),
                            ),
                          ),
                    child: const Text('Tomorrow'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: applying ? null : () => _chooseDate(context),
                    child: const Text('Choose date'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: applying ? null : () => _remove(context, ref),
                    child: const Text('Remove'),
                  ),
                ],
                const Spacer(),
                TextButton(onPressed: onSkip, child: const Text('Skip')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseDate(BuildContext context) async {
    final initial = suggestion.targetDate ?? AppClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      await onApply(suggestion, targetDay: picked);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await runUserMutation(
      context,
      () => ref.read(planningRepositoryProvider).removeCarryForward(suggestion),
      failureMessage: 'Could not remove the carry-forward item.',
    );
    if (!success) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(content: Text('Removed from the previous plan')),
    );
    ref.invalidate(planningSnapshotProvider);
  }

  static IconData _icon(PlanningSuggestionType type) => switch (type) {
    PlanningSuggestionType.overcommittedDay => Icons.speed_outlined,
    PlanningSuggestionType.carryForward => Icons.redo_outlined,
    PlanningSuggestionType.deadlineRisk => Icons.warning_amber_rounded,
    PlanningSuggestionType.unscheduledPriority => Icons.push_pin_outlined,
    PlanningSuggestionType.focusWindow => Icons.center_focus_strong_outlined,
    PlanningSuggestionType.weeklyReview => Icons.assessment_outlined,
  };

  static String _operationLabel(PlanningOperation operation) {
    return switch (operation) {
      MoveBlockOperation() =>
        'Move a calendar block from '
            '${DateFormat('EEE d MMM HH:mm').format(operation.previousStart)}-'
            '${DateFormat('HH:mm').format(operation.previousEnd)} to '
            '${DateFormat('EEE d MMM HH:mm').format(operation.newStart)}-'
            '${DateFormat('HH:mm').format(operation.newEnd)}',
      CreateBlockOperation() =>
        'Create a block on '
            '${DateFormat('EEE d MMM HH:mm').format(operation.start)}-'
            '${DateFormat('HH:mm').format(operation.end)}',
      MovePlanItemOperation() =>
        'Move a My Day item from '
            '${DateFormat('EEE d MMM').format(operation.fromDay)} to '
            '${DateFormat('EEE d MMM').format(operation.toDay)}',
      UpdateTaskFlagsOperation() => 'Update the task importance/urgency flag',
      UpdateTaskPriorityOperation() =>
        'Change priority from ${operation.previousPriority} to '
            '${operation.priority}',
    };
  }
}

class _EisenhowerTab extends ConsumerStatefulWidget {
  const _EisenhowerTab({required this.matrix});

  final EisenhowerResult matrix;

  @override
  ConsumerState<_EisenhowerTab> createState() => _EisenhowerTabState();
}

class _EisenhowerTabState extends ConsumerState<_EisenhowerTab> {
  Future<void> _setWindow(int days) async {
    final success = await runUserMutation(
      context,
      () => ref.read(planningRepositoryProvider).saveUrgencyWindow(days),
      failureMessage: 'Could not save the urgency window.',
    );
    if (success) ref.invalidate(planningSnapshotProvider);
  }

  @override
  Widget build(BuildContext context) {
    final matrix = widget.matrix;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Urgency is derived from the due date. Importance is set by '
                  'you; it is never inferred from priority.',
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<int>(
                value: matrix.urgencyWindowDays,
                items: [
                  for (final days in {
                    1,
                    3,
                    7,
                    14,
                    matrix.urgencyWindowDays,
                  }.toList()..sort())
                    DropdownMenuItem(
                      value: days,
                      child: Text('$days-day window'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _setWindow(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 900 ? 2 : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: columns == 2 ? 1.55 : 1.8,
                children: [
                  _QuadrantCard(
                    title: 'Do first',
                    subtitle: 'Important + urgent',
                    color: Colors.red,
                    quadrant: EisenhowerQuadrant.doFirst,
                    items: matrix.doFirst,
                  ),
                  _QuadrantCard(
                    title: 'Schedule',
                    subtitle: 'Important + not urgent',
                    color: Colors.blue,
                    quadrant: EisenhowerQuadrant.schedule,
                    items: matrix.schedule,
                  ),
                  _QuadrantCard(
                    title: 'Delegate / Waiting',
                    subtitle: 'Not important + urgent',
                    color: Colors.orange,
                    quadrant: EisenhowerQuadrant.delegate,
                    items: matrix.delegate,
                  ),
                  _QuadrantCard(
                    title: 'Eliminate / Review',
                    subtitle: 'Not important + not urgent',
                    color: Colors.grey,
                    quadrant: EisenhowerQuadrant.eliminate,
                    items: matrix.eliminate,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuadrantCard extends ConsumerWidget {
  const _QuadrantCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.quadrant,
    required this.items,
  });

  final String title;
  final String subtitle;
  final Color color;
  final EisenhowerQuadrant quadrant;
  final List<EisenhowerItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$title (${items.length})',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Text(
                        'No tasks',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) => _MatrixTask(
                        item: items[index],
                        onImportance: (value) async {
                          await ref
                              .read(planningRepositoryProvider)
                              .setImportance(items[index].task.key, value);
                          ref.invalidate(planningSnapshotProvider);
                        },
                        onUrgency: (value) async {
                          final override = switch (value) {
                            'urgent' => true,
                            'not_urgent' => false,
                            _ => null,
                          };
                          await ref
                              .read(planningRepositoryProvider)
                              .setUrgencyOverride(
                                items[index].task.key,
                                override,
                              );
                          ref.invalidate(planningSnapshotProvider);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatrixTask extends StatelessWidget {
  const _MatrixTask({
    required this.item,
    required this.onImportance,
    required this.onUrgency,
  });

  final EisenhowerItem item;
  final ValueChanged<bool> onImportance;
  final ValueChanged<String> onUrgency;

  @override
  Widget build(BuildContext context) {
    final task = item.task;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Checkbox(
            value: item.important,
            visualDensity: VisualDensity.compact,
            onChanged: (value) => onImportance(value ?? false),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  item.urgencyReason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Urgency override',
            icon: Icon(
              item.urgencyIsOverride ? Icons.push_pin : Icons.schedule_outlined,
              size: 16,
            ),
            onSelected: onUrgency,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'derived',
                child: Text('Use due-date window'),
              ),
              PopupMenuItem(value: 'urgent', child: Text('Mark urgent')),
              PopupMenuItem(
                value: 'not_urgent',
                child: Text('Mark not urgent'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeeklyReviewTab extends StatelessWidget {
  const _WeeklyReviewTab({required this.review});

  final WeeklyReviewResult? review;

  @override
  Widget build(BuildContext context) {
    final value = review;
    if (value == null || !value.hasData) {
      return const EmptyState(
        icon: Icons.assessment_outlined,
        title: 'No weekly data yet',
        subtitle:
            'Complete tasks, focus sessions, habits or milestones to build a '
            'local review. Missing data is shown as zero, never estimated.',
      );
    }
    final range =
        '${DateFormat('EEE d MMM').format(value.from)} – '
        '${DateFormat('EEE d MMM').format(value.to)}';
    final habitRate = value.habitRate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      children: [
        Text(
          'Selected range: $range',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        const Text(
          'All metrics are computed locally from stored rows. '
          'Denominators are shown where a rate is displayed.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              label: 'Completed history',
              value: '${value.completedTasks}',
              detail:
                  '${value.completedOccurrences} recurring completion(s), '
                  '${value.projectTasksCompleted} project task(s) due in range. '
                  'Plain to-dos without a recorded timestamp are not inferred.',
            ),
            _Metric(
              label: 'Carried tasks',
              value: '${value.carriedTasks}',
              detail: 'Unfinished My Day items from earlier days',
            ),
            _Metric(
              label: 'Overdue now',
              value: '${value.overdueTasks}',
              detail: 'Open tasks whose due date is before today',
            ),
            _Metric(
              label: 'Focus time',
              value: '${value.focusMinutes} min',
              detail: '${value.focusSessions} session(s) in range',
            ),
            _Metric(
              label: 'Habits',
              value: habitRate == null
                  ? '${value.habitCompletions}/0'
                  : '${value.habitCompletions}/${value.habitPossible}',
              detail: habitRate == null
                  ? 'No active habits'
                  : '${(habitRate * 100).toStringAsFixed(0)}% of possible '
                        'daily check-ins',
            ),
            _Metric(
              label: 'Milestones',
              value: '${value.milestonesCompleted}/${value.milestonesDue}',
              detail: 'Completed / due in the selected range',
            ),
          ],
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
