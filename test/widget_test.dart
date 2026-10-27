import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/mobile/data/mobile_sync_client.dart';
import 'package:locus_planner/features/mobile/mobile_app.dart';

class _FakeMobileSyncClient extends MobileSyncClient {
  _FakeMobileSyncClient(super.db);

  @override
  Future<MobileSyncStatus> status() async =>
      const MobileSyncStatus(paired: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Initialize the in-memory database before the widget subscribes to streams.
    await db.customSelect('SELECT 1').get();
  });

  testWidgets('mobile app renders its shell and navigation', (tester) async {
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            mobileSyncClientProvider.overrideWith(
              (ref) => _FakeMobileSyncClient(db),
            ),
          ],
          child: const LocusMobileApp(),
        ),
      );

      // Avoid pumpAndSettle: Material widgets can keep scheduling frames while
      // an async stream is loading (e.g. an indeterminate progress indicator).
      // A bounded pump lets the database-backed providers emit their first data.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Locus'), findsOneWidget);
      expect(find.text('Today'), findsWidgets);
      expect(find.text('Tasks'), findsWidgets);
      expect(find.text('Diary'), findsWidgets);
      expect(find.text('Sync'), findsWidgets);
    } finally {
      // Dispose Riverpod stream subscriptions while the test can still pump
      // Drift's zero-duration close timers, then close the backing database.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await db.close();
    }
  });
}
