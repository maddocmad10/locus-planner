import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/domain/project_model.dart';
import '../../../core/providers/database_provider.dart';
import '../../projects/data/project_mapper.dart';

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

final commandSearchProvider = FutureProvider.autoDispose
    .family<CommandSearchResults, String>((ref, query) async {
      final q = query.trim();
      if (q.isEmpty) return const CommandSearchResults();

      var disposed = false;
      final ready = Completer<void>();
      final debounce = Timer(const Duration(milliseconds: 200), ready.complete);
      ref.onDispose(() {
        disposed = true;
        debounce.cancel();
        if (!ready.isCompleted) ready.complete();
      });
      await ready.future;
      // Typing on disposed this query while it waited; its ref is no longer usable.
      if (disposed) return const CommandSearchResults();

      final db = ref.watch(databaseProvider);
      final results = await Future.wait([
        db.searchEvents(q),
        db.searchTodoItems(q),
        db.searchHabits(q),
        db.searchProjects(q),
        db.searchDiaryEntries(q),
        db.searchFocusSessions(q),
        db.searchAttachments(q),
      ]);
      final events = List<Event>.from(results[0] as List<Event>);
      final tasks = List<TodoItem>.from(results[1] as List<TodoItem>);
      final attachmentMatches = results[6] as List<Attachment>;

      // A task or event is also a result when its attachment name matches.
      final knownEvents = {for (final event in events) event.id};
      final knownTasks = {for (final task in tasks) task.id};
      final eventIds = {
        for (final attachment in attachmentMatches)
          if (attachment.eventId != null &&
              !knownEvents.contains(attachment.eventId))
            attachment.eventId!,
      };
      final todoIds = {
        for (final attachment in attachmentMatches)
          if (attachment.todoId != null &&
              !knownTasks.contains(attachment.todoId))
            attachment.todoId!,
      };
      if (eventIds.isNotEmpty) {
        events.addAll(await db.eventsByIds(eventIds));
      }
      if (todoIds.isNotEmpty) {
        tasks.addAll(await db.todoItemsByIds(todoIds));
      }

      return CommandSearchResults(
        events: events,
        tasks: tasks,
        habits: results[2] as List<Habit>,
        projects: (results[3] as List<Project>)
            .map(projectModelFromDrift)
            .toList(growable: false),
        diaryEntries: results[4] as List<DiaryEntry>,
        focusSessions: results[5] as List<FocusSession>,
      );
    });
