import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';

class EventsPage extends ConsumerStatefulWidget {
  const EventsPage({super.key});
  @override ConsumerState<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends ConsumerState<EventsPage> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();

  void _addEvent() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'general';
    bool hasReminder = false;
    int reminderMin = 10;
    DateTime eventDate = _selected;
    TimeOfDay eventTime = TimeOfDay.now();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setD)=>AlertDialog(
      title: Text('New Event'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, decoration: InputDecoration(labelText: 'Title *')),
        SizedBox(height:12), TextField(controller: descCtrl, decoration: InputDecoration(labelText: 'Description')),
        SizedBox(height:12),
        DropdownButtonFormField<String>(value: category, items: ['general','work','personal','health'].map((c)=>DropdownMenuItem(value:c, child: Text(c))).toList(), onChanged: (v){ if(v!=null) setD(()=>category=v); }, decoration: InputDecoration(labelText: 'Category')),
        SizedBox(height:12),
        Row(children: [
          Text('${eventDate.year}-${eventDate.month}-${eventDate.day} ${eventTime.format(context)}'),
          Spacer(), TextButton(onPressed: () async { final d = await showDatePicker(context: context, firstDate: DateTime(2023), lastDate: DateTime(2030), initialDate: eventDate); if(d!=null) setD(()=>eventDate=d); }, child: Text('Date')),
          TextButton(onPressed: () async { final t = await showTimePicker(context: context, initialTime: eventTime); if(t!=null) setD(()=>eventTime=t); }, child: Text('Time')),
        ]),
        SwitchListTile(title: Text('Reminder'), value: hasReminder, onChanged: (v)=>setD(()=>hasReminder=v)),
        if (hasReminder) DropdownButtonFormField<int>(value: reminderMin, items: [5,10,15,30,60].map((m)=>DropdownMenuItem(value:m, child: Text('$m min before'))).toList(), onChanged: (v){ if(v!=null) setD(()=>reminderMin=v); }),
      ])),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: Text('Cancel')),
        FilledButton(onPressed: () async {
          if (titleCtrl.text.trim().isEmpty) return;
          final db = ref.read(databaseProvider);
          final start = DateTime(eventDate.year, eventDate.month, eventDate.day, eventTime.hour, eventTime.minute);
          await db.into(db.events).insert(EventsCompanion(
            id: drift.Value(Uuid().v4()),
            title: drift.Value(titleCtrl.text.trim()),
            description: drift.Value(descCtrl.text.trim().isEmpty? null : descCtrl.text.trim()),
            startTime: drift.Value(start),
            category: drift.Value(category),
            hasReminder: drift.Value(hasReminder),
            reminderMinutes: drift.Value(reminderMin),
          ));
          if (hasReminder) {
            await NotificationService.instance.scheduleEventReminder(title: titleCtrl.text.trim(), scheduledTime: start.subtract(Duration(minutes: reminderMin)));
          }
          await NotificationService.instance.showNow(title: 'Event Created', body: titleCtrl.text.trim());
          Navigator.pop(ctx);
        }, child: Text('Save')),
      ],
    )));
  }

  @override Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Events'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addEvent, label: Text('New Event'), icon: Icon(Icons.add)),
      body: Row(children: [
        SizedBox(width: 380, child: Card(margin: EdgeInsets.all(16), child: TableCalendar(
          firstDay: DateTime.utc(2023), lastDay: DateTime.utc(2030), focusedDay: _focused,
          selectedDayPredicate: (d)=> isSameDay(_selected, d),
          onDaySelected: (s,f)=> setState((){ _selected=s; _focused=f; }),
          calendarFormat: CalendarFormat.month,
          eventLoader: (day){ return []; },
        ))),
        Expanded(child: StreamBuilder<List<Event>>(stream: db.watchEventsForDay(_selected), builder: (c,snap){
          final events = snap.data?? [];
          if (events.isEmpty) return Center(child: Text('No events for ${ _selected.month}/${_selected.day}'));
          return ListView.builder(padding: EdgeInsets.all(16), itemCount: events.length, itemBuilder: (c,i){
            final e = events[i];
            return Card(child: ListTile(
              title: Text(e.title),
              subtitle: Text('${e.startTime.hour}:${e.startTime.minute.toString().padLeft(2,'0')} - ${e.category}${e.description!= null? ' - ${e.description}' : ''}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.hasReminder) Icon(Icons.notifications_active_outlined),
                IconButton(icon: Icon(Icons.delete_outline), onPressed: () async { await (db.delete(db.events)..where((t)=>t.id.equals(e.id))).go(); }),
              ]),
            ));
          });
        })),
      ]),
    );
  }
}
