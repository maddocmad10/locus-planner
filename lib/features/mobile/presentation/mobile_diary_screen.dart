part of '../mobile_app.dart';

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
