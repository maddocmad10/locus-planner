import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation rail page indices — keep in sync with [_MainScaffold._pages].
abstract final class NavPage {
  static const dashboard = 0;
  static const events = 1;
  static const projects = 2;
  static const tasks = 3;
  static const habits = 4;
  static const focus = 5;
  static const diary = 6;
  static const insights = 7;
  static const settings = 8;
}

final navigationIndexProvider = StateProvider<int>((ref) => NavPage.dashboard);

final selectedCalendarDayProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final diarySelectedDateProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final focusDurationProvider = StateProvider<int>((ref) => 25);

/// Increment to trigger "New Event" dialog on Events page.
final triggerNewEventProvider = StateProvider<int>((ref) => 0);

/// Increment to trigger diary save on Diary page.
final triggerSaveDiaryProvider = StateProvider<int>((ref) => 0);

/// Increment to start focus timer on Focus page.
final triggerStartFocusProvider = StateProvider<int>((ref) => 0);
