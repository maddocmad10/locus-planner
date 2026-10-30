import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/services/sync_tls.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/recurrence.dart';
import '../diary/data/diary_repository.dart';
import '../tasks/data/task_repository.dart';
import 'data/mobile_reminder_service.dart';
import 'data/mobile_sync_client.dart';
import 'data/reminder_platform.dart';
import 'data/today_agenda.dart';
import 'pair_scanner_page.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Event reminders follow the events table, so they also pick up rows that
    // a sync brings in.
    _reminders = ref.read(mobileReminderServiceProvider)..start();
    // Opening the app is the moment the user expects to see current data.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_autoSync()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_reminders.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Moves the window of upcoming reminders forward.
      unawaited(_reminders.refresh());
      unawaited(_autoSync());
    }
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
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _QuickCaptureSheet(),
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
            final todayEvents = agendaForDay(all, now);
            if (todayEvents.isEmpty) {
              return const _EmptyCard(
                message: 'Nothing scheduled today. Use + to add an event.',
              );
            }
            return Card(
              child: Column(
                children: [
                  for (var i = 0; i < todayEvents.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ListTile(
                      leading: const Icon(Icons.event_outlined),
                      title: Text(todayEvents[i].event.title),
                      subtitle: Text(
                        todayEvents[i].isRecurring
                            ? '${DateFormat('h:mm a').format(todayEvents[i].start)}'
                                  ' · ${Recurrence.label(todayEvents[i].event.recurrenceRule)}'
                            : DateFormat('h:mm a').format(todayEvents[i].start),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (todayEvents[i].isRecurring)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.repeat, size: 18),
                            ),
                          if (todayEvents[i].event.hasReminder)
                            const Icon(
                              Icons.notifications_active_outlined,
                              size: 20,
                            ),
                        ],
                      ),
                      onTap: () =>
                          _editEvent(context, ref, todayEvents[i].event),
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
    final result = await showDialog<_EventEditResult>(
      context: context,
      builder: (_) => _EventEditDialog(event: event, start: event.startTime),
    );
    if (result == null) return;

    final db = ref.read(databaseProvider);
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
    await (db.update(db.events)..where((row) => row.id.equals(event.id))).write(
      EventsCompanion(
        title: Value(title),
        startTime: Value(result.start ?? event.startTime),
      ),
    );
  }
}

/// What the event editor returns. A null result means the user cancelled.
class _EventEditResult {
  const _EventEditResult({this.title, this.start, this.delete = false});

  final String? title;
  final DateTime? start;
  final bool delete;
}

class _EventEditDialog extends StatefulWidget {
  const _EventEditDialog({required this.event, required this.start});

  final Event event;
  final DateTime start;

  @override
  State<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends State<_EventEditDialog> {
  late final TextEditingController _controller;
  late DateTime _start;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.event.title);
    _start = widget.start;
  }

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
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickStart,
            icon: const Icon(Icons.schedule),
            label: Text(DateFormat('EEE d MMM yyyy, h:mm a').format(_start)),
          ),
          if (recurring) ...[
            const SizedBox(height: 12),
            Text(
              'This event repeats. Changes apply to every repeat.',
              style: Theme.of(context).textTheme.bodySmall,
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
            _EventEditResult(title: _controller.text.trim(), start: _start),
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
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Task actions',
                        onSelected: (value) async {
                          if (value != 'delete') return;
                          final task = items[i];
                          await ref
                              .read(taskRepositoryProvider)
                              .delete(task.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text('Deleted “${task.title}”'),
                                action: SnackBarAction(
                                  label: 'Undo',
                                  onPressed: () => ref
                                      .read(taskRepositoryProvider)
                                      .restore(task),
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
    if (title != null && title.isNotEmpty) {
      await ref
          .read(taskRepositoryProvider)
          .update(id: item.id, title: title, dueDate: item.dueDate);
    }
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
    final result = await Navigator.of(context).push<PairScanResult>(
      MaterialPageRoute(builder: (_) => const PairScannerPage()),
    );
    if (result is PairScanManualEntry) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter the desktop address and pairing code below.'),
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
    final enabled = await ref.read(mobileReminderServiceProvider).isEnabled();
    final capabilities = await ref
        .read(reminderPlatformProvider)
        .capabilities();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _capabilities = capabilities;
    });
  }

  Future<void> _setEnabled(bool value) async {
    setState(() => _enabled = value);
    await ref.read(mobileReminderServiceProvider).setEnabled(value);
  }

  Future<void> _allowNotifications() async {
    await ref.read(reminderPlatformProvider).requestNotificationPermission();
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
            if (_enabled && !capabilities.notificationsAllowed) ...[
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
                    onPressed: platform.openNotificationSettings,
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ],
            if (_enabled &&
                capabilities.notificationsAllowed &&
                !capabilities.exactAlarmsAllowed) ...[
              const Text(
                'Reminders can arrive a few minutes late. Allow alarms and '
                'reminders for Locus to get them on time.',
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: platform.openExactAlarmSettings,
                  child: const Text('Allow exact timing'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet();
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
  DateTime _start = AppClock.now();
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

  /// Android 13+ only shows notifications once the user has allowed them, and
  /// the best moment to ask is right after they set a reminder.
  Future<void> _ensureNotificationPermission() async {
    final platform = ref.read(reminderPlatformProvider);
    final capabilities = await platform.capabilities();
    if (capabilities.supported && !capabilities.notificationsAllowed) {
      await platform.requestNotificationPermission();
    }
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
        if (_kind == 0) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickStart,
            icon: const Icon(Icons.schedule),
            label: Text(DateFormat('EEE d MMM, h:mm a').format(_start)),
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
                  onSelected: (_) => setState(() => _reminder = option.minutes),
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
                  setState(() => _saving = true);
                  try {
                    final db = ref.read(databaseProvider);
                    if (_kind == 0) {
                      final reminder = _reminder;
                      if (reminder != null &&
                          !_start
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
                              title: Value(text),
                              startTime: Value(_start),
                              hasReminder: Value(reminder != null),
                              reminderMinutes: Value(reminder ?? 10),
                            ),
                          );
                      if (reminder != null) {
                        await _ensureNotificationPermission();
                      }
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: const EdgeInsets.all(18), child: Text(message)),
  );
}
