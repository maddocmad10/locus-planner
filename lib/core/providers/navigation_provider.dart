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

class NavigationIndexNotifier extends Notifier<int> {
  @override
  int build() => NavPage.dashboard;

  void setIndex(int index) => state = index;
}

final navigationIndexProvider =
    NotifierProvider<NavigationIndexNotifier, int>(
  NavigationIndexNotifier.new,
);

class SelectedCalendarDayNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void set(DateTime value) => state = value;
}

final selectedCalendarDayProvider =
    NotifierProvider<SelectedCalendarDayNotifier, DateTime>(
  SelectedCalendarDayNotifier.new,
);

class DiarySelectedDateNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void set(DateTime value) => state = value;
}

final diarySelectedDateProvider =
    NotifierProvider<DiarySelectedDateNotifier, DateTime>(
  DiarySelectedDateNotifier.new,
);

class FocusDurationNotifier extends Notifier<int> {
  @override
  int build() => 25;

  void set(int minutes) => state = minutes.clamp(1, 240);
}

final focusDurationProvider =
    NotifierProvider<FocusDurationNotifier, int>(FocusDurationNotifier.new);
