import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/notification_service.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});
  @override ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  Timer? _timer;
  int _seconds = 25 * 60;
  int _preset = 25;
  bool _running = false;
  String? _selectedProjectId;

  void _start() {
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) { t.cancel(); _onComplete(); } else { setState(() => _seconds--); }
    });
  }
  void _pause() { _timer?.cancel(); setState(() => _running = false); }
  void _reset() { _timer?.cancel(); setState(() { _seconds = _preset * 60; _running = false; }); }
  void _setPreset(int min) { _timer?.cancel(); setState(() { _preset = min; _seconds = min * 60; _running = false; }); }

  Future<void> _onComplete() async {
    final db = ref.read(databaseProvider);
    setState(() => _running = false);
    await db.into(db.focusSessions).insert(FocusSessionsCompanion(
      id: drift.Value(Uuid().v4()),
      projectId: drift.Value(_selectedProjectId),
      startTime: drift.Value(DateTime.now().subtract(Duration(minutes: _preset))),
      durationMinutes: drift.Value(_preset),
      note: const drift.Value('Pomodoro'),
    ));
    if (_selectedProjectId != null) {
      final logs = await (db.select(db.progressLogs)..where((l) => l.projectId.equals(_selectedProjectId!))..orderBy([(t) => drift.OrderingTerm.desc(t.timestamp)])).get();
      final last = logs.isEmpty ? 0 : logs.first.value;
      final next = (last + 5).clamp(0, 100);
      await db.into(db.progressLogs).insert(ProgressLogsCompanion(
        id: drift.Value(Uuid().v4()),
        projectId: drift.Value(_selectedProjectId!),
        value: drift.Value(next),
        note: drift.Value('Focus +$_preset min'),
        timestamp: drift.Value(DateTime.now()),
      ));
    }
    await NotificationService.instance.showNow(title: 'Focus Complete', body: '$_preset min logged');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$_preset min logged${_selectedProjectId != null ? ' +5% to project' : ''}')));
    setState(() => _seconds = _preset * 60);
  }

  String get _timeStr {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override void dispose() { _timer?.cancel(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Focus'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Row(children: [
            ChoiceChip(label: Text('25m'), selected: _preset==25, onSelected: (_)=>_setPreset(25)),
            SizedBox(width:8), ChoiceChip(label: Text('45m'), selected: _preset==45, onSelected: (_)=>_setPreset(45)),
            SizedBox(width:8), ChoiceChip(label: Text('60m'), selected: _preset==60, onSelected: (_)=>_setPreset(60)),
            Spacer(),
            StreamBuilder<List<Project>>(stream: db.watchProjects(), builder: (c,snap){
              final projects = snap.data?? [];
              return SizedBox(width: 260, child: DropdownButtonFormField<String>(value: _selectedProjectId, hint: Text('Link to project'), items: projects.map((p)=>DropdownMenuItem(value:p.id, child: Text(p.name))).toList(), onChanged: (v)=>setState(()=>_selectedProjectId=v), decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))));
            }),
          ]),
          Spacer(),
          Text(_timeStr, style: TextStyle(fontSize: 96, fontWeight: FontWeight.bold, letterSpacing: 2)),
          SizedBox(height: 12), Text(_running? 'Stay focused' : 'Ready to focus?', style: Theme.of(context).textTheme.titleMedium),
          Spacer(),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(onPressed: _running? _pause : _start, icon: Icon(_running? Icons.pause : Icons.play_arrow), label: Text(_running? 'Pause' : 'Start $_preset min'), style: FilledButton.styleFrom(padding: EdgeInsets.symmetric(horizontal:32, vertical:20))),
            SizedBox(width:16), OutlinedButton(onPressed: _reset, child: Text('Reset')),
          ]),
          Spacer(),
          Divider(),
          Align(alignment: Alignment.centerLeft, child: Text('Recent sessions', style: Theme.of(context).textTheme.titleSmall)),
          SizedBox(height:8),
          SizedBox(height: 120, child: StreamBuilder<List<FocusSession>>(stream: db.watchFocusSessions(), builder: (c,snap){
            final sessions = snap.data?.take(5).toList()?? [];
            if (sessions.isEmpty) return Text('No sessions yet', style: TextStyle(color: Colors.black54));
            return ListView.builder(itemCount: sessions.length, itemBuilder: (c,i){ final s = sessions[i]; return ListTile(dense:true, title: Text('${s.durationMinutes} min - ${s.startTime.hour}:${s.startTime.minute.toString().padLeft(2,'0')}'), subtitle: Text(s.note?? '')); });
          })),
        ]),
      ),
    );
  }
}
