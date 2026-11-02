import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locus_planner/core/db/app_database.dart';
import 'package:locus_planner/core/services/sync_change_applier.dart';

void main() {
  late AppDatabase desktop;
  late AppDatabase phone;

  setUp(() async {
    desktop = AppDatabase.forTesting(NativeDatabase.memory());
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    await desktop.ensureDeviceIdentity();
    await phone.ensureDeviceIdentity();
  });

  tearDown(() async {
    await desktop.close();
    await phone.close();
  });

  Future<void> insertTodo(AppDatabase db, String id) => db.customStatement(
    'INSERT INTO todo_items (id, title, completed, created_at) '
    'VALUES (?, ?, 0, 1760000000)',
    [id, 'Task $id'],
  );

  Future<void> insertPlan(
    AppDatabase db, {
    required String id,
    required String dayKey,
    String? intention,
  }) => db.customStatement(
    'INSERT INTO daily_plans (id, day_key, intention, created_at, updated_at) '
    'VALUES (?, ?, ?, 1760000000, 1760000000)',
    [id, dayKey, intention],
  );

  Future<void> insertPlanItem(
    AppDatabase db, {
    required String id,
    required String planId,
    required String todoId,
    int sortOrder = 0,
    int? plannedMinutes,
  }) => db.customStatement(
    'INSERT INTO daily_plan_items (id, plan_id, todo_item_id, '
    'project_task_id, sort_order, planned_minutes, created_at, updated_at) '
    'VALUES (?, ?, ?, NULL, ?, ?, 1760000000, 1760000000)',
    [id, planId, todoId, sortOrder, plannedMinutes],
  );

  Future<int> versionOf(AppDatabase db, String type, String id) async {
    final rows = await db
        .customSelect(
          'SELECT updated_at FROM sync_row_versions '
          'WHERE entity_type = ? AND entity_id = ?',
          variables: [Variable.withString(type), Variable.withString(id)],
        )
        .get();
    return rows.isEmpty ? 0 : rows.first.read<int>('updated_at');
  }

  Map<String, dynamic> planChange({
    required String id,
    required String dayKey,
    required int version,
    String intention = 'Remote',
    String device = 'remote-device',
  }) => {
    'entityType': 'daily_plan',
    'entityId': id,
    'operation': 'upsert',
    'payload': {
      'id': id,
      'day_key': dayKey,
      'intention': intention,
      'created_at': 1760000000,
      'updated_at': 1760000000,
      'sync_updated_at': version,
    },
    'deviceId': device,
  };

  test(
    'snapshot orders daily plans before their items and syncs them',
    () async {
      await insertTodo(desktop, 'todo-1');
      await insertPlan(
        desktop,
        id: 'plan-1',
        dayKey: '2026-05-20',
        intention: 'Focus',
      );
      await insertPlanItem(
        desktop,
        id: 'item-1',
        planId: 'plan-1',
        todoId: 'todo-1',
        plannedMinutes: 30,
      );

      final state = await SyncChangeApplier.readFullState(desktop);
      final planIndex = state.indexWhere(
        (change) => change['entityType'] == 'daily_plan',
      );
      final itemIndex = state.indexWhere(
        (change) => change['entityType'] == 'daily_plan_item',
      );
      expect(planIndex, greaterThanOrEqualTo(0));
      expect(itemIndex, greaterThan(planIndex));
      expect(
        SyncChangeApplier.snapshotTypeRank('daily_plan'),
        lessThan(SyncChangeApplier.snapshotTypeRank('daily_plan_item')),
      );

      final planPayload =
          state.firstWhere(
                (change) => change['entityId'] == 'plan-1',
              )['payload']
              as Map<String, dynamic>;
      expect(planPayload['sync_updated_at'], greaterThan(0));
      expect(planPayload['updated_at'], 1760000000);

      final result = await SyncChangeApplier(phone).apply(state);
      expect(result.rejected, isEmpty);
      final plans = await phone.select(phone.dailyPlans).get();
      final items = await phone.select(phone.dailyPlanItems).get();
      expect(plans.single.id, 'plan-1');
      expect(plans.single.intention, 'Focus');
      expect(items.single.id, 'item-1');
      expect(items.single.todoItemId, 'todo-1');
      expect(items.single.plannedMinutes, 30);
    },
  );

  test('deleting a plan removes its items on the other device', () async {
    await insertTodo(desktop, 'todo-1');
    await insertPlan(desktop, id: 'plan-1', dayKey: '2026-05-20');
    await insertPlanItem(
      desktop,
      id: 'item-1',
      planId: 'plan-1',
      todoId: 'todo-1',
    );
    await SyncChangeApplier(
      phone,
    ).apply(await SyncChangeApplier.readFullState(desktop));

    await desktop.customStatement(
      "DELETE FROM daily_plans WHERE id = 'plan-1'",
    );
    final state = await SyncChangeApplier.readFullState(desktop);
    final tombstones = state
        .where((change) => change['operation'] == 'delete')
        .map((change) => change['entityType'])
        .toSet();
    expect(tombstones, containsAll(['daily_plan', 'daily_plan_item']));

    await SyncChangeApplier(phone).apply(state);
    expect(await phone.select(phone.dailyPlans).get(), isEmpty);
    expect(await phone.select(phone.dailyPlanItems).get(), isEmpty);
  });

  Map<String, dynamic> planItemChange({
    required String id,
    required String planId,
    required String todoId,
    required int version,
    int sortOrder = 0,
    String device = 'remote-device',
  }) => {
    'entityType': 'daily_plan_item',
    'entityId': id,
    'operation': 'upsert',
    'payload': {
      'id': id,
      'plan_id': planId,
      'todo_item_id': todoId,
      'project_task_id': null,
      'sort_order': sortOrder,
      'planned_minutes': null,
      'created_at': 1760000000,
      'updated_at': 1760000000,
      'sync_updated_at': version,
    },
    'deviceId': device,
  };

  test('the newer plan wins when two devices created the same day', () async {
    await insertTodo(phone, 'todo-local');
    await insertTodo(phone, 'todo-remote');
    await insertPlan(
      phone,
      id: 'plan-local',
      dayKey: '2026-05-20',
      intention: 'Local',
    );
    await insertPlanItem(
      phone,
      id: 'item-local',
      planId: 'plan-local',
      todoId: 'todo-local',
    );
    final localVersion = await versionOf(phone, 'daily_plan', 'plan-local');

    final stale = await SyncChangeApplier(phone).apply([
      planChange(
        id: 'plan-remote',
        dayKey: '2026-05-20',
        version: localVersion - 1000,
      ),
    ]);
    expect(stale.applied, 0);
    expect(stale.skipped, 1);
    expect(
      (await phone.select(phone.dailyPlans).get()).single.id,
      'plan-local',
    );
    expect(
      (await phone.select(phone.dailyPlanItems).get()).single.id,
      'item-local',
    );

    final remoteVersion = localVersion + 1000;
    final newer = await SyncChangeApplier(phone).apply([
      planChange(
        id: 'plan-remote',
        dayKey: '2026-05-20',
        version: remoteVersion,
      ),
      planItemChange(
        id: 'item-remote',
        planId: 'plan-remote',
        todoId: 'todo-remote',
        version: remoteVersion + 1,
        sortOrder: 1,
      ),
    ]);
    expect(newer.rejected, isEmpty);
    expect(newer.applied, 2);
    final plans = await phone.select(phone.dailyPlans).get();
    expect(plans.single.id, 'plan-remote');
    expect(plans.single.intention, 'Remote');
    // The losing plan's task is re-parented instead of cascaded away.
    final items = await phone.select(phone.dailyPlanItems).get();
    expect(items, hasLength(2));
    expect(items.map((item) => item.planId).toSet(), {'plan-remote'});
    expect(items.map((item) => item.todoItemId).toSet(), {
      'todo-local',
      'todo-remote',
    });
  });

  test(
    'the outbox carries the sync version without losing updated_at',
    () async {
      await insertPlan(
        desktop,
        id: 'plan-1',
        dayKey: '2026-05-20',
        intention: 'Focus',
      );

      final rows = await desktop
          .customSelect(
            "SELECT payload FROM sync_outbox WHERE entity_type = 'daily_plan'",
          )
          .get();
      expect(rows, hasLength(1));
      final payload =
          jsonDecode(rows.single.read<String>('payload'))
              as Map<String, dynamic>;
      expect(payload['id'], 'plan-1');
      expect(payload['updated_at'], 1760000000);
      expect(payload['sync_updated_at'], greaterThan(0));
    },
  );

  test('plan items for a missing task are skipped, not rejected', () async {
    final result = await SyncChangeApplier(phone).apply([
      {
        'entityType': 'daily_plan_item',
        'entityId': 'item-1',
        'operation': 'upsert',
        'payload': {
          'id': 'item-1',
          'plan_id': 'missing-plan',
          'todo_item_id': 'missing-todo',
          'project_task_id': null,
          'sort_order': 0,
          'planned_minutes': null,
          'created_at': 1760000000,
          'updated_at': 1760000000,
          'sync_updated_at': 5000,
        },
        'deviceId': 'remote-device',
      },
    ]);

    expect(result.rejected, isEmpty);
    expect(result.skipped, 1);
    expect(await phone.select(phone.dailyPlanItems).get(), isEmpty);
  });
}
