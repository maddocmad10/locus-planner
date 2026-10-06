import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

class CommandSearchResults {
  const CommandSearchResults({
    this.events = const [],
    this.tasks = const [],
    this.habits = const [],
    this.projects = const [],
    this.diaryEntries = const [],
    this.focusSessions = const [],
  });

  final List<Event> events;
  final List<TodoItem> tasks;
  final List<Habit> habits;
  final List<Project> projects;
  final List<DiaryEntry> diaryEntries;
  final List<FocusSession> focusSessions;
}

final commandSearchProvider =
    FutureProvider.family<CommandSearchResults, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const CommandSearchResults();

  final db = ref.watch(databaseProvider);
  final results = await Future.wait([
    db.searchEvents(q),
    db.searchTodoItems(q),
    db.searchHabits(q),
    db.searchProjects(q),
    db.searchDiaryEntries(q),
    db.searchFocusSessions(q),
  ]);

  return CommandSearchResults(
    events: results[0] as List<Event>,
    tasks: results[1] as List<TodoItem>,
    habits: results[2] as List<Habit>,
    projects: results[3] as List<Project>,
    diaryEntries: results[4] as List<DiaryEntry>,
    focusSessions: results[5] as List<FocusSession>,
  );
});
