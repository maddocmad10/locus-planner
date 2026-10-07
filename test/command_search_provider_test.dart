import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/providers/database_provider.dart';
import 'package:locus_planner/features/command_palette/providers/command_palette_provider.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('returns matches once the debounce has passed', () async {
    await db.into(db.todoItems).insert(
      TodoItemsCompanion.insert(
        id: 't1',
        title: 'Buy milk',
        createdAt: DateTime(2026, 1, 1),
      ),
    );

    final sub = container.listen(commandSearchProvider('milk'), (_, _) {});
    final results = await container.read(commandSearchProvider('milk').future);

    expect(results.tasks.single.title, 'Buy milk');
    sub.close();
  });

  test('an empty query returns nothing', () async {
    final sub = container.listen(commandSearchProvider('   '), (_, _) {});
    final results = await container.read(commandSearchProvider('   ').future);

    expect(results.tasks, isEmpty);
    expect(results.events, isEmpty);
    sub.close();
  });

  test('abandoning a query while it waits raises no errors', () async {
    final errors = <Object>[];

    await runZonedGuarded(() async {
      // Typing quickly: each keystroke drops the previous query before its
      // debounce has finished.
      for (final q in ['m', 'mi', 'mil', 'milk']) {
        container.listen(commandSearchProvider(q), (_, _) {}).close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }, (error, stack) => errors.add(error));

    expect(errors, isEmpty);
  });
}
