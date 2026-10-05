import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../data/habit_repository.dart';
import '../../../core/widgets/undo_snackbar.dart';
import '../../../core/providers/command_action_provider.dart';
import '../../../core/utils/day_math.dart';
import '../../../core/widgets/empty_state.dart';

class HabitsPage extends ConsumerStatefulWidget {
  const HabitsPage({super.key});

  @override
  ConsumerState<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends ConsumerState<HabitsPage> {
  @override
  void initState() {
    super.initState();
    // The palette sets the action just before navigating here, i.e. before this
    // page subscribed to the provider, so ref.listen in build() never sees it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(commandActionProvider) == CommandAction.newHabit) {
        ref.read(commandActionProvider.notifier).state = CommandAction.none;
        _addOrEditHabit();
      }
    });
  }

  Future<void> _addOrEditHabit({Habit? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    int targetPerWeek = existing?.targetPerWeek ?? 5;
    String selectedIcon = existing?.icon ?? '🔥';

    final icons = ['🔥', '💪', '📚', '🏃', '🧘', '💧', '🎯', '✍️', '🥗', '😴'];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(existing == null ? 'Add Habit' : 'Edit Habit'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Habit Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  const Text('Icon'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: icons.map((icon) {
                      final isSelected = selectedIcon == icon;
                      return ChoiceChip(
                        label: Text(icon, style: const TextStyle(fontSize: 20)),
                        selected: isSelected,
                        onSelected: (_) =>
                            setDialogState(() => selectedIcon = icon),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Text('Target: $targetPerWeek days per week'),
                  Slider(
                    value: targetPerWeek.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: '$targetPerWeek',
                    onChanged: (v) =>
                        setDialogState(() => targetPerWeek = v.round()),
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
                  if (nameController.text.trim().isEmpty) return;

                  final db = ref.read(databaseProvider);

                  if (existing == null) {
                    await db
                        .into(db.habits)
                        .insert(
                          HabitsCompanion(
                            id: drift.Value(Uuid().v4()),
                            name: drift.Value(nameController.text.trim()),
                            icon: drift.Value(selectedIcon),
                            createdAt: drift.Value(DateTime.now()),
                            targetPerWeek: drift.Value(targetPerWeek),
                          ),
                        );
                  } else {
                    await (db.update(
                      db.habits,
                    )..where((t) => t.id.equals(existing.id))).write(
                      HabitsCompanion(
                        name: drift.Value(nameController.text.trim()),
                        icon: drift.Value(selectedIcon),
                        targetPerWeek: drift.Value(targetPerWeek),
                      ),
                    );
                  }

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteHabit(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Habit?'),
        content: Text('Delete "${habit.name}" and all its history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(habitRepositoryProvider).delete(habit.id);
      if (mounted) UndoSnackbar.show(context, message: 'Habit deleted');
    }
  }

  Future<void> _toggleToday(Habit habit, bool currentlyCompleted) async {
    final db = ref.read(databaseProvider);
    final today = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    if (currentlyCompleted) {
      await (db.delete(
        db.habitLogs,
      )..where((t) => t.habitId.equals(habit.id) & t.date.equals(today))).go();
    } else {
      await db
          .into(db.habitLogs)
          .insert(
            HabitLogsCompanion(
              id: drift.Value(Uuid().v4()),
              habitId: drift.Value(habit.id),
              date: drift.Value(today),
              completed: const drift.Value(true),
            ),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    // Command Palette support
    ref.listen<CommandAction>(commandActionProvider, (previous, next) {
      if (next == CommandAction.newHabit) {
        ref.read(commandActionProvider.notifier).state = CommandAction.none;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _addOrEditHabit();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditHabit(),
        child: const Icon(Icons.add),
      ),
      body: StreamBuilder<List<Habit>>(
        stream: db.watchHabits(),
        builder: (context, snapshot) {
          final habits = snapshot.data ?? [];

          if (habits.isEmpty) {
            return EmptyState(
              icon: Icons.check_circle_outline,
              title: 'No habits yet',
              subtitle:
                  'Create your first habit to start building consistency.',
              buttonLabel: 'Add Habit',
              onButtonPressed: () => _addOrEditHabit(),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: habits.length,
            itemBuilder: (context, index) {
              final habit = habits[index];
              return _HabitCard(
                habit: habit,
                onToggleToday: _toggleToday,
                onEdit: () => _addOrEditHabit(existing: habit),
                onDelete: () => _deleteHabit(habit),
              );
            },
          );
        },
      ),
    );
  }
}

// ==================== HABIT CARD ====================
class _HabitCard extends ConsumerWidget {
  final Habit habit;
  final Future<void> Function(Habit, bool) onToggleToday;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _HabitCard({
    required this.habit,
    required this.onToggleToday,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);

    return FutureBuilder(
      future: Future.wait([
        db.logsForHabitToday(habit.id),
        _getHabitLogsLastDays(db, habit.id, 84),
      ]),
      builder: (context, snapshot) {
        final todayLogs = snapshot.hasData ? snapshot.data![0] : <HabitLog>[];
        final allLogs = snapshot.hasData ? snapshot.data![1] : <HabitLog>[];

        final isCompletedToday = todayLogs.isNotEmpty;
        final streak = _calculateStreak(allLogs);
        final thisWeekCount = _countThisWeek(allLogs);
        final target = habit.targetPerWeek;

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(habit.icon, style: const TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            habit.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '🔥 $streak day streak  •  $thisWeekCount/$target this week',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Checkbox(
                      value: isCompletedToday,
                      onChanged: (_) => onToggleToday(habit, isCompletedToday),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'delete') onDelete();
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit')),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _HabitHeatmap(logs: allLogs),
                const SizedBox(height: 8),
                Text(
                  'Last 12 weeks',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<HabitLog>> _getHabitLogsLastDays(
    AppDatabase db,
    String habitId,
    int days,
  ) async {
    final startDay = DayMath.addDays(DayMath.dateOnly(DateTime.now()), -days);

    return (db.select(db.habitLogs)
          ..where(
            (t) =>
                t.habitId.equals(habitId) &
                t.date.isBiggerOrEqualValue(startDay),
          )
          ..orderBy([(t) => drift.OrderingTerm.asc(t.date)]))
        .get();
  }

  int _calculateStreak(List<HabitLog> logs) {
    if (logs.isEmpty) return 0;

    return DayMath.consecutiveDayStreak(
      logs.where((l) => l.completed).map((l) => l.date),
    );
  }

  int _countThisWeek(List<HabitLog> logs) {
    final now = DateTime.now();
    final start = DayMath.startOfWeek(now);
    final end = DayMath.addDays(DayMath.dateOnly(now), 1);

    return logs
        .where(
          (l) => l.completed && !l.date.isBefore(start) && l.date.isBefore(end),
        )
        .length;
  }
}

// ==================== HEATMAP ====================
class _HabitHeatmap extends StatelessWidget {
  final List<HabitLog> logs;

  const _HabitHeatmap({required this.logs});

  @override
  Widget build(BuildContext context) {
    final completedSet = logs
        .where((l) => l.completed)
        .map((l) => DateTime(l.date.year, l.date.month, l.date.day))
        .toSet();

    final today = DayMath.dateOnly(DateTime.now());
    final days = List.generate(84, (i) => DayMath.addDays(today, -(83 - i)));

    final weeks = <List<DateTime>>[];
    for (var i = 0; i < days.length; i += 7) {
      weeks.add(days.sublist(i, i + 7 > days.length ? days.length : i + 7));
    }

    final primary = Theme.of(context).colorScheme.primary;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: weeks.map((week) {
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Column(
              children: week.map((day) {
                final isCompleted = completedSet.contains(day);
                final isToday = day == today;

                return Tooltip(
                  message:
                      DateFormat('MMM d').format(day) +
                      (isCompleted ? ' ✓' : ''),
                  child: Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? primary
                          : Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                      border: isToday
                          ? Border.all(color: primary, width: 1.5)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }
}
