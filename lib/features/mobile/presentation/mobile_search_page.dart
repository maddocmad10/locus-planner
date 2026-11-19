part of '../mobile_app.dart';

class _MobileSearchPage extends ConsumerStatefulWidget {
  const _MobileSearchPage({
    required this.onOpenTask,
    required this.onOpenEvent,
  });

  final ValueChanged<TodoItem> onOpenTask;
  final ValueChanged<Event> onOpenEvent;

  @override
  ConsumerState<_MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileSearchPageState extends ConsumerState<_MobileSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _searching = false;
  var _tasks = <TodoItem>[];
  var _events = <Event>[];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_search(value));
    });
  }

  Future<void> _search(String value) async {
    final query = value.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _tasks = const [];
          _events = const [];
          _searching = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _searching = true);
    final db = ref.read(databaseProvider);
    final tasks = await db.searchTodoItems(query);
    final events = await db.searchEvents(query);
    final attachments = await db.searchAttachments(query);
    final taskIds = {
      for (final attachment in attachments)
        if (attachment.todoId != null) attachment.todoId!,
    };
    final eventIds = {
      for (final attachment in attachments)
        if (attachment.eventId != null) attachment.eventId!,
    };
    final knownTasks = {for (final task in tasks) task.id};
    final knownEvents = {for (final event in events) event.id};
    final extraTasks = await db.todoItemsByIds(
      taskIds.where((id) => !knownTasks.contains(id)),
    );
    final extraEvents = await db.eventsByIds(
      eventIds.where((id) => !knownEvents.contains(id)),
    );
    if (!mounted) return;
    setState(() {
      _tasks = [...tasks, ...extraTasks];
      _events = [...events, ...extraEvents];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasResults = _tasks.isNotEmpty || _events.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search tasks, notes, events and attachments',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: (value) => unawaited(_search(value)),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (!_searching && _controller.text.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Search task titles, notes, event descriptions and attachment names.',
                textAlign: TextAlign.center,
              ),
            ),
          if (!_searching && _controller.text.trim().isNotEmpty && !hasResults)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matches.', textAlign: TextAlign.center),
            ),
          if (_tasks.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text(
                'Tasks',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final task in _tasks)
              ListTile(
                leading: Icon(
                  task.completed ? Icons.check_circle : Icons.task_alt,
                ),
                title: Text(task.title),
                subtitle: task.notes == null || task.notes!.isEmpty
                    ? null
                    : Text(
                        task.notesFormat == 'md1'
                            ? plainTextFromMd1(task.notes!, maxChars: 100)
                            : task.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenTask(task);
                },
              ),
          ],
          if (_events.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text(
                'Events',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final event in _events)
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(event.title),
                subtitle: Text(
                  [
                    DateFormat.yMMMd().add_Hm().format(event.startTime),
                    if (event.description != null &&
                        event.description!.isNotEmpty)
                      event.descriptionFormat == 'md1'
                          ? plainTextFromMd1(event.description!, maxChars: 80)
                          : event.description!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onOpenEvent(event);
                },
              ),
          ],
        ],
      ),
    );
  }
}
