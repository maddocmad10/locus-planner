import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart'; // For SystemSound
import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  int _selectedMinutes = 25;
  int _remainingSeconds = 25 * 60;
  Timer? _timer;
  bool _isRunning = false;
  String? _selectedProjectId;

  final List<int> _presets = [25, 50, 90];

  void _startTimer() {
    if (_isRunning) return;

    setState(() => _isRunning = true);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        _timer?.cancel();
        _onTimerComplete();
      }
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isRunning = false);
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _selectedMinutes * 60;
    });
  }

  void _changeDuration(int minutes) {
    _timer?.cancel();
    setState(() {
      _selectedMinutes = minutes;
      _remainingSeconds = minutes * 60;
      _isRunning = false;
    });
  }

  Future<void> _onTimerComplete() async {
    setState(() => _isRunning = false);

    // Play system notification sound
    SystemSound.play(SystemSoundType.alert);

    final db = ref.read(databaseProvider);

    await db.into(db.focusSessions).insert(FocusSessionsCompanion(
      id: drift.Value(Uuid().v4()),
      projectId: drift.Value(_selectedProjectId),
      startTime: drift.Value(DateTime.now().subtract(Duration(minutes: _selectedMinutes))),
      durationMinutes: drift.Value(_selectedMinutes),
      note: const drift.Value('Completed focus session'),
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Great job! $_selectedMinutes minute focus session completed.'),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {}); // Refresh recent sessions
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  double get _progress {
    return (_remainingSeconds / (_selectedMinutes * 60)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Focus Timer'),
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Today's Focus Summary
            FutureBuilder<int>(
              future: db.focusMinutesToday(),
              builder: (context, snapshot) {
                final minutes = snapshot.data ?? 0;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.timer, size: 32),
                        const SizedBox(width: 12),
                        Text(
                          'Focus Today: $minutes minutes',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Circular Timer
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 280,
                  height: 280,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey.shade300,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                Column(
                  children: [
                    Text(
                      _formatTime(_remainingSeconds),
                      style: const TextStyle(fontSize: 72, fontWeight: FontWeight.w300),
                    ),
                    Text(
                      '$_selectedMinutes min session',
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Duration Presets
            Wrap(
              spacing: 12,
              children: _presets.map((minutes) {
                return ChoiceChip(
                  label: Text('$minutes min'),
                  selected: _selectedMinutes == minutes,
                  onSelected: (_) => _changeDuration(minutes),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Project Selection
            StreamBuilder<List<Project>>(
              stream: db.watchProjects(),
              builder: (context, snapshot) {
                final projects = snapshot.data ?? [];
                return SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedProjectId,
                    decoration: const InputDecoration(
                      labelText: 'Link to Project (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No project'),
                      ),
                      ...projects.map((project) => DropdownMenuItem<String?>(
                            value: project.id,
                            child: Text(project.name),
                          )),
                    ],
                    onChanged: (value) {
                      setState(() => _selectedProjectId = value);
                    },
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Control Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!_isRunning)
                  FilledButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Focus'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  )
                else
                  FilledButton.icon(
                    onPressed: _pauseTimer,
                    icon: const Icon(Icons.pause),
                    label: const Text('Pause'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    ),
                  ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: _resetTimer,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // Recent Focus Sessions
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Recent Focus Sessions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 12),

            StreamBuilder<List<FocusSession>>(
              stream: db.watchFocusSessions(),
              builder: (context, snapshot) {
                final sessions = snapshot.data ?? [];

                if (sessions.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No focus sessions yet. Complete your first session!'),
                    ),
                  );
                }

                return Column(
                  children: sessions.take(5).map((session) {
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: Text('${session.durationMinutes} minutes'),
                        subtitle: Text(
                          '${session.startTime.day}/${session.startTime.month} • ${session.startTime.hour}:${session.startTime.minute.toString().padLeft(2, '0')}',
                        ),
                        trailing: session.projectId != null
                            ? const Chip(label: Text('Linked to Project'))
                            : null,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}