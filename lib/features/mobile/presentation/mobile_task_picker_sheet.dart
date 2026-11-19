part of '../mobile_app.dart';

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
