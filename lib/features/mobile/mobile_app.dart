import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/utils/app_clock.dart';
import '../diary/data/diary_repository.dart';
import '../tasks/data/task_repository.dart';
import 'data/mobile_sync_client.dart';

final _mobileEventsProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(databaseProvider).watchAllEvents();
});
final _mobileDiaryProvider = StreamProvider<List<DiaryEntry>>((ref) {
  return ref.watch(diaryRepositoryProvider).watchAll();
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
  );
}

class _MobileHome extends ConsumerStatefulWidget {
  const _MobileHome();

  @override
  ConsumerState<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends ConsumerState<_MobileHome> {
  int _index = 0;
  bool _syncing = false;

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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _QuickCaptureSheet(),
    );
    if (saved == true && mounted)
      _message('Saved on this device. Tap Sync now to share it.');
  }

  @override
  Widget build(BuildContext context) {
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

class _TodayScreen extends ConsumerWidget {
  const _TodayScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(_mobileEventsProvider);
    final now = AppClock.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Text(
          DateFormat('EEEE, d MMMM').format(now),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        const Text('Your agenda'),
        const SizedBox(height: 12),
        events.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Text('Could not load agenda: $error'),
          data: (all) {
            final todayEvents =
                all
                    .where(
                      (event) =>
                          !event.startTime.isBefore(today) &&
                          event.startTime.isBefore(tomorrow),
                    )
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));
            if (todayEvents.isEmpty)
              return const _EmptyCard(
                message: 'Nothing scheduled today. Use + to add an event.',
              );
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < todayEvents.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(todayEvents[i].title),
                      subtitle: Text(
                        DateFormat('h:mm a').format(todayEvents[i].startTime),
                      ),
                      onTap: () => _editEvent(context, ref, todayEvents[i]),
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
    );
  }

  Future<void> _editEvent(
    BuildContext context,
    WidgetRef ref,
    Event event,
  ) async {
    final controller = TextEditingController(text: event.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit event'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    await (ref.read(databaseProvider).update(ref.read(databaseProvider).events)
          ..where((row) => row.id.equals(event.id)))
        .write(EventsCompanion(title: Value(title)));
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
            if (items.isEmpty)
              return const _EmptyCard(
                message: 'No tasks yet. Tap + to capture one.',
              );
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 12, endIndent: 12),
                    ListTile(
                      leading: Checkbox(
                        value: items[i].completed,
                        onChanged: (value) => ref
                            .read(taskRepositoryProvider)
                            .toggle(items[i].id, value ?? false),
                      ),
                      title: Text(
                        items[i].title,
                        style: TextStyle(
                          decoration: items[i].completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: items[i].dueDate == null
                          ? null
                          : Text(
                              'Due ${DateFormat.yMMMd().format(items[i].dueDate!)}',
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

  Future<void> _editTask(
    BuildContext context,
    WidgetRef ref,
    TodoItem item,
  ) async {
    final controller = TextEditingController(text: item.title);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit task'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title != null && title.isNotEmpty)
      await ref
          .read(taskRepositoryProvider)
          .update(id: item.id, title: title, dueDate: item.dueDate);
  }
}

class _DiaryScreen extends ConsumerStatefulWidget {
  const _DiaryScreen();
  @override
  ConsumerState<_DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends ConsumerState<_DiaryScreen> {
  final _controller = TextEditingController();
  int _mood = 3;
  String? _loadedId;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        final identity = entry?.id ?? 'new-${today.toIso8601String()}';
        if (_loadedId != identity) {
          _loadedId = identity;
          _controller.text = entry?.content ?? '';
          _mood = entry?.mood ?? 3;
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
                    onSelected: (_) => setState(() => _mood = mood.$1),
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
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await ref
                            .read(diaryRepositoryProvider)
                            .save(
                              date: today,
                              mood: _mood,
                              content: _controller.text.trim(),
                            );
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Diary saved locally. Sync to share it.',
                              ),
                            ),
                          );
                      } catch (error) {
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Could not save diary: $error'),
                            ),
                          );
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…' : 'Save diary'),
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
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Desktop IP address',
                    hintText: 'http://192.168.1.20:43821',
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
                FilledButton.icon(
                  onPressed: _pairing
                      ? null
                      : () async {
                          setState(() {
                            _pairing = true;
                            _error = null;
                          });
                          try {
                            await ref
                                .read(mobileSyncClientProvider)
                                .pair(
                                  host: _hostController.text,
                                  code: _codeController.text,
                                );
                            _codeController.clear();
                            await _refreshStatus();
                            if (mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Phone paired. Tap Sync now to exchange data.',
                                  ),
                                ),
                              );
                          } catch (error) {
                            if (mounted) setState(() => _error = '$error');
                          } finally {
                            if (mounted) setState(() => _pairing = false);
                          }
                        },
                  icon: const Icon(Icons.phonelink_setup),
                  label: Text(_pairing ? 'Pairing…' : 'Pair with desktop'),
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
        const _EmptyCard(
          message:
              'Pairing uses the one-time code in desktop Settings → Device Sync (LAN). Sync uses plain HTTP on your local network: only use a trusted private Wi-Fi network, never public Wi-Fi.',
        ),
      ],
    );
  }
}

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet();
  @override
  ConsumerState<_QuickCaptureSheet> createState() => _QuickCaptureSheetState();
}

class _QuickCaptureSheetState extends ConsumerState<_QuickCaptureSheet> {
  final _controller = TextEditingController();
  int _kind = 0;
  bool _saving = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
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
              'Event title',
              'Task title',
              'A thought for today',
            ][_kind],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  setState(() => _saving = true);
                  try {
                    final db = ref.read(databaseProvider);
                    if (_kind == 0) {
                      await db
                          .into(db.events)
                          .insert(
                            EventsCompanion(
                              id: Value(const Uuid().v4()),
                              title: Value(text),
                              startTime: Value(AppClock.now()),
                            ),
                          );
                    } else if (_kind == 1) {
                      await ref.read(taskRepositoryProvider).add(title: text);
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
                    if (mounted) Navigator.pop(context, true);
                  } catch (error) {
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not save: $error')),
                      );
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
  );
}
