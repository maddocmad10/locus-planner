import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/diary_repository.dart';
import '../../../core/utils/app_clock.dart';

class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage>
    with WidgetsBindingObserver {
  final TextEditingController _contentController = TextEditingController();
  late final DiaryRepository _repository;
  int _selectedMood = 3; // Default mood: 🙂
  DiaryEntry? _existingEntry;
  bool _isLoading = true;
  bool _showDraftBanner = false;
  bool _applyingRecoveredDraft = false;
  Timer? _draftTimer;

  final List<Map<String, dynamic>> _moods = [
    {'emoji': '😞', 'value': 1, 'label': 'Bad'},
    {'emoji': '😐', 'value': 2, 'label': 'Okay'},
    {'emoji': '🙂', 'value': 3, 'label': 'Good'},
    {'emoji': '😊', 'value': 4, 'label': 'Great'},
    {'emoji': '🤩', 'value': 5, 'label': 'Awesome'},
  ];

  @override
  void initState() {
    super.initState();
    _repository = ref.read(diaryRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _contentController.addListener(_scheduleDraftSave);
    _loadTodayEntry();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(_flushDraft());
    }
  }

  Future<void> _loadTodayEntry({bool preserveUnsaved = false}) async {
    setState(() => _isLoading = true);

    final today = AppClock.now();
    final entry = await _repository.forDate(today);
    if (!mounted) return;

    // Unsaved work is anything that differs from the entry shown on screen.
    // After a save+reload the controller holds the stored content, so this
    // is false; while the user is mid-typing it is true.
    final hasUnsavedEdits = _existingEntry == null
        ? _contentController.text.isNotEmpty
        : _contentController.text != _existingEntry!.content;

    if (entry != null) {
      _existingEntry = entry;
      _contentController.text = entry.content;
      _selectedMood = entry.mood;
    } else if (preserveUnsaved && hasUnsavedEdits) {
      // The day rolled over while the user was writing. Keep the draft and
      // the chosen mood — it will be saved under the new day — instead of
      // wiping an hour of writing because the clock struck twelve.
      _existingEntry = null;
    } else {
      _existingEntry = null;
      _contentController.clear();
      _selectedMood = 3;
    }

    var showDraftBanner = false;
    final draft = await _repository.loadDraft();
    if (!mounted) return;
    if (draft != null &&
        _sameDay(draft.date, today) &&
        draft.text.trim().isNotEmpty &&
        draft.text != (entry?.content ?? '')) {
      // Recover the unsaved text after a crash, kill or forced reload. The
      // banner lets the user keep it or return to the stored entry.
      _applyingRecoveredDraft = true;
      _contentController.text = draft.text;
      _selectedMood = draft.mood;
      _applyingRecoveredDraft = false;
      showDraftBanner = true;
    } else if (draft != null && _sameDay(draft.date, today)) {
      await _repository.clearDraft();
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
        _showDraftBanner = showDraftBanner;
      });
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scheduleDraftSave() {
    if (_isLoading || _applyingRecoveredDraft) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_flushDraft()),
    );
  }

  Future<void> _flushDraft() async {
    _draftTimer?.cancel();
    _draftTimer = null;
    if (_isLoading) return;
    final text = _contentController.text;
    final saved = _existingEntry;
    if (text.trim().isEmpty || (saved != null && text == saved.content)) {
      await _repository.clearDraft();
      return;
    }
    await _repository.saveDraft(
      date: AppClock.now(),
      mood: _selectedMood,
      text: text,
    );
  }

  Future<void> _keepRecoveredDraft() async {
    await _repository.clearDraft();
    if (!mounted) return;
    setState(() => _showDraftBanner = false);
  }

  Future<void> _discardRecoveredDraft() async {
    final entry = _existingEntry;
    _applyingRecoveredDraft = true;
    _contentController.text = entry?.content ?? '';
    _selectedMood = entry?.mood ?? 3;
    _applyingRecoveredDraft = false;
    await _repository.clearDraft();
    if (!mounted) return;
    setState(() => _showDraftBanner = false);
  }

  Future<void> _saveEntry() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please write something in your diary')),
      );
      return;
    }

    final success = await runUserMutation(
      context,
      () => _repository.save(
        date: AppClock.now(),
        mood: _selectedMood,
        content: _contentController.text.trim(),
      ),
      failureMessage: 'Could not save the diary entry.',
    );

    if (!success || !mounted) return;
    _draftTimer?.cancel();
    await _repository.clearDraft();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diary entry saved!'),
        backgroundColor: Colors.green,
      ),
    );

    await _loadTodayEntry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _contentController.removeListener(_scheduleDraftSave);
    _draftTimer?.cancel();
    unawaited(_flushDraft());
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dayChangeProvider, (previous, _) {
      if (previous?.hasValue != true) return;
      // Midnight rollover: reload the day, but never destroy a draft the
      // user has not saved yet. The refresh button keeps the old behavior —
      // it is an explicit request to see the stored state.
      _loadTodayEntry(preserveUnsaved: true);
    });

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todayFormatted = DateFormat(
      'EEEE, MMMM dd, yyyy',
    ).format(AppClock.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diary'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTodayEntry,
            tooltip: 'Reload today\'s entry',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_showDraftBanner)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.restore, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Recovered unsaved draft')),
                        TextButton(
                          onPressed: _discardRecoveredDraft,
                          child: const Text('Discard'),
                        ),
                        TextButton(
                          onPressed: _keepRecoveredDraft,
                          child: const Text('Keep'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // Date Header
            Text(
              todayFormatted,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'How was your day?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // Mood Selector
            const Text('Mood', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _moods.map((mood) {
                final isSelected = _selectedMood == mood['value'];
                return ChoiceChip(
                  label: Text('${mood['emoji']} ${mood['label']}'),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() {
                      _selectedMood = mood['value'] as int;
                    });
                  },
                  selectedColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontWeight: isSelected ? FontWeight.bold : null,
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Diary Content
            const Text(
              'What happened today?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _contentController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText:
                      'Write about your day, thoughts, wins, or anything on your mind...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  // Inherit InputDecorationTheme so the editor follows both
                  // light and dark application themes.
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _saveEntry,
                icon: const Icon(Icons.save),
                label: Text(
                  _existingEntry != null ? 'Update Entry' : 'Save Entry',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
