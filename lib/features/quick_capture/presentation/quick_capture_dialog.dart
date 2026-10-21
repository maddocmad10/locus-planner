import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/quick_capture_provider.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/utils/day_math.dart';
import '../../diary/data/diary_repository.dart';
import '../../events/data/event_repository.dart';
import '../../tasks/data/task_repository.dart';

enum _CaptureKind { event, todo, diary }

/// Lightweight keyboard-first dialog for capturing an event, to-do, or diary
/// note without navigating away from the current page.
class QuickCaptureDialog extends ConsumerStatefulWidget {
  const QuickCaptureDialog({super.key});

  @override
  ConsumerState<QuickCaptureDialog> createState() => _QuickCaptureDialogState();
}

class _QuickCaptureDialogState extends ConsumerState<QuickCaptureDialog> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  _CaptureKind _kind = _CaptureKind.event;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      switch (_kind) {
        case _CaptureKind.event:
          await ref
              .read(eventRepositoryProvider)
              .create(title: text, startTime: AppClock.now());
        case _CaptureKind.todo:
          await ref.read(taskRepositoryProvider).add(title: text);
        case _CaptureKind.diary:
          final today = DayMath.dateOnly(AppClock.now());
          final existing = await ref
              .read(diaryRepositoryProvider)
              .forDate(today);
          final content = existing == null || existing.content.trim().isEmpty
              ? text
              : '${existing.content.trim()}\n\n$text';
          await ref
              .read(diaryRepositoryProvider)
              .save(date: today, mood: existing?.mood ?? 3, content: content);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accelerator = ref.read(quickCaptureServiceProvider).accelerator;
    return AlertDialog(
      title: const Text('Quick capture'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_CaptureKind>(
              segments: const [
                ButtonSegment(
                  value: _CaptureKind.event,
                  label: Text('Event'),
                  icon: Icon(Icons.event),
                ),
                ButtonSegment(
                  value: _CaptureKind.todo,
                  label: Text('To-do'),
                  icon: Icon(Icons.check_box_outlined),
                ),
                ButtonSegment(
                  value: _CaptureKind.diary,
                  label: Text('Diary'),
                  icon: Icon(Icons.book_outlined),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) {
                setState(() => _kind = selection.first);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: switch (_kind) {
                  _CaptureKind.event => 'Event title',
                  _CaptureKind.todo => 'To-do title',
                  _CaptureKind.diary => 'Diary note (mood 3)',
                },
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Text(
              'Press $accelerator anywhere to open this again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}

/// Shows the quick-capture dialog. Safe to call from a post-frame callback
/// after the main window has been revealed.
Future<void> showQuickCaptureDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const QuickCaptureDialog(),
  );
}
