import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Navigation rail page indices — keep in sync with [_MainScaffold._pages].
abstract final class NavPage {
  static const dashboard = 0;
  static const myDay = 1;
  static const events = 2;
  static const projects = 3;
  static const tasks = 4;
  static const habits = 5;
  static const focus = 6;
  static const diary = 7;
  static const insights = 8;
  static const settings = 9;
  static const calendar = 10;
}

class NavigationIndexNotifier extends Notifier<int> {
  @override
  int build() => NavPage.dashboard;

  void setIndex(int index) => state = index;
}

final navigationIndexProvider = NotifierProvider<NavigationIndexNotifier, int>(
  NavigationIndexNotifier.new,
);
