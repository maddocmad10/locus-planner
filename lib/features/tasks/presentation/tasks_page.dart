import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/command_action_provider.dart';
import '../../../core/widgets/empty_state.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  @override
  void initState() {
    super.initState();
    // The palette sets the action just before navigating here, i.e. before this
    // page subscribed to the provider, so ref.listen in build() never sees it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(commandActionProvider) == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).state = CommandAction.none;
        _showAddTaskDialog();
      }
    });
  }

  final TextEditingController _titleController = TextEditingController();
  final FocusNode _taskFocusNode = FocusNode();
  DateTime? _selectedDueDate;

  // ==================== ADD TASK DIALOG ====================
  Future<void> _showAddTaskDialog() async {
    final titleController = TextEditingController();
    DateTime? dueDate;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add New Task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Task title',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                  onSubmitted: (_) async {
                    if (titleController.text.trim().isEmpty) return;
                    final db = ref.read(databaseProvider);
                    await db.addTodoItem(titleController.text.trim(), dueDate);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    dueDate == null
                        ? 'No due date'
                        : 'Due: ${DateFormat('MMM dd, yyyy').format(dueDate!)}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setDialogState(() => dueDate = picked);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) return;

                  final db = ref.read(databaseProvider);
                  await db.addTodoItem(titleController.text.trim(), dueDate);

                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Add Task'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Quick add from the top bar
  Future<void> _quickAddTask() async {
    if (_titleController.text.trim().isEmpty) return;

    final db = ref.read(databaseProvider);
    await db.addTodoItem(_titleController.text.trim(), _selectedDueDate);

    _titleController.clear();
    setState(() => _selectedDueDate = null);
    _taskFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _taskFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    // Command Palette support
    ref.listen<CommandAction>(commandActionProvider, (previous, next) {
      if (next == CommandAction.newTask) {
        ref.read(commandActionProvider.notifier).state = CommandAction.none;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showAddTaskDialog();
        });
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Quick Add Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    focusNode: _taskFocusNode,
                    decoration: const InputDecoration(
                      hintText: 'Quick add a task...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _quickAddTask(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Set due date',
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) {
                      setState(() => _selectedDueDate = date);
                    }
                  },
                ),
                FilledButton(
                  onPressed: _quickAddTask,
                  child: const Text('Add'),
                ),
              ],
            ),
          ),

          if (_selectedDueDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text('Due: ${DateFormat('MMM dd').format(_selectedDueDate!)}'),
                  onDeleted: () => setState(() => _selectedDueDate = null),
                ),
              ),
            ),

          const Divider(height: 1),

          // Tasks List
          Expanded(
            child: StreamBuilder<List<TodoItem>>(
              stream: db.watchAllTodoItems(),
              builder: (context, snapshot) {
                final tasks = snapshot.data ?? [];

                if (tasks.isEmpty) {
                  return EmptyState(
                    icon: Icons.checklist_outlined,
                    title: 'No tasks yet',
                    subtitle: 'Add your first task to get started.\nYou can also use Ctrl+K → New Task',
                    buttonLabel: 'Add Task',
                    onButtonPressed: _showAddTaskDialog, // ← Now opens the dialog
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Checkbox(
                          value: task.completed,
                          onChanged: (val) {
                            db.toggleTodoItem(task.id, val ?? false);
                          },
                        ),
                        title: Text(
                          task.title,
                          style: TextStyle(
                            decoration: task.completed ? TextDecoration.lineThrough : null,
                            color: task.completed ? Colors.grey : null,
                          ),
                        ),
                        subtitle: task.dueDate != null
                            ? Text('Due: ${DateFormat('MMM dd').format(task.dueDate!)}')
                            : null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => db.deleteTodoItem(task.id),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}