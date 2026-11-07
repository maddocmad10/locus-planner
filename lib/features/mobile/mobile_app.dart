import 'dart:async';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/service_providers.dart';
import '../../core/services/natural_language_quick_add.dart';
import '../../core/services/sync_tls.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/day_math.dart';
import '../../core/utils/recurrence.dart';
import '../../core/widgets/attachment_strip.dart';
import '../../core/widgets/dispose_with.dart';
import '../../core/widgets/notes_field.dart';
import '../../core/widgets/quick_add_preview.dart';
import '../../core/widgets/user_action_error.dart';
import '../app_lock/presentation/app_lock_gate.dart';
import '../app_lock/presentation/app_lock_settings_card.dart';
import '../app_lock/providers/app_lock_controller.dart';
import '../diary/data/diary_repository.dart';
import '../events/data/event_repository.dart';
import '../habits/data/habit_repository.dart';
import '../my_day/data/my_day_models.dart';
import '../my_day/providers/my_day_providers.dart';
import '../tasks/data/task_metadata.dart';
import '../tasks/data/task_repository.dart';
import 'data/mobile_reminder_service.dart';
import 'data/mobile_sync_client.dart';
import 'data/reminder_platform.dart';
import 'data/today_agenda.dart';
import 'data/today_widget_service.dart';
import 'pair_scanner_page.dart';

final _mobileEventsProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(databaseProvider).watchAllEvents();
});
final _mobileDiaryProvider = StreamProvider<List<DiaryEntry>>((ref) {
  return ref.watch(diaryRepositoryProvider).watchAll();
});

/// The day shown by the phone's Today tab. Null follows the real today so the
/// screen moves on after midnight.
final agendaDayProvider = StateProvider<DateTime?>((ref) => null);

/// Number of My Day items per day in the next 14 days, used by the Upcoming
/// list. The key is the `YYYY-MM-DD` plan key.
final mobileUpcomingPlanDaysProvider = FutureProvider.autoDispose
    .family<Map<String, int>, DateTime>((ref, from) async {
      final db = ref.watch(databaseProvider);
      final to = DayMath.addDays(from, 13);
      final rows = await db
          .customSelect(
            'SELECT p.day_key, COUNT(i.id) AS item_count '
            'FROM daily_plans p '
            'LEFT JOIN daily_plan_items i ON i.plan_id = p.id '
            'WHERE p.day_key >= ? AND p.day_key <= ? '
            'GROUP BY p.day_key',
            variables: [
              Variable.withString(myDayKey(from)),
              Variable.withString(myDayKey(to)),
            ],
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('day_key'): row.read<int>('item_count'),
      };
    });

/// Habit logs per day in the next 14 days, so the Upcoming list also shows a
/// day whose only entry is a habit tick.
final mobileUpcomingHabitDaysProvider = FutureProvider.autoDispose
    .family<Map<String, int>, DateTime>((ref, from) async {
      final db = ref.watch(databaseProvider);
      final to = DayMath.addDays(from, 14);
      final rows = await db
          .customSelect(
            'SELECT date, COUNT(*) AS habit_count '
            'FROM habit_logs WHERE date >= ? AND date < ? '
            'AND completed = 1 GROUP BY date',
            variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
          )
          .get();
      return {
        for (final row in rows)
          myDayKey(
            DateTime.fromMillisecondsSinceEpoch(row.read<int>('date') * 1000),
          ): row.read<int>(
            'habit_count',
          ),
      };
    });

class LocusMobileApp extends StatelessWidget {
  const LocusMobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Locus Planner',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5269A8)),
      useMaterial3: true,
    ),
    home: const _MobileHome(),
    builder: (context, child) =>
        AppLockGate(child: child ?? const SizedBox.shrink()),
  );
}

class _MobileHome extends ConsumerStatefulWidget {
  const _MobileHome();

  @override
  ConsumerState<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends ConsumerState<_MobileHome>
    with WidgetsBindingObserver {
  /// A phone that is not on the home network, or a desktop that is switched
  /// off, would otherwise be retried (and wait for a timeout) every time the
  /// app is opened.
  static const _autoSyncInterval = Duration(minutes: 1);

  int _index = 0;
  bool _syncing = false;
  DateTime? _lastAutoAttempt;
  late final MobileReminderService _reminders;
  StreamSubscription<String>? _tabSubscription;
  Timer? _widgetUpdateTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Event reminders follow the events table, so they also pick up rows that
    // a sync brings in.
    _reminders = ref.read(mobileReminderServiceProvider)..start();
    _tabSubscription = ref.read(reminderPlatformProvider).requestedTabs.listen((
      tab,
    ) {
      if (tab == 'tasks' && mounted) setState(() => _index = 1);
    });
    // Opening the app is the moment the user expects to see current data.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_autoSync());
      unawaited(ref.read(todayWidgetServiceProvider).update());
      final tab = await ref.read(reminderPlatformProvider).launchTab();
      if (tab == 'tasks' && mounted) setState(() => _index = 1);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetUpdateTimer?.cancel();
    unawaited(_tabSubscription?.cancel());
    unawaited(_reminders.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Moves the window of upcoming reminders forward.
      unawaited(_reminders.refresh());
      unawaited(_autoSync());
      unawaited(ref.read(todayWidgetServiceProvider).update());
    }
  }

