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
import 'core/providers/navigation_provider.dart';
import 'core/providers/command_action_provider.dart';
import 'core/theme/app_theme.dart';

class LocusApp extends ConsumerWidget {
  const LocusApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Locus',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _MainScaffold(),
    );
  }
}

class _MainScaffold extends ConsumerStatefulWidget {
  const _MainScaffold();

  @override
  ConsumerState<_MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<_MainScaffold> {
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
        ref.read(navigationIndexProvider.notifier).setIndex(index);
      },
    );
  }

  void _goTo(int index) {
    ref.read(navigationIndexProvider.notifier).setIndex(index);
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(navigationIndexProvider);
    return CallbackShortcuts(
      bindings: {
        // Ctrl + K opens the command palette.
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openCommandPalette,
        // Ctrl + Shift + N opens the quick-add task flow.
        const SingleActivator(
          LogicalKeyboardKey.keyN,
          control: true,
          shift: true,
        ): () {
          _goTo(NavPage.tasks);
          ref.read(commandActionProvider.notifier).dispatch(CommandAction.newTask);
        },
        // Keyboard-first navigation for desktop users.
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () =>
            _goTo(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () =>
            _goTo(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () =>
            _goTo(2),
        const SingleActivator(LogicalKeyboardKey.digit4, control: true): () =>
            _goTo(3),
        const SingleActivator(LogicalKeyboardKey.digit5, control: true): () =>
            _goTo(4),
        const SingleActivator(LogicalKeyboardKey.digit6, control: true): () =>
            _goTo(5),
        const SingleActivator(LogicalKeyboardKey.digit7, control: true): () =>
            _goTo(6),
        const SingleActivator(LogicalKeyboardKey.digit8, control: true): () =>
            _goTo(7),
        const SingleActivator(LogicalKeyboardKey.digit9, control: true): () =>
            _goTo(8),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1100;
              return Row(
                children: [
                  NavigationRail(
                    extended: wide,
                    selectedIndex: index,
                    minWidth: 76,
                    minExtendedWidth: 224,
                    onDestinationSelected: (i) =>
                        ref.read(navigationIndexProvider.notifier).setIndex(i),
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                      child: SizedBox(
                        width: wide ? 200 : 52,
                        child: Column(
                          children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                'Locus',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (wide)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: _openCommandPalette,
                                icon: const Icon(Icons.search, size: 18),
                                label: const Text('Search  Ctrl+K'),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  alignment: Alignment.centerLeft,
                                ),
                              ),
                            )
                          else
                            IconButton(
                              tooltip: 'Command Palette (Ctrl+K)',
                              icon: const Icon(Icons.search),
                              onPressed: _openCommandPalette,
                            ),
                          ],
                        ),
                      ),
                    ),
                    groupAlignment: -0.72,
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
                  Expanded(
                    child: IndexedStack(
                      index: index,
                      children: _pages,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
