part of '../mobile_app.dart';

class _TaskEditResult {
  const _TaskEditResult({
    required this.title,
    required this.notesFormat,
    this.notes,
  });

  final String title;
  final String? notes;
  final String notesFormat;
}

/// Owns its text controllers so they are disposed with the dialog route,
/// after the exit animation, rather than while the fields still reference them.
class _MobileTaskEditDialog extends StatefulWidget {
  const _MobileTaskEditDialog({
    required this.todoId,
    required this.title,
    required this.notesFormat,
    this.notes,
    this.completions = const [],
    this.onDownload,
    this.onKeep,
    this.imageResolver,
  });

  final String todoId;
  final Md1ImageResolver? imageResolver;
  final Future<bool> Function(Attachment attachment)? onDownload;
  final Future<void> Function(Attachment attachment, bool pinned)? onKeep;
  final String title;
  final String? notes;
  final String notesFormat;
  final List<TodoCompletion> completions;

  @override
  State<_MobileTaskEditDialog> createState() => _MobileTaskEditDialogState();
}

class _MobileTaskEditDialogState extends State<_MobileTaskEditDialog> {
  late final TextEditingController _titleController = TextEditingController(
    text: widget.title,
  );
  late final TextEditingController _notesController = TextEditingController(
    text: widget.notes ?? '',
  );
  late String _notesFormat = widget.notesFormat;

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit task'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.completions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Completed ${widget.completions.length} '
                    'time${widget.completions.length == 1 ? '' : 's'}, last on '
                    '${DateFormat.yMMMd().format(widget.completions.first.completedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            NotesField(
              controller: _notesController,
              format: _notesFormat,
              onFormatChanged: (value) => setState(() => _notesFormat = value),
              minLines: 2,
              maxLines: 4,
              imageResolver: widget.imageResolver,
            ),
            const SizedBox(height: 12),
            AttachmentStrip(
              todoId: widget.todoId,
              onDownload: widget.onDownload,
              onKeep: widget.onKeep,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final notes = _notesController.text.trim();
            Navigator.pop(
              context,
              _TaskEditResult(
                title: _titleController.text.trim(),
                notes: notes.isEmpty ? null : notes,
                notesFormat: notes.isEmpty ? 'plain' : _notesFormat,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
