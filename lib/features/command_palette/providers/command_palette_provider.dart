import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../projects/data/project_mapper.dart';
import '../../../core/domain/project_model.dart';
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
  final List<ProjectModel> projects;
  final List<DiaryEntry> diaryEntries;
  final List<FocusSession> focusSessions;
}

final commandSearchProvider =
    FutureProvider.autoDispose.family<CommandSearchResults, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const CommandSearchResults();

  final ready = Completer<void>();
  final debounce = Timer(const Duration(milliseconds: 200), ready.complete);
  ref.onDispose(() {
    debounce.cancel();
    if (!ready.isCompleted) ready.complete();
  });
  await ready.future;

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
    projects: (results[3] as List<Project>).map(projectModelFromDrift).toList(growable: false),
    diaryEntries: results[4] as List<DiaryEntry>,
    focusSessions: results[5] as List<FocusSession>,
  );
});
