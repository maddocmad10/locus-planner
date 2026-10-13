import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/focus/providers/focus_timer_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('focus timer restores safely after invalid persisted state', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    await db.setSetting(
      'focus.active_session',
      jsonEncode({
        'selectedMinutes': 25,
        'remainingSeconds': 100,
        'status': 'running',
      }),
    );

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );

    try {
      await container
          .read(focusTimerProvider.notifier)
          .debugWaitForRestore();

      expect(
        container.read(focusTimerProvider).isRestoring,
        isFalse,
      );
    } finally {
      container.dispose();
      await db.close();
    }
  });
}
