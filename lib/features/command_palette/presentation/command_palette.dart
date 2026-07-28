import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/command_action_provider.dart';

class CommandPalette extends ConsumerStatefulWidget {
  final Function(int) onNavigate;

  const CommandPalette({
    super.key,
    required this.onNavigate,
  });

  @override
  ConsumerState<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<CommandPalette> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = '';
  int _selectedIndex = 0;

  late final List<_CommandItem> _allCommands;

  @override
  void initState() {
    super.initState();

    _allCommands = [
      // ========== NAVIGATION ==========
      _CommandItem(
        title: 'Go to Today',
        subtitle: 'Dashboard overview',
        icon: Icons.dashboard_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(0),
      ),
      _CommandItem(
        title: 'Go to Events',
        subtitle: 'Calendar & reminders',
        icon: Icons.event_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(1),
      ),
      _CommandItem(
        title: 'Go to Projects',
        subtitle: 'Projects & progress tracking',
        icon: Icons.folder_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(2),
      ),
      _CommandItem(
        title: 'Go to Tasks',
        subtitle: 'Global to-do list',
        icon: Icons.checklist_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(3),
      ),
      _CommandItem(
        title: 'Go to Habits',
        subtitle: 'Daily habits & heatmap',
        icon: Icons.check_circle_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(4),
      ),
      _CommandItem(
        title: 'Go to Focus',
        subtitle: 'Focus timer',
        icon: Icons.timer_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(5),
      ),
      _CommandItem(
        title: 'Go to Diary',
        subtitle: 'Daily journal',
        icon: Icons.book_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(6),
      ),
      _CommandItem(
        title: 'Go to Insights',
        subtitle: 'Charts & statistics',
        icon: Icons.insights_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(7),
      ),
      _CommandItem(
        title: 'Go to Settings',
        subtitle: 'Theme, export & import',
        icon: Icons.settings_outlined,
        category: 'Navigation',
        action: () => widget.onNavigate(8),
      ),

      // ========== ACTIONS ==========
      _CommandItem(
        title: 'New Event',
        subtitle: 'Create a new calendar event',
        icon: Icons.event,
        category: 'Actions',
        action: () {
          widget.onNavigate(1);
          ref.read(commandActionProvider.notifier).state = CommandAction.newEvent;
        },
      ),
      _CommandItem(
        title: 'New Task',
        subtitle: 'Add a new to-do item',
        icon: Icons.add_task,
        category: 'Actions',
        action: () {
          widget.onNavigate(3);
          ref.read(commandActionProvider.notifier).state = CommandAction.newTask;
        },
      ),
      _CommandItem(
        title: 'New Habit',
        subtitle: 'Create a new habit',
        icon: Icons.add_circle_outline,
        category: 'Actions',
        action: () {
          widget.onNavigate(4);
          ref.read(commandActionProvider.notifier).state = CommandAction.newHabit;
        },
      ),
      _CommandItem(
        title: 'Start Focus Session',
        subtitle: 'Begin a focus / pomodoro timer',
        icon: Icons.play_arrow_rounded,
        category: 'Actions',
        action: () {
          widget.onNavigate(5);
          ref.read(commandActionProvider.notifier).state = CommandAction.startFocus;
        },
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_CommandItem> get _filtered {
    if (_query.trim().isEmpty) return _allCommands;
    final q = _query.toLowerCase();
    return _allCommands.where((c) {
      return c.title.toLowerCase().contains(q) ||
          (c.subtitle?.toLowerCase().contains(q) ?? false) ||
          c.category.toLowerCase().contains(q);
    }).toList();
  }

  void _runSelected() {
    final items = _filtered;
    if (items.isEmpty) return;
    final index = _selectedIndex.clamp(0, items.length - 1);
    items[index].action();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    // Keep selected index in bounds
    if (_selectedIndex >= items.length) {
      _selectedIndex = items.isEmpty ? 0 : items.length - 1;
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchController,
                focusNode: _focusNode,
                decoration: InputDecoration(
                  hintText: 'Search commands...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                ),
                onChanged: (v) {
                  setState(() {
                    _query = v;
                    _selectedIndex = 0;
                  });
                },
                onSubmitted: (_) => _runSelected(),
              ),
            ),

            const Divider(height: 1),

            // Results with keyboard support
            Flexible(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(40),
                      child: Text('No matching commands'),
                    )
                  : KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent) {
                          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                            setState(() {
                              _selectedIndex = (_selectedIndex + 1).clamp(0, items.length - 1);
                            });
                          } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                            setState(() {
                              _selectedIndex = (_selectedIndex - 1).clamp(0, items.length - 1);
                            });
                          } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                            _runSelected();
                          }
                        }
                      },
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final cmd = items[index];
                          final isSelected = index == _selectedIndex;

                          return Material(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                                : Colors.transparent,
                            child: ListTile(
                              leading: Icon(
                                cmd.icon,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                              ),
                              title: Text(
                                cmd.title,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                ),
                              ),
                              subtitle: cmd.subtitle != null ? Text(cmd.subtitle!) : null,
                              trailing: Text(
                                cmd.category,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              onTap: () {
                                cmd.action();
                                Navigator.pop(context);
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),

            // Footer
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Text(
                '↑↓ Navigate  •  Enter Select  •  Esc Close',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String category;
  final VoidCallback action;

  _CommandItem({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.category,
    required this.action,
  });
}

Future<void> showCommandPalette(
  BuildContext context, {
  required Function(int) onNavigate,
}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => CommandPalette(onNavigate: onNavigate),
  );
}