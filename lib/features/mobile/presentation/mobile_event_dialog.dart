part of '../mobile_app.dart';

class _EventEditResult {
  const _EventEditResult({
    this.title,
    this.description,
    this.descriptionFormat = 'plain',
    this.start,
    this.allDay = false,
    this.delete = false,
    this.recurrenceRule,
    this.skipOccurrence,
  });

  final String? title;
  final String? description;
  final String descriptionFormat;
  final DateTime? start;
  final bool allDay;
  final bool delete;
  final String? recurrenceRule;
  final DateTime? skipOccurrence;
}

class _EventEditDialog extends StatefulWidget {
  const _EventEditDialog({
    required this.event,
    required this.start,
    this.onDownload,
    this.onKeep,
    this.imageResolver,
  });

  final Event event;
  final DateTime start;
  final Md1ImageResolver? imageResolver;
  final Future<bool> Function(Attachment attachment)? onDownload;
  final Future<void> Function(Attachment attachment, bool pinned)? onKeep;

  @override
  State<_EventEditDialog> createState() => _EventEditDialogState();
}

class _EventEditDialogState extends State<_EventEditDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _descriptionController;
  late DateTime _start;
  late bool _allDay;
  late String _recurrenceRule;
  late String _descriptionFormat;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.event.title);
    _descriptionController = TextEditingController(
      text: widget.event.description ?? '',
    );
    _start = widget.start;
    _allDay = widget.event.allDay;
    _recurrenceRule = widget.event.recurrenceRule ?? Recurrence.none;
    _descriptionFormat = widget.event.descriptionFormat;
  }

  @override
  void dispose() {
    _controller.dispose();
    _descriptionController.dispose();
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
          const SizedBox(height: 12),
          NotesField(
            controller: _descriptionController,
            format: _descriptionFormat,
            onFormatChanged: (value) =>
                setState(() => _descriptionFormat = value),
            label: 'Description',
            hint: 'Agenda, location, links…',
            minLines: 2,
            maxLines: 4,
            imageResolver: widget.imageResolver,
          ),
          const SizedBox(height: 8),
          AttachmentStrip(
            eventId: widget.event.id,
            onDownload: widget.onDownload,
            onKeep: widget.onKeep,
          ),
          const SizedBox(height: 8),
          if (!_allDay)
            OutlinedButton.icon(
              onPressed: _pickStart,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEE d MMM yyyy, h:mm a').format(_start)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('All day'),
            value: _allDay,
            onChanged: (value) => setState(() {
              _allDay = value;
              if (value) {
                _start = DateTime(_start.year, _start.month, _start.day);
              }
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _recurrenceRule,
            items: Recurrence.values
                .map(
                  (rule) => DropdownMenuItem(
                    value: rule,
                    child: Text(Recurrence.label(rule)),
                  ),
                )
                .toList(),
            onChanged: (value) =>
                setState(() => _recurrenceRule = value ?? Recurrence.none),
            decoration: const InputDecoration(labelText: 'Repeat'),
          ),
          if (recurring) ...[
            const SizedBox(height: 8),
            Text(
              'Changes apply to every repeat. Skip this occurrence to remove '
              'only the selected day.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _EventEditResult(skipOccurrence: widget.start),
                ),
                icon: const Icon(Icons.event_busy_outlined),
                label: const Text('Skip this occurrence'),
              ),
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
            _EventEditResult(
              title: _controller.text.trim(),
              description: _descriptionController.text.trim().isEmpty
                  ? null
                  : _descriptionController.text.trim(),
              descriptionFormat: _descriptionController.text.trim().isEmpty
                  ? 'plain'
                  : _descriptionFormat,
              start: _start,
              allDay: _allDay,
              recurrenceRule: _recurrenceRule,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
