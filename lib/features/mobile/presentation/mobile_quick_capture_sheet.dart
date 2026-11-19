part of '../mobile_app.dart';

class _QuickCaptureSheet extends ConsumerStatefulWidget {
  const _QuickCaptureSheet({this.initialStart});

  final DateTime? initialStart;

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
  bool _startPicked = false;
  DateTime _start = AppClock.now();

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart ?? AppClock.now();
  }

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
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      _startPicked = true;
    });
  }

  /// Android 13+ only shows notifications once the user has allowed them, and
  /// the best moment to ask is right after they set a reminder.
  Future<void> _ensureNotificationPermission() async {
    final platform = ref.read(reminderPlatformProvider);
    final capabilities = await platform.capabilities();
    if (capabilities.supported && !capabilities.notificationsAllowed) {
      await ref
          .read(appLockControllerProvider.notifier)
          .runExternal(platform.requestNotificationPermission);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _kind == 2
        ? null
        : NaturalLanguageQuickAdd.parse(_controller.text);
    final captureStart = _startPicked ? _start : (parsed?.date ?? _start);
    return Padding(
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
                'e.g. Team standup tomorrow 9am',
                'e.g. Review draft every Monday !',
                'A thought for today',
              ][_kind],
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (parsed != null && parsed.hasDetails) ...[
            const SizedBox(height: 10),
            QuickAddPreview(parsed: parsed),
          ],
          if (_kind == 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickStart,
              icon: const Icon(Icons.schedule),
              label: Text(DateFormat('EEE d MMM, h:mm a').format(captureStart)),
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
                    onSelected: (_) =>
                        setState(() => _reminder = option.minutes),
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
                    final capture = _kind == 2
                        ? null
                        : NaturalLanguageQuickAdd.parse(text);
                    final title = capture?.title ?? text;
                    final start = capture?.date ?? captureStart;
                    setState(() => _saving = true);
                    try {
                      final db = ref.read(databaseProvider);
                      if (_kind == 0) {
                        final reminder = _reminder;
                        if (reminder != null &&
                            !start
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
                                title: Value(title),
                                startTime: Value(start),
                                allDay: Value(capture?.allDay ?? false),
                                recurrenceRule: Value(capture?.recurrenceRule),
                                hasReminder: Value(reminder != null),
                                reminderMinutes: Value(reminder ?? 10),
                              ),
                            );
                        if (reminder != null) {
                          await _ensureNotificationPermission();
                        }
                      } else if (_kind == 1) {
                        await ref
                            .read(taskRepositoryProvider)
                            .add(
                              title: title,
                              dueDate: capture?.date,
                              priority: TaskPriority.fromValue(
                                capture?.priority.value ?? 0,
                              ),
                              tags: capture?.tags ?? const <String>[],
                              recurrenceRule: capture?.recurrenceRule,
                            );
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
}
