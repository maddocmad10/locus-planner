import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CommandAction {
  none,
  newEvent,
  newTask,
  newHabit,
  startFocus,
}

final commandActionProvider = StateProvider<CommandAction>((ref) {
  return CommandAction.none;
});