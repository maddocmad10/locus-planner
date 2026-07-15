import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/navigation_provider.dart';

class CommandPalette extends ConsumerStatefulWidget {
  const CommandPalette({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const CommandPalette(),
    );
  }

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  static const _commands = [
    _Cmd('Go to Today', Icons.dashboard_outlined, 0),
    _Cmd('Go to Events', Icons.event_outlined, 1),
    _Cmd('Go to Projects', Icons.folder_outlined, 2),
    _Cmd('Go to Habits', Icons.check_circle_outlined, 3),
    _Cmd('Go to Focus', Icons.timer_outlined, 4),
    _Cmd('Go to Diary', Icons.book_outlined, 5),
    _Cmd('Go to Insights', Icons.insights_outlined, 6),
    _Cmd('New Event', Icons.add, -1),
    _Cmd('Start Focus', Icons.play_arrow, -2),
  ];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _run(_Cmd cmd) {
    Navigator.pop(context);
    if (cmd.index >= 0) {
      ref.read(navigationIndexProvider.notifier).state = cmd.index;
    } else if (cmd.index == -1) {
      ref.read(navigationIndexProvider.notifier).state = 1;
      ref.read(triggerNewEventProvider.notifier).state++;
    } else if (cmd.index == -2) {
      ref.read(navigationIndexProvider.notifier).state = 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _commands
        .where((c) => c.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return Shortcuts(
      shortcuts: {LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent()},
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              Navigator.pop(context);
              return null;
            },
          ),
        },
        child: AlertDialog(
          title: const Text('Command Palette'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Type a command...',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) {
                    if (filtered.isNotEmpty) _run(filtered.first);
                  },
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final cmd = filtered[i];
                      return ListTile(
                        leading: Icon(cmd.icon),
                        title: Text(cmd.label),
                        onTap: () => _run(cmd),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cmd {
  const _Cmd(this.label, this.icon, this.index);
  final String label;
  final IconData icon;
  final int index;
}

final triggerNewEventProvider = StateProvider<int>((ref) => 0);

final triggerSaveDiaryProvider = StateProvider<int>((ref) => 0);
