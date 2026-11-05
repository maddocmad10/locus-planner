import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/day_math.dart';
import '../data/schedule_block_repository.dart';

/// Edits the time, kind and note of one schedule block. Moving/resizing is also
/// possible by dragging, but this dialog is the precise and keyboard-friendly
/// path.
class BlockEditorDialog extends ConsumerStatefulWidget {
  const BlockEditorDialog({
    super.key,
    required this.block,
    required this.title,
  });

  final TaskScheduleBlock block;
  final String title;

  static Future<void> show(
    BuildContext context, {
    required TaskScheduleBlock block,
    required String title,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => BlockEditorDialog(block: block, title: title),
    );
  }

  @override
  ConsumerState<BlockEditorDialog> createState() => _BlockEditorDialogState();
}

class _BlockEditorDialogState extends ConsumerState<BlockEditorDialog> {
  late DateTime _day;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late String _kind;
  late final TextEditingController _note;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _day = DayMath.dateOnly(widget.block.startAt);
    _start = TimeOfDay.fromDateTime(widget.block.startAt);
    _end = TimeOfDay.fromDateTime(widget.block.endAt);
    _kind = widget.block.blockKind;
    _note = TextEditingController(text: widget.block.note ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay time) =>
      DateTime(_day.year, _day.month, _day.day, time.hour, time.minute);

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _day = DayMath.dateOnly(picked));
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final start = _at(_start);
    var end = _at(_end);
    if (!end.isAfter(start)) {
      // A block that ends "before" its start most likely crosses midnight.
      end = end.add(const Duration(days: 1));
    }
    final minutes = end.difference(start).inMinutes;
    if (minutes < 5 || minutes > 24 * 60) {
      setState(() {
        _error = 'A block must last between 5 minutes and 24 hours.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final previous = widget.block;
    try {
      await ref
          .read(scheduleBlockRepositoryProvider)
          .updateBlock(
            id: previous.id,
            startAt: start,
            endAt: end,
            blockKind: _kind,
            note: _note.text,
          );
      ref
          .read(undoServiceProvider)
          .offer(
            label: 'block edited',
            restore: () async {
              await ref
                  .read(scheduleBlockRepositoryProvider)
                  .restoreBlock(previous);
            },
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete time block?'),
        content: Text('The task itself is not deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(scheduleBlockRepositoryProvider).deleteBlock(widget.block);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(
                  '${_day.year}-${_day.month.toString().padLeft(2, '0')}-'
                  '${_day.day.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(start: true),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('Start ${_start.format(context)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickTime(start: false),
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text('End ${_end.format(context)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: const [
                  DropdownMenuItem(value: 'work', child: Text('Work')),
                  DropdownMenuItem(value: 'focus', child: Text('Focus')),
                  DropdownMenuItem(value: 'buffer', child: Text('Buffer')),
                ],
                onChanged: (value) => setState(() => _kind = value ?? 'work'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('Delete block'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// Keep the import explicit so the dialog's undo restore path stays typed.
