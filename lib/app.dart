import 'package:flutter/material.dart';
import 'features/dashboard/presentation/dashboard_page.dart';
import 'features/events/presentation/events_page.dart';
import 'features/projects/presentation/projects_page.dart';
import 'features/diary/presentation/diary_page.dart';
import 'features/insights/presentation/insights_page.dart';
import 'features/habits/presentation/habits_page.dart';
import 'features/focus/presentation/focus_page.dart';

class LocusApp extends StatefulWidget {
  const LocusApp({super.key});
  @override State<LocusApp> createState() => _LocusAppState();
}

class _LocusAppState extends State<LocusApp> {
  int _index = 0;
  final _pages = const [
    DashboardPage(),
    EventsPage(),
    ProjectsPage(),
    HabitsPage(),
    FocusPage(),
    DiaryPage(),
    InsightsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Locus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0xFF6C5CE7)),
        scaffoldBackgroundColor: Color(0xFFFAFAF9),
      ),
      home: Row(children: [
        NavigationRail(
          extended: true,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          leading: Padding(padding: EdgeInsets.all(16), child: Text('Locus', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Today')),
            NavigationRailDestination(icon: Icon(Icons.event_outlined), label: Text('Events')),
            NavigationRailDestination(icon: Icon(Icons.folder_outlined), label: Text('Projects')),
            NavigationRailDestination(icon: Icon(Icons.check_circle_outlined), label: Text('Habits')),
            NavigationRailDestination(icon: Icon(Icons.timer_outlined), label: Text('Focus')),
            NavigationRailDestination(icon: Icon(Icons.book_outlined), label: Text('Diary')),
            NavigationRailDestination(icon: Icon(Icons.insights_outlined), label: Text('Insights')),
          ],
        ),
        VerticalDivider(width: 1),
        Expanded(child: _pages[_index]),
      ]),
    );
  }
}
