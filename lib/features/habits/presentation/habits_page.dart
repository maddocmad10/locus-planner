import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';

class HabitsPage extends StatefulWidget {
  const HabitsPage({super.key});
  @override State<HabitsPage> createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  final db = AppDatabase();
  final _nameCtrl = TextEditingController();

  void _addHabit() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('New Habit'),
      content: TextField(controller: _nameCtrl, decoration: InputDecoration(labelText: 'e.g., Morning run')),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: Text('Cancel')),
        FilledButton(onPressed: () async {
          final id = Uuid().v4();
          await db.into(db.habits).insert(HabitsCompanion(id: drift.Value(id), name: drift.Value(_nameCtrl.text), createdAt: drift.Value(DateTime.now())));
          _nameCtrl.clear();
          Navigator.pop(ctx);
        }, child: Text('Add'))
      ],
    ));
  }

  Future<void> _toggleToday(Habit habit, bool isDone) async {
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (isDone) {
      final existing = await (db.select(db.habitLogs)..where((t) => t.habitId.equals(habit.id) & t.date.equals(today))).get();
      for (var e in existing) { await (db.delete(db.habitLogs)..where((t) => t.id.equals(e.id))).go(); }
    } else {
      await db.into(db.habitLogs).insert(HabitLogsCompanion(id: drift.Value(Uuid().v4()), habitId: drift.Value(habit.id), date: drift.Value(today), completed: drift.Value(true)));
    }
    setState((){});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Habits'), automaticallyImplyLeading: false),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addHabit, label: Text('New Habit'), icon: Icon(Icons.add)),
      body: StreamBuilder<List<Habit>>(
        stream: db.watchHabits(),
        builder: (ctx, snap) {
          final habits = snap.data?? [];
          if (habits.isEmpty) return Center(child: Text('No habits yet. Tap New Habit.'));
          return ListView.builder(padding: EdgeInsets.all(16), itemCount: habits.length, itemBuilder: (c,i){
            final h = habits[i];
            return FutureBuilder(future: db.logsForHabitToday(h.id), builder: (c2, lsnap){
              final done = (lsnap.data?.isNotEmpty?? false);
              return Card(child: ListTile(leading: Text(h.icon, style: TextStyle(fontSize: 24)), title: Text(h.name), trailing: Checkbox(value: done, onChanged: (_)=> _toggleToday(h, done)), onTap: ()=> _toggleToday(h, done)));
            });
          });
        },
      ),
    );
  }
}
