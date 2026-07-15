import 'dart:async';
import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import '../../../core/db/app_database.dart';
import '../../../core/services/notification_service.dart';

class FocusPage extends StatefulWidget {
  const FocusPage({super.key});
  @override State<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends State<FocusPage> {
  final db = AppDatabase();
  Timer? _timer;
  int _seconds = 25 * 60;
  bool _running = false;
  String? _selectedProjectId;

  void _start() {
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds <= 1) {
        t.cancel();
        _onComplete();
      } else {
        setState(() => _seconds--);
      }
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _seconds = 25 * 60;
      _running = false;
    });
  }

  Future<void> _onComplete() async {
    setState(() => _running = false);
    // Fixed: use Value with nullable String directly, no ternary without space
    await db.into(db.focusSessions).insert(
      FocusSessionsCompanion(
        id: drift.Value(Uuid().v4()),
        projectId: drift.Value(_selectedProjectId),
        startTime: drift.Value(DateTime.now().subtract(const Duration(minutes: 25))),
        durationMinutes: const drift.Value(25),
      ),
    );
    await NotificationService.instance.showNow(title: 'Focus Complete', body: '25 min logged');
    setState(() => _seconds = 25 * 60);
  }

  String get _timeStr {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '\$m:\$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus'), automaticallyImplyLeading: false),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            StreamBuilder(
              stream: db.watchProjects(),
              builder: (c, snap) {
                final projects = snap.data ?? [];
                return DropdownButtonFormField<String>(
                  value: _selectedProjectId,
                  hint: const Text('Link to project (optional)'),
                  items: projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => _selectedProjectId = v),
                  decoration: InputDecoration(border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                );
              },
            ),
            const Spacer(),
            Text(_timeStr, style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(onPressed: _running ? _pause : _start, icon: Icon(_running ? Icons.pause : Icons.play_arrow), label: Text(_running ? 'Pause' : 'Start 25 min')),
                const SizedBox(width: 16),
                OutlinedButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}