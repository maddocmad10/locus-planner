import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../services/error_log_service.dart';
import 'database_provider.dart';
import 'navigation_provider.dart';

/// Pages the user may choose as the startup destination. The stored value is
/// stable, so it must not depend on enum declaration order or display labels.
enum LandingPage {
  dashboard('dashboard', 'Today', NavPage.dashboard),
  myDay('my_day', 'My Day', NavPage.myDay),
  events('events', 'Events', NavPage.events),
  projects('projects', 'Projects', NavPage.projects),
  tasks('tasks', 'To-do', NavPage.tasks),
  habits('habits', 'Habits', NavPage.habits),
  focus('focus', 'Focus', NavPage.focus),
  diary('diary', 'Diary', NavPage.diary),
  insights('insights', 'Insights', NavPage.insights);

  const LandingPage(this.storageValue, this.label, this.navigationIndex);

  final String storageValue;
  final String label;
  final int navigationIndex;

  static LandingPage fromStorage(String? value) => values.firstWhere(
    (page) => page.storageValue == value,
    orElse: () => LandingPage.dashboard,
  );
}

class LandingPageNotifier extends AsyncNotifier<LandingPage> {
  @override
  Future<LandingPage> build() async {
    final db = ref.watch(databaseProvider);
    final stored = await db.getSetting(
      AppDatabase.defaultLandingPageSettingKey,
    );
    return LandingPage.fromStorage(stored);
  }

  Future<void> setPage(LandingPage page) async {
    final previous = state;
    state = AsyncData(page);
    try {
      await ref
          .read(databaseProvider)
          .setSetting(
            AppDatabase.defaultLandingPageSettingKey,
            page.storageValue,
          );
    } catch (error, stack) {
      state = previous;
      await ErrorLogService.log(error, stack);
      rethrow;
    }
  }
}

final landingPageProvider =
    AsyncNotifierProvider<LandingPageNotifier, LandingPage>(
      LandingPageNotifier.new,
    );
