part of '../mobile_app.dart';

/// Paperclip count shown on compact mobile rows.
class _MobileAttachmentBadge extends StatelessWidget {
  const _MobileAttachmentBadge(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Semantics(
      label: '$count attachment${count == 1 ? '' : 's'}',
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.attach_file, size: 16, color: Colors.grey),
            Text(
              '$count',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
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
