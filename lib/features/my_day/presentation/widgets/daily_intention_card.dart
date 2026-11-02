import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/user_action_error.dart';
import '../../data/my_day_models.dart';
import '../../providers/my_day_providers.dart';

/// A short statement of what the user wants to accomplish on the selected day.
/// The plan row is created on the first save, never just by opening the day.
class DailyIntentionCard extends ConsumerStatefulWidget {
  const DailyIntentionCard({super.key, required this.plan});

  final DailyPlanView plan;

  @override
  ConsumerState<DailyIntentionCard> createState() => _DailyIntentionCardState();
}

class _DailyIntentionCardState extends ConsumerState<DailyIntentionCard> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late DateTime _day;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = widget.plan.day;
    _controller.text = widget.plan.intention;
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant DailyIntentionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Switching days must never write the old day's draft into the new day,
    // even if the field still has focus.
    if (oldWidget.plan.day != widget.plan.day) {
      _day = widget.plan.day;
      if (_controller.text != widget.plan.intention) {
        _controller.text = widget.plan.intention;
      }
      return;
    }
    // Remote edits may arrive while the field is idle. Never overwrite text
    // the user is currently typing.
    if (!_focus.hasFocus && _controller.text != widget.plan.intention) {
      _controller.text = widget.plan.intention;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) _save();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text == widget.plan.intention.trim() || _saving) return;
    setState(() => _saving = true);
    final saved = await runUserMutation(
      context,
      () => ref.read(myDayControllerProvider).setIntention(_day, text),
      failureMessage: 'Could not save the daily intention.',
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!saved) _controller.text = widget.plan.intention;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('Daily intention', style: theme.textTheme.titleMedium),
                const Spacer(),
                if (_saving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    tooltip: 'Save intention',
                    icon: const Icon(Icons.check),
                    onPressed:
                        _controller.text.trim() == widget.plan.intention.trim()
                        ? null
                        : _save,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What matters most today?',
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
    );
  }
}
