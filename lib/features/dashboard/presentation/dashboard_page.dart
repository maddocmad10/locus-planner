import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  void _showReview(BuildContext context, WidgetRef ref) {
    final winCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final tomorrowCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('End of Day Review'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: winCtrl, decoration: InputDecoration(labelText: '1 win today?')),
        SizedBox(height:12), TextField(controller: blockCtrl, decoration: InputDecoration(labelText: '1 blocker?')),
        SizedBox(height:12), TextField(controller: tomorrowCtrl, decoration: InputDecoration(labelText: 'Top 1 for tomorrow?')),
      ])),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: Text('Cancel')),
        FilledButton(onPressed: () async {
          final db = ref.read(databaseProvider);
          final now = DateTime.now();
          final dayStart = DateTime(now.year, now.month, now.day);
          final newContent = 'Win: ${winCtrl.text}\nBlocker: ${blockCtrl.text}\nTomorrow: ${tomorrowCtrl.text}';
          final existing = await db.entryForDate(dayStart);
          if (existing == null) {
            await db.into(db.diaryEntries).insert(DiaryEntriesCompanion(id: drift.Value(Uuid().v4()), date: drift.Value(dayStart), mood: drift.Value(3), content: drift.Value(newContent)));
          } else {
            await (db.update(db.diaryEntries)..where((t)=>t.id.equals(existing.id))).write(DiaryEntriesCompanion(content: drift.Value('${existing.content}\n\n$newContent')));
          }
          Navigator.pop(ctx);
          await NotificationService.instance.showNow(title: 'Review Saved', body: 'Saved to diary');
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to diary. Streak +1')));
        }, child: Text('Save'))
      ],
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text('Today'), automaticallyImplyLeading: false, actions: [
        Padding(padding: EdgeInsets.only(right:16), child: FilledButton.icon(onPressed: ()=> _showReview(context, ref), icon: Icon(Icons.nightlight), label: Text('End of Day Review')))
      ]),
      body: ListView(padding: EdgeInsets.all(24), children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          FutureBuilder<int>(future: db.focusMinutesToday(), builder: (c,s){ return _StatCard(title: 'Focus Today', value: '${s.data?? 0} min', icon: Icons.timer); }),
          StreamBuilder<List<Habit>>(stream: db.watchHabits(), builder: (c,s){ return _StatCard(title: 'Active Habits', value: '${s.data?.length?? 0}', icon: Icons.check_circle); }),
          StreamBuilder<List<Event>>(stream: db.watchEventsForDay(DateTime.now()), builder: (c,s){ return _StatCard(title: 'Events Today', value: '${s.data?.length?? 0}', icon: Icons.event); }),
          FutureBuilder<int>(future: db.diaryStreak(), builder: (c,s){ return _StatCard(title: 'Diary Streak', value: '${s.data?? 0} days', icon: Icons.local_fire_department); }),
        ]),
        SizedBox(height:24),
        Text('Today\'s schedule', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height:12),
        StreamBuilder<List<Event>>(stream: db.watchEventsForDay(DateTime.now()), builder: (c,snap){
          final events = snap.data?? [];
          if (events.isEmpty) return Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No events today. Add one in Events tab.')));
          return Column(children: events.map((e)=>Card(child: ListTile(title: Text(e.title), subtitle: Text('${e.startTime.hour}:${e.startTime.minute.toString().padLeft(2,'0')} - ${e.category}'), trailing: e.hasReminder? Icon(Icons.notifications_active) : null))).toList());
        }),
        SizedBox(height:24),
        Text('Active Projects', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height:12),
        StreamBuilder<List<Project>>(stream: db.watchProjects(), builder: (c,snap){
          final projects = snap.data?.take(3).toList()?? [];
          if (projects.isEmpty) return Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No projects yet')));
          return Column(children: projects.map((p)=>FutureBuilder<int>(future: db.projectProgressPercent(p.id), builder: (c, prog){ return Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.name, style: TextStyle(fontWeight: FontWeight.bold)), SizedBox(height:8), LinearProgressIndicator(value: (prog.data?? 0)/100), SizedBox(height:4), Text('${prog.data?? 0}%')] ))); })).toList());
        }),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value; final IconData icon;
  const _StatCard({required this.title, required this.value, required this.icon});
  @override Widget build(BuildContext context) {
    return SizedBox(width: 220, child: Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), SizedBox(height:12), Text(value, style: Theme.of(context).textTheme.headlineSmall), Text(title)]))));
  }
}
