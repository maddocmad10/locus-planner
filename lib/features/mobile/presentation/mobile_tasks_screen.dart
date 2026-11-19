part of '../mobile_app.dart';

class _TasksScreen extends ConsumerWidget {
  const _TasksScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksStreamProvider);
    final attachmentCounts =
        ref.watch(attachmentCountsProvider).valueOrNull?.todos ??
        const <String, int>{};
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
                          _MobileAttachmentBadge(
                            attachmentCounts[items[i].id] ?? 0,
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
      if (task.notes != null && task.notes!.isNotEmpty)
        task.notesFormat == 'md1'
            ? plainTextFromMd1(task.notes!, maxChars: 160)
            : task.notes!,
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
