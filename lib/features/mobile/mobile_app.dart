import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/providers/database_provider.dart';
import '../../core/providers/item_navigation_provider.dart';
import '../../core/providers/service_providers.dart';
import '../../core/services/natural_language_quick_add.dart';
import '../../core/services/sync_receipt_store.dart';
import '../../core/services/snapshot_reconciliation_service.dart';
import '../../core/services/sync_tls.dart';
import '../../core/utils/app_clock.dart';
import '../../core/utils/day_math.dart';
import '../../core/utils/md1_plain.dart';
import '../../core/utils/recurrence.dart';
import '../../core/widgets/attachment_strip.dart';
import '../../core/widgets/dispose_with.dart';
import '../../core/widgets/notes_field.dart';
import '../../core/widgets/quick_add_preview.dart';
import '../../core/widgets/user_action_error.dart';
import '../app_lock/presentation/app_lock_gate.dart';
import '../app_lock/presentation/app_lock_settings_card.dart';
import '../app_lock/providers/app_lock_controller.dart';
import '../diary/data/diary_repository.dart';
import '../events/data/event_repository.dart';
import '../habits/data/habit_repository.dart';
import '../my_day/data/my_day_models.dart';
import '../my_day/providers/my_day_providers.dart';
import '../tasks/data/task_metadata.dart';
import '../tasks/data/task_repository.dart';
import 'data/mobile_reminder_service.dart';
import 'data/mobile_sync_client.dart';
import 'data/mobile_sync_status.dart';
import 'data/reminder_platform.dart';
import 'data/share_intake_service.dart';
import 'data/today_agenda.dart';
import 'data/today_widget_service.dart';
import 'pair_scanner_page.dart';

part 'presentation/mobile_today_tab.dart';
part 'presentation/mobile_task_picker_sheet.dart';
part 'presentation/mobile_event_dialog.dart';
part 'presentation/mobile_tasks_screen.dart';
part 'presentation/mobile_task_dialog.dart';
part 'presentation/mobile_diary_screen.dart';
part 'presentation/mobile_sync_screen.dart';
part 'presentation/mobile_reminders_card.dart';
part 'presentation/mobile_quick_capture_sheet.dart';
part 'presentation/mobile_habits_tab.dart';
part 'presentation/mobile_search_page.dart';
part 'presentation/mobile_sync_status_card.dart';
part 'presentation/mobile_reconciliation_dialog.dart';

final _mobileEventsProvider = StreamProvider<List<Event>>((ref) {
  return ref.watch(databaseProvider).watchAllEvents();
});
final _mobileDiaryProvider = StreamProvider<List<DiaryEntry>>((ref) {
  return ref.watch(diaryRepositoryProvider).watchAll();
});

/// The day shown by the phone's Today tab. Null follows the real today so the
/// screen moves on after midnight.
final agendaDayProvider = StateProvider<DateTime?>((ref) => null);

/// Number of My Day items per day in the next 14 days, used by the Upcoming
/// list. The key is the `YYYY-MM-DD` plan key.
final mobileUpcomingPlanDaysProvider = FutureProvider.autoDispose
    .family<Map<String, int>, DateTime>((ref, from) async {
      final db = ref.watch(databaseProvider);
      final to = DayMath.addDays(from, 13);
      final rows = await db
          .customSelect(
            'SELECT p.day_key, COUNT(i.id) AS item_count '
            'FROM daily_plans p '
            'LEFT JOIN daily_plan_items i ON i.plan_id = p.id '
            'WHERE p.day_key >= ? AND p.day_key <= ? '
            'GROUP BY p.day_key',
            variables: [
              Variable.withString(myDayKey(from)),
              Variable.withString(myDayKey(to)),
            ],
          )
          .get();
      return {
        for (final row in rows)
          row.read<String>('day_key'): row.read<int>('item_count'),
      };
    });

/// Habit logs per day in the next 14 days, so the Upcoming list also shows a
/// day whose only entry is a habit tick.
final mobileUpcomingHabitDaysProvider = FutureProvider.autoDispose
    .family<Map<String, int>, DateTime>((ref, from) async {
      final db = ref.watch(databaseProvider);
      final to = DayMath.addDays(from, 14);
      final rows = await db
          .customSelect(
            'SELECT date, COUNT(*) AS habit_count '
            'FROM habit_logs WHERE date >= ? AND date < ? '
            'AND completed = 1 GROUP BY date',
            variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
          )
          .get();
      return {
        for (final row in rows)
          myDayKey(
            DateTime.fromMillisecondsSinceEpoch(row.read<int>('date') * 1000),
          ): row.read<int>(
            'habit_count',
          ),
      };
    });

