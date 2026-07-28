import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/events/presentation/events_page.dart';
import 'features/projects/presentation/projects_page.dart';
import 'features/tasks/presentation/tasks_page.dart';
import 'features/habits/presentation/habits_page.dart';
import 'features/focus/presentation/focus_page.dart';
import 'features/diary/presentation/diary_page.dart';
import 'features/insights/presentation/insights_page.dart';
import 'features/settings/presentation/settings_page.dart';
import 'features/command_palette/presentation/command_palette.dart';
import 'core/providers/theme_provider.dart';

class LocusApp extends ConsumerWidget {
  const LocusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Locus',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C5CE7)),
        scaffoldBackgroundColor: const Color(0xFFFAFAF9),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C5CE7),
          brightness: Brightness.dark,
        ),
      ),
      home: const _MainScaffold(),
    );
  }
}

class _MainScaffold extends ConsumerStatefulWidget {
  const _MainScaffold({super.key});

  @override
  ConsumerState<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<_MainScaffold> {
  int _index = 0;

  final _pages = const [
    DashboardPage(),
    EventsPage(),
    ProjectsPage(),
    TasksPage(),
    HabitsPage(),
    FocusPage(),
    DiaryPage(),
    InsightsPage(),
    SettingsPage(),
  ];

  void _openCommandPalette() {
  showCommandPalette(
    context,
    onNavigate: (index) {
      setState(() => _index = index);
    },
  );
}
    

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        // Ctrl + K opens the command palette
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openCommandPalette,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: true,
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                leading: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'Locus',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      // Quick access button for Command Palette
                      IconButton(
                        tooltip: 'Command Palette (Ctrl+K)',
                        icon: const Icon(Icons.search),
                        onPressed: _openCommandPalette,
                      ),
                    ],
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    label: Text('Today'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.event_outlined),
                    label: Text('Events'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.folder_outlined),
                    label: Text('Projects'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.checklist_outlined),
                    label: Text('Tasks'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.check_circle_outlined),
                    label: Text('Habits'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.timer_outlined),
                    label: Text('Focus'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.book_outlined),
                    label: Text('Diary'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.insights_outlined),
                    label: Text('Insights'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings_outlined),
                    label: Text('Settings'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _pages[_index]),
            ],
          ),
        ),
      ),
    );
  }
}