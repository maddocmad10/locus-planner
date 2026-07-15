import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/notification_service.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});
  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;
  final _events = <String>[];

  void _addEvent() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('New Event'),
      content: TextField(controller: ctrl, decoration: InputDecoration(labelText: 'Title')),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: Text('Cancel')),
        FilledButton(onPressed: () async {
          setState(()=> _events.add(ctrl.text));
          await NotificationService.instance.showNow(title: 'Event Created', body: ctrl.text);
          await NotificationService.instance.scheduleEventReminder(title: ctrl.text, scheduledTime: DateTime.now().add(Duration(seconds: 10)));
          Navigator.pop(ctx);
        }, child: Text('Save')),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Events'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addEvent, label: Text('New Event'), icon: Icon(Icons.add)),
      body: Row(children: [
        SizedBox(width: 380, child: Card(margin: EdgeInsets.all(16), child: TableCalendar(firstDay: DateTime.utc(2023), lastDay: DateTime.utc(2030), focusedDay: _focused, selectedDayPredicate: (d)=> isSameDay(_selected, d), onDaySelected: (s,f)=> setState((){ _selected=s; _focused=f; })))), 
        Expanded(child: ListView(padding: EdgeInsets.all(16), children: _events.map((e)=> Card(child: ListTile(title: Text(e), subtitle: Text('Today 10:00 AM'), trailing: Icon(Icons.notifications_active_outlined)))).toList())),
      ]),
    );
  }
}