class LocusMobileApp extends StatelessWidget {
  const LocusMobileApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Locus Planner',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5269A8)),
      useMaterial3: true,
    ),
    home: const _MobileHome(),
    builder: (context, child) =>
        AppLockGate(child: child ?? const SizedBox.shrink()),
  );
}

class _MobileHome extends ConsumerStatefulWidget {
  const _MobileHome();

  @override
  ConsumerState<_MobileHome> createState() => _MobileHomeState();
}

class _MobileHomeState extends ConsumerState<_MobileHome>
    with WidgetsBindingObserver {
  /// A phone that is not on the home network, or a desktop that is switched
  /// off, would otherwise be retried (and wait for a timeout) every time the
  /// app is opened.
  static const _autoSyncInterval = Duration(minutes: 1);

  int _index = 0;
  bool _syncing = false;
  DateTime? _lastAutoAttempt;
  late final MobileReminderService _reminders;
  StreamSubscription<String>? _tabSubscription;
  StreamSubscription<ItemTarget>? _targetSubscription;
  StreamSubscription<List<ShareIntake>>? _shareSubscription;
  Timer? _widgetUpdateTimer;
  ItemTarget? _pendingTarget;
  final Set<String> _activeShareIntakes = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Event reminders follow the events table, so they also pick up rows that
    // a sync brings in.
    _reminders = ref.read(mobileReminderServiceProvider)..start();
    _tabSubscription = ref.read(reminderPlatformProvider).requestedTabs.listen((
      tab,
    ) {
      if (tab == 'tasks' && mounted) setState(() => _index = 1);
      if (tab == 'quick_capture' && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_quickCapture());
        });
      }
    });
    _targetSubscription = ref
        .read(reminderPlatformProvider)
        .requestedTargets
        .listen(_activateTarget);
    _shareSubscription = ref
        .read(shareIntakeServiceProvider)
        .pendingIntakes
        // Drain the native queue instead of trusting only the event payload,
        // so a share delivered while the app was running is not imported a
        // second time by the next resume.
        .listen((_) => unawaited(_importSharedFiles()));
    // Opening the app is the moment the user expects to see current data.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      unawaited(_autoSync());
      unawaited(ref.read(todayWidgetServiceProvider).update());
      final tab = await ref.read(reminderPlatformProvider).launchTab();
      if (tab == 'tasks' && mounted) setState(() => _index = 1);
      if (tab == 'quick_capture' && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_quickCapture());
        });
      }
      final target = await ref.read(reminderPlatformProvider).launchTarget();
      if (target != null) _activateTarget(target);
      unawaited(_importSharedFiles());
    });
  }

  /// Routes a typed target through app-lock handling. The page that owns the
  /// kind consumes the request and opens its editor.
  void _activateTarget(ItemTarget target) {
    final lock = ref.read(appLockControllerProvider).valueOrNull;
    if (lock == null || lock.locked) {
      _pendingTarget = target;
      return;
    }
    if (!mounted) return;
    setState(() => _index = target.kind == ItemKind.task ? 1 : 0);
    ref.read(itemOpenRequestProvider.notifier).publish(target);
  }

  Future<void> _importSharedFiles() async {
    final service = ref.read(shareIntakeServiceProvider);
    final intakes = await service.takeIntakes();
    if (intakes.isEmpty || !mounted) return;
    final db = ref.read(databaseProvider);
    final attachmentService = await ref.read(attachmentServiceProvider.future);
    var tasks = 0;
    var attachments = 0;
    final failures = <String>[];
    for (final intake in intakes) {
      if (intake.isEmpty) {
        await service.complete(intake.id);
        continue;
      }
      if (!_activeShareIntakes.add(intake.id)) continue;
      final now = AppClock.now().millisecondsSinceEpoch;
      await db.customStatement(
        'INSERT OR IGNORE INTO share_intake_state '
        '(intake_id, status, claimed_at, created_at, updated_at) '
        "VALUES (?, 'pending', NULL, ?, ?)",
        [intake.id, now, now],
      );
      await db.customStatement(
        'UPDATE share_intake_state SET status = ?, claimed_at = ?, '
        'updated_at = ? WHERE intake_id = ?',
        ['importing', now, now, intake.id],
      );

      var existing = await db.getTodoItem(intake.id);
      if (existing == null) {
        try {
          final notes = intake.text.trim();
          await ref
              .read(taskRepositoryProvider)
              .add(
                id: intake.id,
                title: intake.title,
                notes: notes.isEmpty ? null : notes,
              );
          existing = await db.getTodoItem(intake.id);
        } catch (error) {
          await _markShareState(db, intake.id, 'failed');
          failures.add('${intake.title}: $error');
          _activeShareIntakes.remove(intake.id);
          continue;
        }
      }
      if (existing == null) {
        await _markShareState(db, intake.id, 'failed');
        failures.add('${intake.title}: the task was not created');
        _activeShareIntakes.remove(intake.id);
        continue;
      }
      try {
        var imported = 0;
        for (final file in intake.files) {
          final attachmentId =
              file.attachmentId ?? '${intake.id}-${file.ordinal}';
          final existingAttachment = await db
              .customSelect(
                'SELECT sha256 FROM attachments WHERE id = ?',
                variables: [Variable.withString(attachmentId)],
              )
              .getSingleOrNull();
          if (existingAttachment != null &&
              await attachmentService.hasBlob(
                existingAttachment.read<String>('sha256'),
              )) {
            imported++;
            await _markShareFile(
              db,
              intake.id,
              file.ordinal,
              attachmentId,
              'imported',
              null,
            );
            continue;
          }
          if (existingAttachment != null) {
            // The metadata committed but bytes did not reach the durable store.
            await db.customStatement('DELETE FROM attachments WHERE id = ?', [
              attachmentId,
            ]);
          }
          try {
            await attachmentService.importFile(
              file: File(file.path),
              id: attachmentId,
              todoId: intake.id,
              displayName: file.name,
            );
            imported++;
            await _markShareFile(
              db,
              intake.id,
              file.ordinal,
              attachmentId,
              'imported',
              null,
            );
          } catch (error) {
            final reason = '$error';
            failures.add('${file.name}: $reason');
            await _markShareFile(
              db,
              intake.id,
              file.ordinal,
              attachmentId,
              'rejected',
              reason,
            );
          }
        }
        for (var index = 0; index < intake.rejected.length; index++) {
          final rejected = intake.rejected[index];
          failures.add('${rejected.name}: ${rejected.reason}');
          await _markShareFile(
            db,
            intake.id,
            1000 + index,
            'rejected-${intake.id}-$index',
            'rejected',
            rejected.reason,
          );
        }
        final notes = intake.text.trim();
        if (imported == 0 && notes.isEmpty && intake.files.isNotEmpty) {
          // All files were rejected and there was no text to keep.
          await db.deleteTodoItem(intake.id);
        } else {
          tasks++;
          attachments += imported;
        }
        await _markShareState(db, intake.id, 'done');
        await service.complete(intake.id);
      } catch (error) {
        await _markShareState(db, intake.id, 'failed');
        // Keep the intake pending so a later launch can retry the same id.
        failures.add('${intake.title}: $error');
      }
      _activeShareIntakes.remove(intake.id);
    }
    if (!mounted) return;
    setState(() => _index = 1);
    final parts = <String>[
      if (tasks > 0)
        '$tasks shared item${tasks == 1 ? '' : 's'} added to Tasks',
      if (attachments > 0)
        '$attachments file${attachments == 1 ? '' : 's'} attached',
      if (failures.isNotEmpty)
        '${failures.length} item${failures.length == 1 ? '' : 's'} not added',
    ];
    if (parts.isEmpty) return;
    _message(parts.join(' · '));
    if (failures.isNotEmpty) {
      // Individual failures stay visible instead of disappearing into a count.
      for (final failure in failures.take(3)) {
        _message(failure);
      }
    }
  }

  Future<void> _markShareFile(
    AppDatabase db,
    String intakeId,
    int ordinal,
    String attachmentId,
    String status,
    String? reason,
  ) async {
    await db.customStatement(
      'INSERT INTO share_intake_files '
      '(intake_id, ordinal, attachment_id, status, reason, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(intake_id, ordinal) DO UPDATE SET '
      'attachment_id = excluded.attachment_id, status = excluded.status, '
      'reason = excluded.reason, updated_at = excluded.updated_at',
      [
        intakeId,
        ordinal,
        attachmentId,
        status,
        reason,
        AppClock.now().millisecondsSinceEpoch,
      ],
    );
  }

  Future<void> _markShareState(
    AppDatabase db,
    String intakeId,
    String status,
  ) async {
    await db.customStatement(
      'UPDATE share_intake_state SET status = ?, updated_at = ? '
      'WHERE intake_id = ?',
      [status, AppClock.now().millisecondsSinceEpoch, intakeId],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetUpdateTimer?.cancel();
    unawaited(_tabSubscription?.cancel());
    unawaited(_targetSubscription?.cancel());
    unawaited(_shareSubscription?.cancel());
    unawaited(_reminders.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Moves the window of upcoming reminders forward.
      unawaited(_reminders.refresh());
      unawaited(_autoSync());
      unawaited(ref.read(todayWidgetServiceProvider).update());
      unawaited(_importSharedFiles());
    }
  }

  /// Coalesces database stream changes into one widget refresh.
  void _scheduleWidgetUpdate() {
    _widgetUpdateTimer?.cancel();
    _widgetUpdateTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        unawaited(ref.read(todayWidgetServiceProvider).update());
      }
    });
  }

  /// Syncs quietly when the app is opened or returns to the foreground, if the
  /// phone is paired and has not synced in the last minute. Failures are not
  /// shown: being away from the desktop is normal, and the Sync tab still
  /// reports problems when the user syncs by hand.
  Future<void> _autoSync() async {
    if (_syncing || !mounted) return;
    final now = AppClock.now();
    final last = _lastAutoAttempt;
    if (last != null && now.difference(last) < _autoSyncInterval) return;
    _lastAutoAttempt = now;
    setState(() => _syncing = true);
    try {
      await ref
          .read(mobileSyncClientProvider)
          .syncIfDue(minInterval: _autoSyncInterval);
      ref.invalidate(mobileSyncStatusProvider);
    } catch (_) {
      // Quiet by design; see above.
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final result = await ref.read(mobileSyncClientProvider).syncNow();
      ref.invalidate(mobileSyncStatusProvider);
      if (mounted) _message(result);
    } catch (error) {
      if (mounted) _message('Sync failed: $error');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _quickCapture() async {
    final selected = ref.read(agendaDayProvider);
    final now = AppClock.now();
    final day = selected == null ? now : DayMath.dateOnly(selected);
    final sameDay = DayMath.calendarDaysBetween(now, day) == 0;
    final start = sameDay ? now : DateTime(day.year, day.month, day.day, 9);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _QuickCaptureSheet(initialStart: start),
    );
    if (saved == true && mounted) {
      _message(
        'Saved on this device. It will sync when you next open the app, '
        'or tap Sync now.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<AppLockState>>(appLockControllerProvider, (
      previous,
      next,
    ) {
      final lock = next.valueOrNull;
      if (lock == null || lock.locked) return;
      final pending = _pendingTarget;
      if (pending != null) {
        _pendingTarget = null;
        _activateTarget(pending);
      }
    });
    ref.listen(_mobileEventsProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(tasksStreamProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(habitsStreamProvider, (_, _) => _scheduleWidgetUpdate());
    ref.listen(
      habitLogsForDayProvider(DayMath.dateOnly(AppClock.now())),
      (_, _) => _scheduleWidgetUpdate(),
    );
    final pages = <Widget>[
      const _TodayScreen(),
      const _TasksScreen(),
      const _DiaryScreen(),
      _SyncScreen(syncing: _syncing, onSync: _syncNow),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Locus'),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _MobileSearchPage(
                    onOpenTask: (task) {
                      _activateTarget(
                        ItemTarget(kind: ItemKind.task, id: task.id),
                      );
                    },
                    onOpenEvent: (event) {
                      _activateTarget(
                        ItemTarget(kind: ItemKind.event, id: event.id),
                      );
                    },
                  ),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Quick capture',
            onPressed: _quickCapture,
            icon: const Icon(Icons.add_circle_outline),
          ),
          if (_index == 3)
            IconButton(
              tooltip: 'Sync now',
              onPressed: _syncing ? null : _syncNow,
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index == 0 || _index == 1
          ? FloatingActionButton(
              onPressed: _quickCapture,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Tasks',
          ),
          NavigationDestination(
            icon: Icon(Icons.book_outlined),
            selectedIcon: Icon(Icons.book),
            label: 'Diary',
          ),
          NavigationDestination(
            icon: Icon(Icons.sync_outlined),
            selectedIcon: Icon(Icons.sync),
            label: 'Sync',
          ),
        ],
      ),
    );
  }
}
