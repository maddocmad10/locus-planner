import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/widgets/user_action_error.dart';
import '../data/diary_repository.dart';

class DiaryPage extends ConsumerStatefulWidget {
  const DiaryPage({super.key});

  @override
  ConsumerState<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends ConsumerState<DiaryPage> {
  final TextEditingController _contentController = TextEditingController();
  int _selectedMood = 3; // Default mood: 🙂
  DiaryEntry? _existingEntry;
  bool _isLoading = true;

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
    _loadTodayEntry();
  }

  Future<void> _loadTodayEntry() async {
    setState(() => _isLoading = true);

    final today = DateTime.now();
    final entry = await ref.read(diaryRepositoryProvider).forDate(today);
    if (!mounted) return;

    if (entry != null) {
      _existingEntry = entry;
      _contentController.text = entry.content;
      _selectedMood = entry.mood;
    } else {
      _existingEntry = null;
      _contentController.clear();
      _selectedMood = 3;
    }

    if (mounted) setState(() => _isLoading = false);
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
      () => ref
          .read(diaryRepositoryProvider)
          .save(
            date: DateTime.now(),
            mood: _selectedMood,
            content: _contentController.text.trim(),
          ),
      failureMessage: 'Could not save the diary entry.',
    );

    if (!success || !mounted) return;
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
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dayChangeProvider, (_, _) {
      _loadTodayEntry();
    });

    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final todayFormatted = DateFormat(
      'EEEE, MMMM dd, yyyy',
    ).format(DateTime.now());

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
