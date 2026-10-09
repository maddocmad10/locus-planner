import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CommandAction { none, newEvent, newTask, newHabit, startFocus }

class CommandActionNotifier extends Notifier<CommandAction> {
  @override
  CommandAction build() => CommandAction.none;

  void dispatch(CommandAction action) => state = action;

  void clear() => state = CommandAction.none;
}

final commandActionProvider =
    NotifierProvider<CommandActionNotifier, CommandAction>(
      CommandActionNotifier.new,
    );
