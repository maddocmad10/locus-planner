part of '../mobile_app.dart';

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
    final attachmentCounts = ref.watch(attachmentCountsProvider).valueOrNull;
    final eventAttachmentCounts =
        attachmentCounts?.events ?? const <String, int>{};
    final todoAttachmentCounts =
        attachmentCounts?.todos ?? const <String, int>{};

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
                            _MobileAttachmentBadge(
                              eventAttachmentCounts[dayEvents[i].event.id] ?? 0,
                            ),
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
                              _MobileAttachmentBadge(
                                todoAttachmentCounts[item.taskId] ?? 0,
                              ),
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
        imageResolver: (id) async {
          final service = await ref.read(attachmentServiceProvider.future);
          return service.thumbnailById(id);
        },
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
