import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/clock_provider.dart';
import '../../../core/services/error_log_service.dart';
import '../../events/data/reminder_inbox_service.dart';

enum _ReminderAction { snooze10, snooze60, dismiss }

Future<void> showMissedRemindersDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _MissedRemindersDialog(),
  );
}

class _MissedRemindersDialog extends ConsumerWidget {
  const _MissedRemindersDialog();

  Future<void> _handle(
    BuildContext context,
    WidgetRef ref,
    MissedReminder reminder,
    _ReminderAction action,
  ) async {
    final service = ref.read(reminderInboxServiceProvider);
    try {
      switch (action) {
        case _ReminderAction.snooze10:
          await service.snooze(reminder, const Duration(minutes: 10));
        case _ReminderAction.snooze60:
          await service.snooze(reminder, const Duration(hours: 1));
        case _ReminderAction.dismiss:
          await service.dismiss(reminder);
      }
      if (!context.mounted) return;
      final message = switch (action) {
        _ReminderAction.snooze10 => 'Reminder snoozed for 10 minutes.',
        _ReminderAction.snooze60 => 'Reminder snoozed for 1 hour.',
        _ReminderAction.dismiss => 'Reminder dismissed.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update the reminder: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(missedRemindersProvider);
    final now = ref.watch(clockProvider)();

    return AlertDialog(
      title: const Text('Missed reminders'),
      content: SizedBox(
        width: 560,
        height: 380,
        child: reminders.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const Center(child: Text('Could not load missed reminders.')),
          data: (items) {
            if (items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.done_all,
                      size: 42,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text('Nothing missed. You are caught up.'),
                  ],
                ),
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reminder = items[index];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: Icon(
                    Icons.notifications_paused_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(reminder.title),
                  subtitle: Text(
                    'Due ${_relativeTime(reminder.reminderAt, now)} '
                    '· event at ${_formatWhen(reminder.occurrenceStart)}',
                  ),
                  trailing: PopupMenuButton<_ReminderAction>(
                    tooltip: 'Reminder actions',
                    onSelected: (action) =>
                        _handle(context, ref, reminder, action),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: _ReminderAction.snooze10,
                        child: Text('Snooze 10 minutes'),
                      ),
                      PopupMenuItem(
                        value: _ReminderAction.snooze60,
                        child: Text('Snooze 1 hour'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _ReminderAction.dismiss,
                        child: Text('Dismiss'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

String _relativeTime(DateTime time, DateTime now) {
  final difference = now.difference(time);
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} h ago';
  return '${difference.inDays} d ago';
}

String _formatWhen(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.day}/${time.month} $hour:$minute';
}