  /// Coalesces database stream changes into one widget refresh.
  void _scheduleWidgetUpdate() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        unawaited(ref.read(todayWidgetServiceProvider).update());
      }
    });
  }

  /// Syncs quietly when the app is opened or returns to the foreground, if the
  /// phone is paired and has not synced in the last minute. Failures are not
  /// shown: being away from the desktop is normal, and the Sync tab still
  /// reports problems when the user syncs by hand.
  Future<void> _autoSync() async {
    if (_syncing || !mounted) return;
    final now = AppClock.now();
    final last = _lastAutoAttempt;
    if (last != null && now.difference(last) < _autoSyncInterval) return;
    _lastAutoAttempt = now;
    setState(() => _syncing = true);
    try {
      await ref
          .read(mobileSyncClientProvider)
          .syncIfDue(minInterval: _autoSyncInterval);
    } catch (_) {
      // Quiet by design; see above.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await ref.read(mobileSyncClientProvider).syncNow();
      if (mounted) _message(result);
    } catch (error) {
      if (mounted) _message('Sync failed: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _quickCapture() async {
    final selected = ref.read(agendaDayProvider);
    final now = AppClock.now();
    final day = selected == null ? now : DayMath.dateOnly(selected);
    final sameDay = DayMath.calendarDaysBetween(now, day) == 0;
    final start = sameDay ? now : DateTime(day.year, day.month, day.day, 9);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickCaptureSheet(initialStart: start),
    );
    if (saved == true && mounted) {
      _message(
        'Saved on this device. It will sync when you next open the app, '
        'or tap Sync now.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(_mobileEventsProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(tasksStreamProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(habitsStreamProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(
      habitLogsForDayProvider(DayMath.dateOnly(AppClock.now())),
      (_, _) => _scheduleWidgetUpdate(),
    );
    final pages = <Widget>[
      const _TodayScreen(),
      const _TasksScreen(),
      const _DiaryScreen(),
      _SyncScreen(syncing: _syncing, onSync: _syncNow),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locus'),
        actions: [
          IconButton(
            tooltip: 'Quick capture',
            onPressed: _quickCapture,
            icon: const Icon(Icons.add_circle_outline),
          ),
          if (_index == 3)
            IconButton(
              tooltip: 'Sync now',
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 0 || _index == 1
          ? FloatingActionButton(
              onPressed: _quickCapture,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Diary',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Sync',
          ),
        ],
      ),
    );
  }
}

class _TodayScreen extends ConsumerStatefulWidget {
  const _TodayScreen();

  @override
  ConsumerState<_TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<_TodayScreen> {
  /// How many days ahead the phone can browse. A week covers the quick-access
  /// planning horizon of the Today tab.
  static const _upcomingDays = 7;
  static const _upcomingListDays = 14;

  bool _upcomingMode = false;

  static DateTime _today() {
    final now = AppClock.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _day {
    final selected = ref.read(agendaDayProvider);
    return selected == null ? _today() : DayMath.dateOnly(selected);
  }

  bool get _isToday => DayMath.calendarDaysBetween(_today(), _day) == 0;

  bool get _isPast => DayMath.calendarDaysBetween(_today(), _day) < 0;

  void _selectDay(DateTime day) {
    ref.read(agendaDayProvider.notifier).state = DayMath.dateOnly(day);
  }

  void _shiftDay(int delta) => _selectDay(DayMath.addDays(_day, delta));

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(_today().year + 5, 12, 31),
    );
    if (picked != null && mounted) _selectDay(picked);
  }

  String _dayLabel() {
    final difference = DayMath.calendarDaysBetween(_today(), _day);
    return switch (difference) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => DateFormat('EEE d MMM').format(_day),
    };
  }

  Future<void> _editIntention(DailyPlanView plan) async {
    final controller = TextEditingController(text: plan.intention);
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily intention'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'What matters most on this day?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).setIntention(_day, text),
      failureMessage: 'Could not save the daily intention.',
    );
  }

  Future<void> _showDayReview(DailyPlanView plan) async {
    final done = plan.items
        .where((item) => item.completed || item.doneToday)
        .toList();
    final unfinished = plan.items
        .where((item) => !item.completed && !item.doneToday)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End of day review'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: ListView(
            children: [
              Text(
                '${plan.completedCount} of ${plan.items.length} tasks done'
                '${plan.completedMinutes > 0 ? ' · ${plan.completedMinutes} min completed' : ''}',
                style: Theme.of(dialogContext).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              if (done.isNotEmpty) ...[
                Text(
                  'Completed',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                for (final item in done)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle, size: 20),
                    title: Text(
                      item.title,
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    subtitle: Text(
                      item.doneToday && !item.completed
                          ? 'Done today'
                          : item.plannedMinutes == null
                          ? 'Duration unknown'
                          : '${item.plannedMinutes} min',
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              Text('Unfinished', style: Theme.of(context).textTheme.labelLarge),
              if (unfinished.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Everything planned for this day is done.'),
                )
              else
                for (final item in unfinished)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.radio_button_unchecked, size: 20),
                    title: Text(item.title),
                    subtitle: Text(
                      item.plannedMinutes == null
                          ? 'Duration unknown'
                          : '${item.plannedMinutes} min',
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _addPlannedTask() async {
    final picked = await showModalBottomSheet<PlannableTaskView>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MyDayTaskPickerSheet(day: _day),
    );
    if (picked == null || !mounted) return;
    final added = await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).addTask(_day, picked),
      failureMessage: 'Could not add the task to My Day.',
    );
    if (added && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Added “${picked.title}”')));
    }
  }

  Future<void> _togglePlanned(PlannedTaskView item, bool completed) {
    return runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).setCompleted(item, completed),
      failureMessage: 'Could not update the task.',
    );
  }

  Future<void> _removePlanned(PlannedTaskView item) {
    return runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).removeItem(item),
      failureMessage: 'Could not remove the task from My Day.',
    );
  }

  Future<void> _reorderPlanned(DailyPlanView plan, int oldIndex, int newIndex) {
    final reordered = [...plan.items];
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    return runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).reorder(reordered),
      failureMessage: 'Could not save the new order.',
    );
  }

  Widget? _plannedSubtitle(PlannedTaskView item) {
    final parts = <String>[
      if (item.projectName != null) item.projectName!,
      if (item.dueDate != null)
        'Due ${DateFormat.yMMMd().format(item.dueDate!)}',
      item.plannedMinutes == null
          ? 'Estimate unknown'
          : '${item.plannedMinutes} min',
    ];
    return Text(
      parts.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(agendaDayProvider);
    final today = _today();
    final events = ref.watch(_mobileEventsProvider);
    final habits = ref.watch(habitsStreamProvider);
    final myDay = ref.watch(myDayDayViewProvider(_day));
    final habitLogs = ref.watch(habitLogsForDayProvider(_day));
    final planDays = ref.watch(mobileUpcomingPlanDaysProvider(today));
    final habitDays = ref.watch(mobileUpcomingHabitDaysProvider(today));
    final completedHabitIds = <String>{
      for (final log in habitLogs.valueOrNull ?? const <HabitLog>[])
        if (log.completed) log.habitId,
    };

    if (_upcomingMode) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _dayHeader(context),
          const SizedBox(height: 12),
          _upcomingView(context, today, events, planDays, habitDays),
        ],
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 250) {
          _shiftDay(-1);
        } else if (velocity < -250) {
          _shiftDay(1);
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _dayHeader(context),
          const SizedBox(height: 6),
          _dayStrip(today),
          const SizedBox(height: 16),
          Text(
            _isToday
                ? 'Your agenda'
                : 'Agenda for ${DateFormat('EEE d MMM').format(_day)}',
          ),
          const SizedBox(height: 12),
          events.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Could not load agenda: $error'),
            data: (all) {
              final dayEvents = agendaForDay(all, _day);
              if (dayEvents.isEmpty) {
                return _EmptyCard(
                  message: _isToday
                      ? 'Nothing scheduled today. Use + to add an event.'
                      : 'Nothing scheduled on this day.',
                );
              }
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < dayEvents.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        leading: const Icon(Icons.event_outlined),
                        textColor:
                            _isPast ||
                                (_isToday &&
                                    dayEvents[i].start.isBefore(AppClock.now()))
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                        iconColor:
                            _isPast ||
                                (_isToday &&
                                    dayEvents[i].start.isBefore(AppClock.now()))
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                        title: Text(dayEvents[i].event.title),
                        subtitle: Text(
                          dayEvents[i].event.allDay
                              ? dayEvents[i].isRecurring
                                    ? 'All day · ${Recurrence.label(dayEvents[i].event.recurrenceRule)}'
                                    : 'All day'
                              : dayEvents[i].isRecurring
                              ? '${DateFormat('h:mm a').format(dayEvents[i].start)}'
                                    ' · ${Recurrence.label(dayEvents[i].event.recurrenceRule)}'
                              : DateFormat('h:mm a').format(dayEvents[i].start),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (dayEvents[i].isRecurring)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.repeat, size: 18),
                              ),
                            if (dayEvents[i].event.hasReminder)
                              const Icon(
                                Icons.notifications_active_outlined,
                                size: 20,
                              ),
                          ],
                        ),
                        onTap: () =>
                            _editEvent(context, ref, dayEvents[i].event),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'My Day',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _isPast ? null : _addPlannedTask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add task'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          myDay.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Could not load My Day: $error'),
            data: (plan) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileIntentionCard(
                  plan: plan,
                  onEdit: _isPast ? null : () => _editIntention(plan),
                ),
                const SizedBox(height: 8),
                if (plan.items.isEmpty)
                  const _EmptyCard(
                    message:
                        'No tasks planned yet. Add one from your existing tasks.',
                  )
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      itemCount: plan.items.length,
                      onReorderItem: _isPast
                          ? (_, _) {}
                          : (oldIndex, newIndex) =>
                                _reorderPlanned(plan, oldIndex, newIndex),
                      itemBuilder: (context, index) {
                        final item = plan.items[index];
                        final done = item.completed || item.doneToday;
                        return ListTile(
                          key: ValueKey('my-day-item-${item.planItemId}'),
                          leading: Checkbox(
                            value: done,
                            onChanged: item.doneToday && !item.completed
                                ? null
                                : (value) =>
                                      _togglePlanned(item, value ?? false),
                          ),
                          title: Text(
                            item.title,
                            style: TextStyle(
                              decoration: done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          subtitle: _plannedSubtitle(item),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isPast)
                                IconButton(
                                  tooltip: 'Remove from My Day',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => _removePlanned(item),
                                ),
                              if (!_isPast)
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_handle),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                FutureBuilder<MobileSyncStatus>(
                  future: ref.read(mobileSyncClientProvider).status(),
                  builder: (context, snapshot) {
                    final status = snapshot.data;
                    final label =
                        snapshot.connectionState == ConnectionState.waiting
                        ? 'Checking sync status…'
                        : status == null || !status.paired
                        ? 'Not paired with a desktop yet'
                        : status.lastSync == null
                        ? 'Paired · no sync yet'
                        : 'Last sync ${DateFormat('d MMM, HH:mm').format(status.lastSync!)}';
                    return Row(
                      children: [
                        Icon(
                          status?.paired == true
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (plan.items.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _showDayReview(plan),
                      icon: const Icon(Icons.fact_check_outlined, size: 18),
                      label: const Text('Review day'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isToday
                      ? 'Habits'
                      : 'Habits on ${DateFormat('EEE d MMM').format(_day)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: _showHabitDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New habit'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          habits.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Could not load habits: $error'),
            data: (all) {
              if (all.isEmpty) {
                return const _EmptyCard(
                  message:
                      'No habits yet. Add one here, or on the desktop and sync.',
                );
              }
              final items = all.toList()
                ..sort(
                  (a, b) =>
                      a.name.toLowerCase().compareTo(b.name.toLowerCase()),
                );
              final futureDay = DayMath.calendarDaysBetween(today, _day) > 0;
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 12, endIndent: 12),
                      _HabitTile(
                        key: ValueKey('habit-${items[i].id}'),
                        habit: items[i],
                        day: _day,
                        completed: completedHabitIds.contains(items[i].id),
                        disabled: habitLogs.isLoading || futureDay,
                        onToggle: () => ref
                            .read(habitRepositoryProvider)
                            .toggleDay(
                              items[i],
                              _day,
                              completedHabitIds.contains(items[i].id),
                            ),
                        onEdit: () => _showHabitDialog(existing: items[i]),
                        onDelete: () => _deleteHabit(items[i]),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Quick tip', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'Your data stays on this phone until you pair it with your desktop and tap Sync now.',
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: () => _shiftDay(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: InkWell(
            onTap: _pickDay,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  Text(
                    _dayLabel(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    DateFormat('EEEE, d MMMM').format(_day),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: () => _shiftDay(1),
          icon: const Icon(Icons.chevron_right),
        ),
        if (!_isToday)
          TextButton(
            onPressed: () => _selectDay(_today()),
            child: const Text('Today'),
          ),
        IconButton(
          tooltip: _upcomingMode ? 'Day view' : 'Upcoming',
          onPressed: () => setState(() => _upcomingMode = !_upcomingMode),
          icon: Icon(_upcomingMode ? Icons.view_day : Icons.upcoming_outlined),
        ),
      ],
    );
  }

  Widget _dayStrip(DateTime today) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _upcomingDays,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final day = DayMath.addDays(today, index);
          final selected = DayMath.calendarDaysBetween(day, _day) == 0;
          return ChoiceChip(
            key: ValueKey('agenda-day-$index'),
            label: Text(
              index == 0
                  ? 'Today'
                  : index == 1
                  ? 'Tomorrow'
                  : DateFormat('EEE d').format(day),
            ),
            selected: selected,
            onSelected: (_) => _selectDay(day),
          );
        },
      ),
    );
  }

  Widget _upcomingView(
    BuildContext context,
    DateTime today,
    AsyncValue<List<Event>> events,
    AsyncValue<Map<String, int>> planDays,
    AsyncValue<Map<String, int>> habitDays,
  ) {
    final eventDays = <String, int>{};
    for (final event in events.valueOrNull ?? const <Event>[]) {
      for (var offset = 0; offset < _upcomingListDays; offset++) {
        final day = DayMath.addDays(today, offset);
        final count = agendaForDay([event], day).length;
        if (count == 0) continue;
        final key = myDayKey(day);
        eventDays[key] = (eventDays[key] ?? 0) + count;
      }
    }
    final plans = planDays.valueOrNull ?? const <String, int>{};
    final habits = habitDays.valueOrNull ?? const <String, int>{};
    final keys = {...eventDays.keys, ...plans.keys, ...habits.keys}.toList()
      ..sort();
    if (keys.isEmpty) {
      return const _EmptyCard(message: 'Nothing planned in the next 14 days.');
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Builder(
              builder: (context) {
                final day = DateTime.parse(keys[i]);
                final eventCount = eventDays[keys[i]] ?? 0;
                final taskCount = plans[keys[i]] ?? 0;
                final habitCount = habits[keys[i]] ?? 0;
                return ListTile(
                  title: Text(DateFormat('EEE d MMM').format(day)),
                  subtitle: Text(
                    [
                      if (eventCount > 0)
                        '$eventCount event${eventCount == 1 ? '' : 's'}',
                      if (taskCount > 0)
                        '$taskCount task${taskCount == 1 ? '' : 's'}',
                      if (habitCount > 0)
                        '$habitCount habit${habitCount == 1 ? '' : 's'}',
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _selectDay(day);
                    setState(() => _upcomingMode = false);
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showHabitDialog({Habit? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final icon = TextEditingController(text: existing?.icon ?? '🔥');
    var target = existing?.targetPerWeek ?? 5;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DisposeWith(
        disposables: [name, icon],
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New habit' : 'Edit habit'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const ValueKey('habit-name'),
                  controller: name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('habit-icon'),
                  controller: icon,
                  maxLength: 4,
                  decoration: const InputDecoration(labelText: 'Icon'),
                ),
                const SizedBox(height: 4),
                DropdownButtonFormField<int>(
                  initialValue: target,
                  decoration: const InputDecoration(labelText: 'Weekly target'),
                  items: [
                    for (var value = 1; value <= 7; value++)
                      DropdownMenuItem(
                        value: value,
                        child: Text('$value× per week'),
                      ),
                  ],
                  onChanged: (value) =>
                      setDialogState(() => target = value ?? target),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(existing == null ? 'Create' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) {
      return;
    }
    final repository = ref.read(habitRepositoryProvider);
    try {
      if (existing == null) {
        await repository.create(
          name: name.text.trim(),
          icon: icon.text.trim().isEmpty ? '🔥' : icon.text.trim(),
          targetPerWeek: target,
        );
      } else {
        await repository.update(
          existing.copyWith(
            name: name.text.trim(),
            icon: icon.text.trim().isEmpty ? '🔥' : icon.text.trim(),
            targetPerWeek: target,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save habit: $error')));
      }
    }
  }

  Future<void> _deleteHabit(Habit habit) async {
    await ref.read(habitRepositoryProvider).delete(habit.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Deleted “${habit.name}”'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => ref.read(undoServiceProvider).undo(),
          ),
        ),
      );
  }

  Future<void> _editEvent(
    BuildContext context,
    WidgetRef ref,
    Event event,
  ) async {
    final syncClient = ref.read(mobileSyncClientProvider);
    final result = await showDialog<_EventEditResult>(
      context: context,
      builder: (_) => _EventEditDialog(
        event: event,
        start: event.startTime,
        onDownload: (attachment) => syncClient.downloadAttachment(
          attachment.sha256,
          kind: attachment.kind,
        ),
        onKeep: (attachment, pinned) =>
            syncClient.pinAttachment(attachment.sha256, pinned),
      ),
    );
    if (result == null) return;

    final db = ref.read(databaseProvider);
    if (result.skipOccurrence != null) {
      await ref
          .read(eventRepositoryProvider)
          .update(
            event.copyWith(
              recurrenceExceptions: Recurrence.addException(
                event.recurrenceExceptions,
                result.skipOccurrence!,
              ),
            ),
          );
      return;
    }
    if (result.delete) {
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete event?'),
          content: Text(
            event.recurrenceRule == null ||
                    event.recurrenceRule == Recurrence.none
                ? '“${event.title}” will be removed from this phone.'
                : 'Every repeat of “${event.title}” will be removed from this '
                      'phone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        await (db.delete(
          db.events,
        )..where((row) => row.id.equals(event.id))).go();
      }
      return;
    }

    final title = result.title?.trim() ?? '';
    if (title.isEmpty) return;
    await ref
        .read(eventRepositoryProvider)
        .update(
          event.copyWith(
            title: title,
            description: Value(result.description),
            descriptionFormat: result.descriptionFormat,
            startTime: result.start ?? event.startTime,
            allDay: result.allDay,
            hasReminder: result.allDay ? false : event.hasReminder,
            recurrenceRule: Value(
              result.recurrenceRule ?? event.recurrenceRule,
            ),
          ),
        );
  }
}

class _MobileIntentionCard extends StatelessWidget {
  const _MobileIntentionCard({required this.plan, required this.onEdit});

  final DailyPlanView plan;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intention = plan.intention.trim();
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.wb_sunny_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          intention.isEmpty ? 'Set a daily intention' : intention,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: intention.isEmpty
              ? theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : null,
        ),
        subtitle: Text(
          'What you want to accomplish on this day',
          style: theme.textTheme.bodySmall,
        ),
        trailing: IconButton(
          tooltip: 'Edit daily intention',
          icon: const Icon(Icons.edit_outlined),
          onPressed: onEdit,
        ),
      ),
    );
  }
}

/// Bottom-sheet picker for existing to-dos and project checklist tasks.
class _MyDayTaskPickerSheet extends ConsumerStatefulWidget {
  const _MyDayTaskPickerSheet({required this.day});

  final DateTime day;

  @override
  ConsumerState<_MyDayTaskPickerSheet> createState() =>
      _MyDayTaskPickerSheetState();
}

class _MyDayTaskPickerSheetState extends ConsumerState<_MyDayTaskPickerSheet> {
  late Future<List<PlannableTaskView>> _tasks;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tasks = ref.read(myDayControllerProvider).plannableTasks(widget.day);
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add to My Day · ${DateFormat('EEE d MMM').format(widget.day)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search tasks',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: FutureBuilder<List<PlannableTaskView>>(
                  future: _tasks,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('Could not load tasks: ${snapshot.error}'),
                      );
                    }
                    final all = snapshot.data ?? const <PlannableTaskView>[];
                    final visible = query.isEmpty
                        ? all
                        : all
                              .where(
                                (task) =>
                                    task.title.toLowerCase().contains(query) ||
                                    (task.projectName?.toLowerCase().contains(
                                          query,
                                        ) ??
                                        false),
                              )
                              .toList();
                    if (visible.isEmpty) {
                      return const Center(child: Text('No matching tasks.'));
                    }
                    return ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final task = visible[index];
                        return ListTile(
                          enabled: !task.alreadyPlanned,
                          leading: const Icon(Icons.task_alt),
                          title: Text(task.title),
                          subtitle: Text(
                            [
                              if (task.projectName != null) task.projectName!,
                              if (task.dueDate != null)
                                'Due ${DateFormat.yMMMd().format(task.dueDate!)}',
                            ].join(' · '),
                          ),
                          trailing: task.alreadyPlanned
                              ? const Icon(Icons.check_circle_outline)
                              : const Icon(Icons.add_circle_outline),
                          onTap: task.alreadyPlanned
                              ? null
                              : () => Navigator.pop(context, task),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the event editor returns. A null result means the user cancelled.
class _EventEditResult {
  const _EventEditResult({
    this.title,
    this.description,
    this.descriptionFormat = 'plain',
    this.start,
    this.allDay = false,
    this.delete = false,
    this.recurrenceRule,
    this.skipOccurrence,
  });

  final String? title;
  final String? description;
  final String descriptionFormat;
  final DateTime? start;
  final bool allDay;
  final bool delete;
  final String? recurrenceRule;
  final DateTime? skipOccurrence;
}

class _EventEditDialog extends StatefulWidget {
  const _EventEditDialog({
    required this.event,
    required this.start,
    this.onDownload,
    this.onKeep,
  });

  final Event event;
  final DateTime start;
  final Future<bool> Function(Attachment attachment)? onDownload;
  final Future<void> Function(Attachment attachment, bool pinned)? onKeep;

  @override
  State<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends State<_EventEditDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _descriptionController;
  late DateTime _start;
  late bool _allDay;
  late String _recurrenceRule;
  late String _descriptionFormat;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.event.title);
    _descriptionController = TextEditingController(
      text: widget.event.description ?? '',
    );
    _start = widget.start;
    _allDay = widget.event.allDay;
    _recurrenceRule = widget.event.recurrenceRule ?? Recurrence.none;
    _descriptionFormat = widget.event.descriptionFormat;
  }

  @override
  void dispose() {
    _controller.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(
      () => _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recurring = Recurrence.isRecurring(widget.event.recurrenceRule);
    return AlertDialog(
      title: const Text('Edit event'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          NotesField(
            controller: _descriptionController,
            format: _descriptionFormat,
            onFormatChanged: (value) =>
                setState(() => _descriptionFormat = value),
            label: 'Description',
            hint: 'Agenda, location, links…',
            minLines: 2,
            maxLines: 4,
          ),
          const SizedBox(height: 8),
          AttachmentStrip(
            eventId: widget.event.id,
            onDownload: widget.onDownload,
            onKeep: widget.onKeep,
          ),
          const SizedBox(height: 8),
          if (!_allDay)
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEE d MMM yyyy, h:mm a').format(_start)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (value) => setState(() {
              _allDay = value;
              if (value) {
                _start = DateTime(_start.year, _start.month, _start.day);
              }
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _recurrenceRule,
            items: Recurrence.values
                .map(
                  (rule) => DropdownMenuItem(
                    value: rule,
                    child: Text(Recurrence.label(rule)),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _recurrenceRule = value ?? Recurrence.none),
            decoration: const InputDecoration(labelText: 'Repeat'),
          ),
          if (recurring) ...[
            const SizedBox(height: 8),
            Text(
              'Changes apply to every repeat. Skip this occurrence to remove '
              'only the selected day.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _EventEditResult(skipOccurrence: widget.start),
                ),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Skip this occurrence'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(context, const _EventEditResult(delete: true)),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _EventEditResult(
              title: _controller.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              descriptionFormat: _descriptionController.text.trim().isEmpty
                  ? 'plain'
                  : _descriptionFormat,
              start: _start,
              allDay: _allDay,
              recurrenceRule: _recurrenceRule,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _TasksScreen extends ConsumerWidget {
  const _TasksScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksStreamProvider);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text('To-do list', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        tasks.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load tasks: $error'),
          data: (items) {
            if (items.isEmpty) {
              return const _EmptyCard(
                message: 'No tasks yet. Tap + to capture one.',
              );
            }
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 12, endIndent: 12),
                    ListTile(
                      contentPadding: EdgeInsets.fromLTRB(
                        12 + _mobileTaskDepth(items[i], items) * 16,
                        4,
                        16,
                        4,
                      ),
                      leading: Checkbox(
                        value: items[i].completed,
                        onChanged: (value) => ref
                            .read(taskRepositoryProvider)
                            .toggle(items[i].id, value ?? false),
                      ),
                      title: Row(
                        children: [
                          if (items[i].parentId != null)
                            const Padding(
                              padding: EdgeInsets.only(right: 4),
                              child: Icon(
                                Icons.subdirectory_arrow_right,
                                size: 16,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              items[i].title,
                              style: TextStyle(
                                decoration: items[i].completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: _mobileTaskSubtitle(items[i]),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Task actions',
                        onSelected: (value) async {
                          if (value != 'delete') return;
                          final task = items[i];
                          final repository = ref.read(taskRepositoryProvider);
                          final subtree = await repository.deleteCascade(task);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('Deleted “${task.title}”'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () =>
                                      repository.restoreSubtree(subtree),
                                ),
                              ),
                            );
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () => _editTask(context, ref, items[i]),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  static int _mobileTaskDepth(TodoItem task, List<TodoItem> all) {
    final byId = {for (final item in all) item.id: item};
    final seen = <String>{task.id};
    var depth = 0;
    var parent = task.parentId;
    while (parent != null && byId.containsKey(parent) && seen.add(parent)) {
      depth++;
      parent = byId[parent]!.parentId;
    }
    return depth;
  }

  static Widget? _mobileTaskSubtitle(TodoItem task) {
    final lines = <String>[
      if (task.notes != null && task.notes!.isNotEmpty) task.notes!,
      if (task.startDate != null)
        'Starts ${DateFormat.yMMMd().format(task.startDate!)}',
      if (task.dueDate != null)
        'Due ${DateFormat.yMMMd().format(task.dueDate!)}',
      if (!TaskSchedule.isScheduled(task)) 'Unscheduled',
      if (task.reminderAt != null)
        'Reminder ${DateFormat('MMM d · HH:mm').format(task.reminderAt!)}',
    ];
    if (lines.isEmpty) return null;
    return Text(
      lines.join(' · '),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    TodoItem item,
  ) async {
    final completions = await ref
        .read(taskRepositoryProvider)
        .completionsFor(item.id);
    if (!context.mounted) return;
    final syncClient = ref.read(mobileSyncClientProvider);
    final result = await showDialog<_TaskEditResult>(
      context: context,
      builder: (_) => _MobileTaskEditDialog(
        todoId: item.id,
        title: item.title,
        notes: item.notes,
        notesFormat: item.notesFormat,
        completions: completions,
        onDownload: (attachment) => syncClient.downloadAttachment(
          attachment.sha256,
          kind: attachment.kind,
        ),
        onKeep: (attachment, pinned) =>
            syncClient.pinAttachment(attachment.sha256, pinned),
      ),
    );
    if (result == null || result.title.isEmpty) return;

    // Preserve every field the mobile editor does not expose so saving the
    // title cannot erase dates, tags, reminder or project metadata.
    await ref
        .read(taskRepositoryProvider)
        .update(
          id: item.id,
          title: result.title,
          notes: result.notes,
          notesFormat: result.notesFormat,
          startDate: item.startDate,
          dueDate: item.dueDate,
          priority: TaskPriority.fromStorage(item.priority),
          tags: TaskTags.decode(item.tags),
          recurrenceRule: item.recurrenceRule,
          parentId: item.parentId,
          projectId: item.projectId,
          reminderAt: item.reminderAt,
        );
  }
}

class _TaskEditResult {
  const _TaskEditResult({
    required this.title,
    required this.notesFormat,
    this.notes,
  });

  final String title;
  final String? notes;
  final String notesFormat;
}

/// Owns its text controllers so they are disposed with the dialog route,
/// after the exit animation, rather than while the fields still reference them.
class _MobileTaskEditDialog extends StatefulWidget {
  const _MobileTaskEditDialog({
    required this.todoId,
    required this.title,
    required this.notesFormat,
    this.notes,
    this.completions = const [],
    this.onDownload,
    this.onKeep,
  });

  final String todoId;
  final Future<bool> Function(Attachment attachment)? onDownload;
  final Future<void> Function(Attachment attachment, bool pinned)? onKeep;
  final String title;
  final String? notes;
  final String notesFormat;
  final List<TodoCompletion> completions;

  @override
  State<_MobileTaskEditDialog> createState() => _MobileTaskEditDialogState();
}

class _MobileTaskEditDialogState extends State<_MobileTaskEditDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.title,
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.notes ?? '',
  );
  late String _notesFormat = widget.notesFormat;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.completions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Completed ${widget.completions.length} '
                    'time${widget.completions.length == 1 ? '' : 's'}, last on '
                    '${DateFormat.yMMMd().format(widget.completions.first.completedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            NotesField(
              controller: _notesController,
              format: _notesFormat,
              onFormatChanged: (value) => setState(() => _notesFormat = value),
              minLines: 2,
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            AttachmentStrip(
              todoId: widget.todoId,
              onDownload: widget.onDownload,
              onKeep: widget.onKeep,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final notes = _notesController.text.trim();
            Navigator.pop(
              context,
              _TaskEditResult(
                title: _titleController.text.trim(),
                notes: notes.isEmpty ? null : notes,
                notesFormat: notes.isEmpty ? 'plain' : _notesFormat,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DiaryScreen extends ConsumerStatefulWidget {
  const _DiaryScreen();
  @override
  ConsumerState<_DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<_DiaryScreen>
    with WidgetsBindingObserver {
  /// How long typing has to pause before the entry is written.
  static const _autosaveDelay = Duration(milliseconds: 900);

  final _controller = TextEditingController();
  int _mood = 3;
  String? _loadedId;
  String? _loadedDay;
  bool _saving = false;
  bool _dirty = false;
  bool _suppressListener = false;
  DiaryEntry? _entry;
  DateTime? _savedAt;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android can stop the process while the app is in the background; write
    // what is already typed instead of relying on the debounce timer.
    if (state == AppLifecycleState.paused) unawaited(_save());
  }

  void _onTextChanged() {
    if (_suppressListener) return;
    _markDirty();
  }

  void _markDirty() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(_autosaveDelay, () => unawaited(_save()));
  }

  DateTime _today() {
    final now = AppClock.now();
    return DateTime(now.year, now.month, now.day);
  }

  String get _statusText {
    if (_saving) return 'Saving…';
    if (_dirty) return 'Unsaved changes';
    final savedAt = _savedAt;
    if (savedAt != null) return 'Saved at ${DateFormat.jm().format(savedAt)}';
    if (_entry != null) return 'Saved on this device';
    return 'Changes save automatically';
  }

  /// Writes the current diary entry. Autosave runs quietly; [force] is the
  /// explicit Save button and reports the result.
  Future<void> _save({bool force = false}) async {
    _saveTimer?.cancel();
    if (_saving) {
      // A save is already in flight. If more was typed meanwhile, try again
      // shortly after it finishes.
      if (_dirty) {
        _saveTimer = Timer(
          const Duration(milliseconds: 400),
          () => unawaited(_save()),
        );
      }
      return;
    }
    if (!_dirty && !force) return;

    final content = _controller.text.trim();
    final hadEntry = _entry != null;
    if (content.isEmpty && !hadEntry) {
      // Typing and then deleting everything should not leave an empty row.
      _dirty = false;
      if (force && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Nothing to save yet.')));
      }
      if (mounted) setState(() {});
      return;
    }

    final date = _today();
    final mood = _mood;
    _dirty = false;
    setState(() => _saving = true);
    try {
      await ref
          .read(diaryRepositoryProvider)
          .save(date: date, mood: mood, content: content);
      if (!mounted) return;
      setState(() => _savedAt = AppClock.now());
      if (force) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diary saved locally. Sync to share it.'),
          ),
        );
      }
    } catch (error) {
      _dirty = true;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save diary: $error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = ref.watch(_mobileDiaryProvider);
    return entries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Could not load diary: $error')),
      data: (all) {
        final matchingEntries = all
            .where(
              (item) =>
                  item.date.year == today.year &&
                  item.date.month == today.month &&
                  item.date.day == today.day,
            )
            .toList();
        final entry = matchingEntries.isEmpty ? null : matchingEntries.first;
        final dayKey = today.toIso8601String();
        if (_loadedDay != dayKey) {
          _loadedDay = dayKey;
          _savedAt = null;
        }
        final identity = entry?.id ?? 'new-$dayKey';
        if (_loadedId != identity) {
          _loadedId = identity;
          _entry = entry;
          // A save can create the row and therefore change the identity while
          // the user keeps typing. Only reload the field when there are no
          // unsaved edits, and never move the cursor for identical text.
          if (!_dirty) {
            final text = entry?.content ?? '';
            if (_controller.text != text) {
              _suppressListener = true;
              _controller.text = text;
              _suppressListener = false;
            }
            _mood = entry?.mood ?? 3;
          }
        } else {
          _entry = entry;
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Daily diary', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(DateFormat('EEEE, d MMMM yyyy').format(now)),
            const SizedBox(height: 18),
            const Text('How are you feeling?'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final mood in [
                  (1, '😞'),
                  (2, '😐'),
                  (3, '🙂'),
                  (4, '😊'),
                  (5, '🤩'),
                ])
                  ChoiceChip(
                    label: Text(mood.$2),
                    selected: _mood == mood.$1,
                    onSelected: (_) {
                      if (_mood == mood.$1) return;
                      setState(() => _mood = mood.$1);
                      _markDirty();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 8,
              maxLines: 16,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Write a few thoughts about today…',
              ),
            ),
            const SizedBox(height: 12),
            Text(_statusText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : () => _save(force: true),
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save now'),
            ),
          ],
        );
      },
    );
  }
}

class _SyncScreen extends ConsumerStatefulWidget {
  const _SyncScreen({required this.syncing, required this.onSync});
  final bool syncing;
  final Future<void> Function() onSync;
  @override
  ConsumerState<_SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<_SyncScreen> {
  final _hostController = TextEditingController();
  final _codeController = TextEditingController();
  bool _pairing = false;
  MobileSyncStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await ref.read(mobileSyncClientProvider).status();
    if (mounted) setState(() => _status = status);
  }

  /// Runs a pairing flow. [action] returns false when the user backed out.
  Future<void> _runPairing(Future<bool> Function() action) async {
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final paired = await action();
      if (!paired) return;
      _codeController.clear();
      await _refreshStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone paired. Tap Sync now to exchange data.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  /// Scanning is the safest path: the QR code carries the desktop's address,
  /// the one-time code and the certificate fingerprint, so nothing is typed
  /// and nothing can be swapped.
  Future<bool> _pairFromQr() async {
    return ref.read(appLockControllerProvider.notifier).runExternal(() async {
      final result = await Navigator.of(context).push<PairScanResult>(
        MaterialPageRoute(builder: (_) => const PairScannerPage()),
      );
      if (result is PairScanManualEntry) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enter the desktop address and pairing code below.',
              ),
            ),
          );
        }
        return false;
      }
      if (result is! PairScanSuccess) return false;
      final payload = result.payload;
      await ref
          .read(mobileSyncClientProvider)
          .pair(
            host: '${payload.host}:${payload.port}',
            code: payload.code,
            fingerprint: payload.fingerprint,
          );
      return true;
    });
  }

  /// Manual pairing: read the certificate fingerprint from the desktop, have
  /// the user confirm it matches the one shown there, then pair.
  Future<bool> _pairManually() async {
    final client = ref.read(mobileSyncClientProvider);
    final host = _hostController.text;
    final fingerprint = await client.fetchDesktopFingerprint(host);
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Is this your desktop?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Locus on your desktop shows a security fingerprint next to the '
              'pairing code. Pair only if it starts with exactly these '
              'characters:',
            ),
            const SizedBox(height: 12),
            SelectableText(
              shortSyncFingerprint(fingerprint),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('They match'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await client.pair(
      host: host,
      code: _codeController.text,
      fingerprint: fingerprint,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Device sync', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Connect to Locus on your desktop while both devices are on the same trusted Wi-Fi network.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(status?.paired == true ? Icons.link : Icons.link_off),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status?.paired == true
                            ? 'Paired with ${status!.host}'
                            : 'Not paired',
                      ),
                    ),
                  ],
                ),
                if (status?.lastSync != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Last sync: ${DateFormat.yMMMd().add_jm().format(status!.lastSync!.toLocal())}',
                    ),
                  ),
                const SizedBox(height: 16),
                if (status?.needsRepair == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Sync now uses a verified, encrypted connection. Pair '
                      'this phone with the desktop again.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _pairing ? null : () => _runPairing(_pairFromQr),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(
                    _pairing ? 'Pairing…' : 'Scan QR code on desktop',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No camera? Enter the details instead.',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Desktop IP address',
                    hintText: '192.168.1.20:43821',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'One-time pairing code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pairing ? null : () => _runPairing(_pairManually),
                  icon: const Icon(Icons.phonelink_setup),
                  label: const Text('Pair with entered details'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () async {
                          await widget.onSync();
                          await _refreshStatus();
                        },
                  icon: widget.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(widget.syncing ? 'Syncing…' : 'Sync now'),
                ),
                if (status?.paired == true)
                  TextButton(
                    onPressed: () async {
                      await ref.read(mobileSyncClientProvider).unpair();
                      await _refreshStatus();
                    },
                    child: const Text('Forget pairing on this phone'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _RemindersCard(),
        const SizedBox(height: 12),
        const AppLockSettingsCard(),
        const SizedBox(height: 12),
        const _EmptyCard(
          message:
              'Locus syncs when you open the app or bring it back to the '
              'foreground, and when you tap Sync now. There is no background '
              'sync while the app is closed; open it once before relying on '
              'changes made on the desktop.',
        ),
        const SizedBox(height: 12),
        const _EmptyCard(
          message:
              'Pairing uses the one-time code in desktop Settings → Device Sync (LAN). Sync is encrypted with HTTPS and pins the desktop certificate, so other devices on the network cannot read or impersonate it. Only use a trusted private Wi-Fi network, never public Wi-Fi.',
        ),
      ],
    );
  }
}

class _RemindersCard extends ConsumerStatefulWidget {
  const _RemindersCard();

  @override
  ConsumerState<_RemindersCard> createState() => _RemindersCardState();
}

class _RemindersCardState extends ConsumerState<_RemindersCard>
    with WidgetsBindingObserver {
  ReminderCapabilities? _capabilities;
  bool _enabled = true;
  bool _tasksEnabled = true;
  bool _exactEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from one of Android's settings screens: show what changed there.
    if (state == AppLifecycleState.resumed) unawaited(_load());
  }

  Future<void> _load() async {
    final service = ref.read(mobileReminderServiceProvider);
    final enabled = await service.isEnabled();
    final tasksEnabled = await service.tasksEnabled();
    final capabilities = await ref
        .read(reminderPlatformProvider)
        .capabilities();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _tasksEnabled = tasksEnabled;
      _exactEnabled = capabilities.exactAlarmsEnabled;
      _capabilities = capabilities;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await ref.read(mobileReminderServiceProvider).setEnabled(value);
  }

  Future<void> _setTasksEnabled(bool value) async {
    setState(() => _tasksEnabled = value);
    await ref.read(mobileReminderServiceProvider).setTasksEnabled(value);
  }

  Future<void> _setExactEnabled(bool value) async {
    setState(() => _exactEnabled = value);
    await ref.read(reminderPlatformProvider).setExactAlarmsEnabled(value);
    await _load();
  }

  Future<void> _allowNotifications() async {
    await ref
        .read(appLockControllerProvider.notifier)
        .runExternal(
          () => ref
              .read(reminderPlatformProvider)
              .requestNotificationPermission(),
        );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    // Nothing to show until the Android side has answered, or without it.
    if (capabilities == null || !capabilities.supported) {
      return const SizedBox.shrink();
    }
    final platform = ref.read(reminderPlatformProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Event reminders'),
              subtitle: const Text(
                'Notify me before events that have a reminder, even when '
                'Locus is closed.',
              ),
              value: _enabled,
              onChanged: _setEnabled,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Task reminders'),
              subtitle: const Text(
                'Notify me at a to-do reminder time, even when Locus is '
                'closed.',
              ),
              value: _tasksEnabled,
              onChanged: _setTasksEnabled,
            ),
            if (_enabled || _tasksEnabled)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Exact reminder timing'),
                subtitle: Text(
                  !capabilities.exactAlarmsAllowed
                      ? 'Android is restricting exact alarms, so reminders may '
                            'arrive a few minutes late.'
                      : _exactEnabled
                      ? 'Fire at the exact minute. Turn off to save battery; '
                            'reminders may then arrive a few minutes late.'
                      : 'Approximate timing is on; reminders may arrive a few '
                            'minutes late.',
                ),
                value: _exactEnabled && capabilities.exactAlarmsAllowed,
                onChanged: capabilities.exactAlarmsAllowed
                    ? _setExactEnabled
                    : null,
              ),
            if ((_enabled || _tasksEnabled) &&
                !capabilities.notificationsAllowed) ...[
              Text(
                'Notifications are turned off for Locus, so reminders cannot '
                'appear.',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _allowNotifications,
                    child: const Text('Allow notifications'),
                  ),
                  TextButton(
                    onPressed: () => ref
                        .read(appLockControllerProvider.notifier)
                        .runExternal(platform.openNotificationSettings),
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ],
            if ((_enabled || _tasksEnabled) &&
                capabilities.notificationsAllowed &&
                !capabilities.exactAlarmsAllowed) ...[
              const Text(
                'Reminders can arrive a few minutes late. Allow alarms and '
                'reminders for Locus to get them on time.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => ref
                      .read(appLockControllerProvider.notifier)
                      .runExternal(platform.openExactAlarmSettings),
                  child: const Text('Allow exact timing'),
                ),
              ),
            ],
            if (_enabled || _tasksEnabled) ...[
              const SizedBox(height: 8),
              Text(
                'Locus plans reminders for the next 30 days. On Windows, '
                'reminders require the app to be running; Android uses native '
                'alarms.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet({this.initialStart});

  final DateTime? initialStart;

  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  static const _reminderOptions = <({String label, int? minutes})>[
    (label: 'Off', minutes: null),
    (label: 'At start', minutes: 0),
    (label: '5 min before', minutes: 5),
    (label: '10 min before', minutes: 10),
    (label: '15 min before', minutes: 15),
    (label: '30 min before', minutes: 30),
    (label: '1 hour before', minutes: 60),
  ];

  final _controller = TextEditingController();
  int _kind = 0;
  bool _saving = false;
  bool _startPicked = false;
  DateTime _start = AppClock.now();

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart ?? AppClock.now();
  }

  int? _reminder;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _startPicked = true;
    });
  }

  /// Android 13+ only shows notifications once the user has allowed them, and
  /// the best moment to ask is right after they set a reminder.
  Future<void> _ensureNotificationPermission() async {
    final platform = ref.read(reminderPlatformProvider);
    final capabilities = await platform.capabilities();
    if (capabilities.supported && !capabilities.notificationsAllowed) {
      await ref
          .read(appLockControllerProvider.notifier)
          .runExternal(platform.requestNotificationPermission);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _kind == 2
        ? null
        : NaturalLanguageQuickAdd.parse(_controller.text);
    final captureStart = _startPicked ? _start : (parsed?.date ?? _start);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Quick capture', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('Event'),
                icon: Icon(Icons.event),
              ),
              ButtonSegment(
                value: 1,
                label: Text('Task'),
                icon: Icon(Icons.check_box_outlined),
              ),
              ButtonSegment(
                value: 2,
                label: Text('Diary'),
                icon: Icon(Icons.book_outlined),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: _kind == 2 ? 3 : 1,
            maxLines: _kind == 2 ? 6 : 2,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: [
                'e.g. Team standup tomorrow 9am',
                'e.g. Review draft every Monday !',
                'A thought for today',
              ][_kind],
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (parsed != null && parsed.hasDetails) ...[
            const SizedBox(height: 10),
            QuickAddPreview(parsed: parsed),
          ],
          if (_kind == 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickStart,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEE d MMM, h:mm a').format(captureStart)),
            ),
            const SizedBox(height: 12),
            Text('Remind me', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final option in _reminderOptions)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _reminder == option.minutes,
                    onSelected: (_) =>
                        setState(() => _reminder = option.minutes),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving
                ? null
                : () async {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    final capture = _kind == 2
                        ? null
                        : NaturalLanguageQuickAdd.parse(text);
                    final title = capture?.title ?? text;
                    final start = capture?.date ?? captureStart;
                    setState(() => _saving = true);
                    try {
                      final db = ref.read(databaseProvider);
                      if (_kind == 0) {
                        final reminder = _reminder;
                        if (reminder != null &&
                            !start
                                .subtract(Duration(minutes: reminder))
                                .isAfter(AppClock.now())) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'That reminder time has already passed. Pick a '
                                'later start time or a shorter reminder.',
                              ),
                            ),
                          );
                          return;
                        }
                        await db
                            .into(db.events)
                            .insert(
                              EventsCompanion(
                                id: Value(const Uuid().v4()),
                                title: Value(title),
                                startTime: Value(start),
                                allDay: Value(capture?.allDay ?? false),
                                recurrenceRule: Value(capture?.recurrenceRule),
                                hasReminder: Value(reminder != null),
                                reminderMinutes: Value(reminder ?? 10),
                              ),
                            );
                        if (reminder != null) {
                          await _ensureNotificationPermission();
                        }
                      } else if (_kind == 1) {
                        await ref
                            .read(taskRepositoryProvider)
                            .add(
                              title: title,
                              dueDate: capture?.date,
                              priority: TaskPriority.fromValue(
                                capture?.priority.value ?? 0,
                              ),
                              tags: capture?.tags ?? const <String>[],
                              recurrenceRule: capture?.recurrenceRule,
                            );
                      } else {
                        final today = AppClock.now();
                        final existing = await ref
                            .read(diaryRepositoryProvider)
                            .forDate(today);
                        final content =
                            existing == null || existing.content.trim().isEmpty
                            ? text
                            : '${existing.content.trim()}\n\n$text';
                        await ref
                            .read(diaryRepositoryProvider)
                            .save(
                              date: today,
                              mood: existing?.mood ?? 3,
                              content: content,
                            );
                      }
                      if (context.mounted) Navigator.pop(context, true);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not save: $error')),
                        );
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  },
            child: Text(_saving ? 'Saving…' : 'Save locally'),
          ),
        ],
      ),
    );
  }
}

class _HabitTile extends StatelessWidget {
  const _HabitTile({
    super.key,
    required this.habit,
    required this.day,
    required this.completed,
    required this.disabled,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Habit habit;
  final DateTime day;
  final bool completed;
  final bool disabled;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final state = completed ? 'done' : 'not done';
    return ListTile(
      leading: Semantics(
        label: '${habit.name}, ${DateFormat('EEE d MMM').format(day)}, $state',
        checked: completed,
        child: Checkbox(
          value: completed,
          onChanged: disabled ? null : (_) => onToggle(),
        ),
      ),
      title: Text(habit.name),
      subtitle: Text('${habit.icon} · Target ${habit.targetPerWeek}× per week'),
      onTap: disabled ? null : onToggle,
      trailing: PopupMenuButton<String>(
        tooltip: 'Habit actions',
        onSelected: (value) {
          if (value == 'edit') {
            onEdit();
          } else if (value == 'delete') {
            onDelete();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
  );
}
