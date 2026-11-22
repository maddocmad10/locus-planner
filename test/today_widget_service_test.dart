import 'dart:async';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/features/mobile/data/today_widget_service.dart';

void main() {
  late AppDatabase db;
  final clock = DateTime(2026, 11, 22, 10, 30);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'e1',
            title: 'Standup',
            startTime: DateTime(2026, 11, 22, 9),
          ),
        );
    await db
        .into(db.events)
        .insert(
          EventsCompanion.insert(
            id: 'e2',
            title: 'Review',
            startTime: DateTime(2026, 11, 22, 15),
          ),
        );
    await db.addTodoItem('Due today', DateTime(2026, 11, 22, 12));
    await db.addTodoItem('Done today', DateTime(2026, 11, 22, 13));
    await db.customStatement(
      "UPDATE todo_items SET completed = 1 WHERE title = 'Done today'",
    );
    await db
        .into(db.habits)
        .insert(
          HabitsCompanion.insert(
            id: 'h1',
            name: 'Walk',
            createdAt: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  test('publishes one atomic snapshot carrying counts, day and zone', () async {
    final channel = _FakeWidgetChannel();
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: true,
    );

    await service.update();

    final publish = channel.publishes.single;
    expect(publish['title'], 'Sun 22 Nov');
    expect(publish['body'], contains('Standup'));
    expect(publish['body'], contains('Review'));
    expect(publish['eventCount'], 2);
    expect(publish['taskCount'], 1);
    expect(publish['habitCount'], 1);
    expect(publish['day'], '2026-11-22');
    expect(publish['expectedZoneToken'], 'zone-A');
    expect(publish['generation'], isA<int>());
    expect(publish['generatedAtMs'], clock.toUtc().millisecondsSinceEpoch);
    expect(channel.zoneCalls, 1);
  });

  test('retries once immediately when the native zone changed', () async {
    final channel = _FakeWidgetChannel(
      zoneTokens: ['zone-A', 'zone-B'],
      responses: [
        {'ok': false, 'reason': 'zone_changed', 'zoneToken': 'zone-B'},
        {'ok': true},
      ],
    );
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: true,
    );

    await service.update();

    expect(channel.publishes, hasLength(2));
    expect(channel.publishes[0]['expectedZoneToken'], 'zone-A');
    expect(channel.publishes[1]['expectedZoneToken'], 'zone-B');
    expect(
      channel.publishes[0]['generation'],
      channel.publishes[1]['generation'],
    );
    expect(channel.zoneCalls, 2);
  });

  test('stops after two failed attempts and leaves the error for the next '
      'normal refresh', () async {
    final channel = _FakeWidgetChannel(
      zoneTokens: ['zone-A', 'zone-B', 'zone-C', 'zone-D'],
      responses: [
        {'ok': false, 'reason': 'zone_changed'},
        {'ok': false, 'reason': 'zone_changed'},
        {'ok': true},
      ],
    );
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: true,
    );

    await service.update();
    expect(channel.publishes, hasLength(2));

    await service.update();
    expect(channel.publishes, hasLength(3));
    final firstGeneration = channel.publishes[0]['generation'] as int;
    final secondGeneration = channel.publishes[2]['generation'] as int;
    expect(secondGeneration, greaterThan(firstGeneration));
  });

  test('a commit failure is not retried within the same update', () async {
    final channel = _FakeWidgetChannel(
      responses: [
        {'ok': false, 'reason': 'commit_failed'},
        {'ok': true},
      ],
    );
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: true,
    );

    await service.update();
    expect(channel.publishes, hasLength(1));

    await service.update();
    expect(channel.publishes, hasLength(2));
  });

  test('overlapping updates coalesce into one extra publish', () async {
    final gate = Completer<Object?>();
    final channel = _FakeWidgetChannel(
      onPublish: (count) => count == 0 ? gate.future : {'ok': true},
    );
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: true,
    );

    final first = service.update();
    while (channel.publishes.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final second = service.update();
    final third = service.update();
    gate.complete(<String, Object?>{'ok': true});
    await Future.wait([first, second, third]);

    expect(channel.publishes, hasLength(2));
    final generations = channel.publishes
        .map((call) => call['generation'] as int)
        .toList();
    expect(generations[1], greaterThan(generations[0]));
  });

  test('hosts without the native widget bridge are left untouched', () async {
    final channel = _FakeWidgetChannel();
    final service = TodayWidgetService(
      db,
      invoke: channel.invoke,
      clock: () => clock,
      isAndroid: false,
    );

    await service.update();

    expect(channel.calls, isEmpty);
  });
}

class _FakeWidgetChannel {
  _FakeWidgetChannel({
    List<String>? zoneTokens,
    List<Map<String, Object?>>? responses,
    this.onPublish,
  }) : zoneTokens = zoneTokens ?? ['zone-A'],
       responses = responses ?? const [];

  final List<String> zoneTokens;
  final List<Map<String, Object?>> responses;
  final Object? Function(int count)? onPublish;
  final List<({String method, Map<String, Object?>? arguments})> calls = [];

  late int _zoneIndex = 0;

  int get zoneCalls => calls.where((call) => call.method == 'zoneToken').length;

  List<Map<String, Object?>> get publishes => [
    for (final call in calls)
      if (call.method == 'publishSnapshot') call.arguments!,
  ];

  Future<Object?> invoke(String method, Map<String, Object?>? arguments) async {
    calls.add((method: method, arguments: arguments));
    if (method == 'zoneToken') {
      final token = zoneTokens[min(_zoneIndex, zoneTokens.length - 1)];
      _zoneIndex++;
      return token;
    }
    if (method == 'publishSnapshot') {
      final index = publishes.length - 1;
      if (onPublish != null) return onPublish!(index);
      if (index < responses.length) return responses[index];
      return <String, Object?>{'ok': true};
    }
    return null;
  }
}
