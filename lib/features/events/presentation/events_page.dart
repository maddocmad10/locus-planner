import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/command_action_provider.dart';

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});

  @override
  ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Event>> _eventsByDay = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadAllEventsForMarkers();
    // See the note in tasks_page.dart: the palette sets the action before this
    // page exists, so pick it up once on first build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(commandActionProvider) == CommandAction.newEvent) {
        ref.read(commandActionProvider.notifier).state = CommandAction.none;
        _showEventDialog();
      }
    });
  }

  // Load all events to show markers on calendar
  Future<void> _loadAllEventsForMarkers() async {
    final db = ref.read(databaseProvider);
    final allEvents = await db.watchAllEvents().first;

    final Map<DateTime, List<Event>> eventsMap = {};
    for (var event in allEvents) {
      final day = DateTime(event.startTime.year, event.startTime.month, event.startTime.day);
      if (eventsMap[day] == null) eventsMap[day] = [];
      eventsMap[day]!.add(event);
    }

    setState(() {
      _eventsByDay = eventsMap;
    });
  }

  List<Event> _getEventsForDay(DateTime day) {
    return _eventsByDay[DateTime(day.year, day.month, day.day)] ?? [];
  }

  // Show Add or Edit Dialog
  void _showEventDialog({Event? existingEvent}) {
    final isEditing = existingEvent != null;

    final titleController = TextEditingController(text: existingEvent?.title ?? '');
    final descController = TextEditingController(text: existingEvent?.description ?? '');
    String selectedCategory = existingEvent?.category ?? 'general';
    DateTime selectedDate = existingEvent?.startTime ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(existingEvent?.startTime ?? DateTime.now());
    bool hasReminder = existingEvent?.hasReminder ?? false;
    int reminderMinutes = existingEvent?.reminderMinutes ?? 10;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Edit Event' : 'Add New Event'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Event Title*'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description (optional)'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),

                  // Category Dropdown
                  DropdownButtonFormField<String>(
                    initialValue: selectedCategory,
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('General')),
                      DropdownMenuItem(value: 'work', child: Text('Work')),
                      DropdownMenuItem(value: 'personal', child: Text('Personal')),
                      DropdownMenuItem(value: 'health', child: Text('Health')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedCategory = val!),
                    decoration: const InputDecoration(labelText: 'Category'),
                  ),
                  const SizedBox(height: 12),

                  // Date Picker
                  ListTile(
                    title: Text('Date: ${DateFormat('MMM dd, yyyy').format(selectedDate)}'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                  ),

                  // Time Picker
                  ListTile(
                    title: Text('Time: ${selectedTime.format(context)}'),
                    trailing: const Icon(Icons.access_time),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                  ),

                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('Set Reminder'),
                    value: hasReminder,
                    onChanged: (val) => setDialogState(() => hasReminder = val!),
                  ),

                  if (hasReminder)
                    DropdownButtonFormField<int>(
                      initialValue: reminderMinutes,
                      items: const [5, 10, 15, 30, 60]
                          .map((m) => DropdownMenuItem(value: m, child: Text('$m minutes before')))
                          .toList(),
                      onChanged: (val) => setDialogState(() => reminderMinutes = val!),
                      decoration: const InputDecoration(labelText: 'Reminder Time'),
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
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Title cannot be empty')),
                    );
                    return;
                  }

                  final db = ref.read(databaseProvider);
                  final eventDateTime = DateTime(
                    selectedDate.year,
                    selectedDate.month,
                    selectedDate.day,
                    selectedTime.hour,
                    selectedTime.minute,
                  );

                  if (isEditing) {
                    // UPDATE existing event
                    await (db.update(db.events)
                          ..where((t) => t.id.equals(existingEvent.id)))
                        .write(EventsCompanion(
                      title: drift.Value(titleController.text.trim()),
                      description: drift.Value(descController.text.trim()),
                      startTime: drift.Value(eventDateTime),
                      category: drift.Value(selectedCategory),
                      hasReminder: drift.Value(hasReminder),
                      reminderMinutes: drift.Value(reminderMinutes),
                    ));
                  } else {
                    // INSERT new event
                    final newEvent = EventsCompanion(
                      id: drift.Value(const Uuid().v4()),
                      title: drift.Value(titleController.text.trim()),
                      description: drift.Value(descController.text.trim()),
                      startTime: drift.Value(eventDateTime),
                      category: drift.Value(selectedCategory),
                      hasReminder: drift.Value(hasReminder),
                      reminderMinutes: drift.Value(reminderMinutes),
                    );
                    await db.into(db.events).insert(newEvent);

                    // Schedule reminder if enabled
                    if (hasReminder) {
                      final reminderTime = eventDateTime.subtract(Duration(minutes: reminderMinutes));
                      await NotificationService.instance.scheduleEventReminder(
                        title: 'Reminder: ${titleController.text}',
                        scheduledTime: reminderTime,
                        body: 'Your event starts in $reminderMinutes minutes',
                      );
                    }
                  }

                  Navigator.pop(context);
                  _loadAllEventsForMarkers(); // Refresh calendar markers
                },
                child: Text(isEditing ? 'Update Event' : 'Add Event'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteEvent(Event event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text('Are you sure you want to delete "${event.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(databaseProvider);
      await (db.delete(db.events)..where((t) => t.id.equals(event.id))).go();
      _loadAllEventsForMarkers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final selectedDay = _selectedDay ?? DateTime.now();

    // Listen for command palette action
ref.listen<CommandAction>(commandActionProvider, (previous, next) {
  if (next == CommandAction.newEvent) {
    // Reset the action
    ref.read(commandActionProvider.notifier).state = CommandAction.none;
    // Call your existing add event method
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showEventDialog(); // ← use the name of your add/edit dialog method
    });
  }
});

    return Scaffold(
      appBar: AppBar(
        title: const Text('Events'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllEventsForMarkers,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEventDialog(),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          // Calendar
          TableCalendar<Event>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            eventLoader: _getEventsForDay,
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
            },
            calendarStyle: const CalendarStyle(
              markersMaxCount: 3,
              markerDecoration: BoxDecoration(
                color: Color(0xFF6C5CE7),
                shape: BoxShape.circle,
              ),
            ),
          ),

          const Divider(height: 1),

          // Events List for Selected Day
          Expanded(
            child: StreamBuilder<List<Event>>(
              stream: db.watchEventsForDay(selectedDay),
              builder: (context, snapshot) {
                final events = snapshot.data ?? [];

                if (events.isEmpty) {
                  return const Center(
                    child: Text(
                      'No events on this day.\nTap + to add one.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  itemBuilder: (context, index) {
                    final event = events[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF6C5CE7).withValues(alpha: 0.1),
                          child: const Icon(Icons.event, color: Color(0xFF6C5CE7)),
                        ),
                        title: Text(event.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${DateFormat('hh:mm a').format(event.startTime)} • ${event.category}'),
                            if (event.description != null && event.description!.isNotEmpty)
                              Text(event.description!, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (event.hasReminder)
                              const Icon(Icons.notifications_active, color: Colors.orange, size: 20),
                            IconButton(
                              icon: const Icon(Icons.edit, size: 20),
                              onPressed: () => _showEventDialog(existingEvent: event),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                              onPressed: () => _deleteEvent(event),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
