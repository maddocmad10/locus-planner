import 'package:flutter/material.dart';
import '../../../core/services/notification_service.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  void _showReview(BuildContext context) {
    final winCtrl = TextEditingController();
    final blockCtrl = TextEditingController();
    final tomorrowCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text('End of Day Review'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: winCtrl, decoration: InputDecoration(labelText: '1 win today?')),
        SizedBox(height: 12),
        TextField(controller: blockCtrl, decoration: InputDecoration(labelText: '1 blocker?')),
        SizedBox(height: 12),
        TextField(controller: tomorrowCtrl, decoration: InputDecoration(labelText: 'Top 1 for tomorrow?')),
      ])),
      actions: [
        TextButton(onPressed: ()=> Navigator.pop(ctx), child: Text('Cancel')),
        FilledButton(onPressed: () async {
          Navigator.pop(ctx);
          await NotificationService.instance.showNow(title: 'Review Saved', body: 'Great job today!');
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to diary. Streak +1')));
        }, child: Text('Save'))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Today'), automaticallyImplyLeading: false, actions: [
        Padding(padding: EdgeInsets.only(right:16), child: FilledButton.icon(onPressed: ()=> _showReview(context), icon: Icon(Icons.nightlight), label: Text('End of Day Review')))
      ]),
      body: ListView(padding: EdgeInsets.all(24), children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          _StatCard(title: 'Events Today', value: '3', icon: Icons.event),
          _StatCard(title: 'Active Habits', value: '4', icon: Icons.check_circle),
          _StatCard(title: 'Focus Today', value: '52 min', icon: Icons.timer),
          _StatCard(title: 'Diary Streak', value: '12 days', icon: Icons.local_fire_department),
        ]),
        SizedBox(height: 24),
        Text('Active Projects', style: Theme.of(context).textTheme.titleLarge),
        SizedBox(height: 12),
        Card(child: Padding(padding: EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Locus Windows Build'), SizedBox(height: 8), LinearProgressIndicator(value: 0.72), SizedBox(height: 8), Text('72% complete - Focus sessions logged')] ))),
        SizedBox(height: 24),
        Text('Tip: Use Focus mode to log deep work directly to a project. Each 25 min adds 5% progress.', style: TextStyle(color: Colors.black54)),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title, value; final IconData icon;
  const _StatCard({required this.title, required this.value, required this.icon});
  @override Widget build(BuildContext context) {
    return SizedBox(width: 220, child: Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon), SizedBox(height: 12), Text(value, style: Theme.of(context).textTheme.headlineSmall), Text(title)]))));
  }
}
