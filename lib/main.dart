import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'app.dart';
import 'features/mobile/mobile_app.dart';
import 'core/db/app_database.dart';
import 'core/db/startup_checks.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/command_action_provider.dart';
import 'core/providers/landing_page_provider.dart';
import 'core/providers/item_navigation_provider.dart';
import 'core/providers/mini_today_provider.dart';
import 'core/providers/navigation_provider.dart';
import 'core/utils/app_clock.dart';
import 'core/providers/service_providers.dart';
import 'core/reminders/windows_toast_platform.dart';
import 'core/services/error_log_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_outbox_pruner.dart';
import 'core/services/window_service.dart';
import 'core/services/single_instance_service.dart';
import 'core/services/window_reveal.dart';
import 'core/security/database_paths.dart';
import 'core/security/database_security_options.dart';
import 'core/security/startup_recovery_button.dart';
import 'features/events/data/event_repository.dart';
import 'features/events/data/reminder_inbox_service.dart';
import 'features/tasks/data/task_repository.dart';
import 'features/mobile/data/mobile_sync_client.dart';
import 'core/providers/quick_capture_provider.dart';

final SingleInstanceService _singleInstanceService = SingleInstanceService();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialUri = args
      .where((arg) => arg.startsWith('locus://'))
      .cast<String?>()
      .firstWhere((arg) => true, orElse: () => null);
  final startInBackground = args.contains('--background');

  // E0 gate: live encryption is off unless the release environment turns it
  // on. Automatic plaintext conversion has its own LOCUS_DB_MIGRATION switch.
  // The connection factory then owns key, identity and recovery rules.
  DatabaseSecurity.configureFromEnvironment();

  // Native SQLite3MultipleCiphers is not a pub package, so register its
  // licence explicitly for the in-app licence screen.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/sqlite3mc_LICENSE.txt');
    yield LicenseEntryWithLineBreaks(['SQLite3MultipleCiphers'], text);
  });

  // Install the global handlers before either startup path so an error on
  // Android reaches locus_error.log too, not just one on Windows.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(
      _logGlobalError(details.exception, details.stack ?? StackTrace.current),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_logGlobalError(error, stack));
    return true;
  };

  // Android uses a compact touch-first shell and the same local Drift schema.
  // Keep desktop-only window/tray/single-instance initialization out of the
  // mobile startup path.
  if (Platform.isAndroid) {
    await _runAndroidApp();
    return;
  }

  final instanceResult = await _singleInstanceService.acquire(
    activationUri: initialUri,
  );
  if (instanceResult == SingleInstanceResult.alreadyRunning) {
    exit(0);
  }

  AppDatabase? db;
  ProviderContainer? container;
  WindowService? windowService;
  NotificationService? notificationService;

  try {
    await windowManager.ensureInitialized();

    db = AppDatabase();
    windowService = WindowService();
    notificationService = NotificationService(db: db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        windowServiceProvider.overrideWithValue(windowService),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
    );

    windowService.onExit = () => _shutdown(
      db: db!,
      container: container!,
      notificationService: notificationService!,
      windowService: windowService!,
    );

    const options = WindowOptions(
      size: Size(1360, 860),
      center: true,
      title: 'Locus - Planner',
      titleBarStyle: TitleBarStyle.normal,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowService!.init();
      if (startInBackground) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    await windowManager.setPreventClose(true);
    _singleInstanceService.onSecondInstance = _revealMainWindow;
    _singleInstanceService.onActivation = (uri) =>
        _handleActivation(container!, windowService!, uri);

    // Open (and migrate) the database before anything optional runs. A broken
    // database must reach the startup error screen below, not be logged and
    // ignored as if it were a notification problem.
    await verifyDatabaseReady(db);

    // The landing-page choice is a local preference. Reading it before the
    // first frame means the chosen page is already selected instead of the app
    // visibly jumping after startup.
    await _applyLandingPage(db, container);

    // Render the database-backed UI before initializing optional integrations.
    // Reminder restoration and tray setup can take noticeable time on Windows;
    // neither should block the first usable frame after the database is ready.
    runApp(
      UncontrolledProviderScope(container: container, child: const LocusApp()),
    );
    _signalSmokeReadyAfterFirstFrame();
    if (initialUri != null) {
      unawaited(_handleActivation(container, windowService, initialUri));
    }
    unawaited(
      _initializeOptionalServices(
        container: container,
        notificationService: notificationService,
        windowService: windowService,
        db: db,
      ),
    );
    unawaited(_runAutoBackup(container));
    _backupTimer?.cancel();
    _backupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(_runAutoBackup(container!));
      unawaited(
        container
            .read(calendarSubscriptionServiceProvider)
            .refreshAll()
            .catchError((Object _) {}),
      );
    });
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    _quietly(() => windowService?.dispose());
    try {
      await windowManager.setPreventClose(false);
    } catch (_) {
      // The window manager may not have finished initializing.
    }
    _quietly(() => notificationService?.dispose());
    _quietly(() => container?.dispose());
    // If this throws, the error screen below would never be shown.
    await closeQuietly(db);
    final backupsPath = await _backupsPath();
    runApp(StartupErrorApp(error: error, backupsPath: backupsPath));
  }
}

Future<void> _runAndroidApp() async {
  final db = AppDatabase();
  try {
    await verifyDatabaseReady(db);
    await db.ensureDeviceIdentity();
    // An unpaired phone has no desktop to send its changes to, so its outbox
    // would otherwise grow forever and keep deleted diary text. A paired phone
    // is never cleared here; its outbox holds unsent changes.
    try {
      await MobileSyncClient(db).pruneOutboxIfUnpaired();
    } catch (error, stack) {
      // Housekeeping must not stop the app from starting.
      await _logGlobalError(error, stack);
    }
    runApp(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => db.close());
            return db;
          }),
        ],
        child: const LocusMobileApp(),
      ),
    );
  } catch (error, stack) {
    await _logGlobalError(error, stack);
    await closeQuietly(db);
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Locus could not start',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Your local database was not intentionally replaced.',
                      ),
                      const SizedBox(height: 12),
                      SelectableText('$error'),
                      const StartupRecoveryButton(compact: true),
                      const StartupRawRecoveryButton(compact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Applies the stored start-page preference to the initial navigation index.
/// A bad or unreadable preference must never block startup, so failures are
/// logged and the default Today page is kept.
Future<void> _applyLandingPage(
  AppDatabase db,
  ProviderContainer container,
) async {
  try {
    final stored = await db.getSetting(
      AppDatabase.defaultLandingPageSettingKey,
    );
    final landing = LandingPage.fromStorage(stored);
    if (landing != LandingPage.dashboard) {
      container
          .read(navigationIndexProvider.notifier)
          .setIndex(landing.navigationIndex);
    }
  } catch (error, stack) {
    await _logGlobalError(error, stack);
  }
}

/// Optional CI handshake: write a marker after the first planner frame has
/// rendered. Startup-error UI intentionally does not emit this marker.
void _signalSmokeReadyAfterFirstFrame() {
  final readyPath = Platform.environment['LOCUS_SMOKE_READY_FILE'];
  if (readyPath == null || readyPath.isEmpty) return;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      try {
        await File(readyPath).writeAsString('ready');
      } catch (error, stack) {
        await _logGlobalError(error, stack);
      }
    }());
  });
}

Future<void> _initializeOptionalServices({
  required ProviderContainer container,
  required NotificationService notificationService,
  required WindowService windowService,
  required AppDatabase db,
}) async {
  // Every local edit is queued in the outbox even while LAN sync is off. Trim
  // it at startup so it cannot grow without bound, and so deleted diary text
  // does not stay in the database. With no paired phones this clears it; a
  // phone that pairs later starts from a snapshot.
  try {
    await SyncOutboxPruner(db).prune();
  } catch (error, stack) {
    // Housekeeping must not prevent the planner from starting.
    await _logGlobalError(error, stack);
  }

  // Events and to-dos that arrive from the phone are written straight to the
  // database, so their reminders must be armed (or cancelled) here.
  container.read(lanSyncServerProvider).onChangesApplied = (result) async {
    final eventIds = [
      for (final change in result.changes)
        if (change.type == 'event') change.id,
    ];
    if (eventIds.isNotEmpty) {
      await container
          .read(eventRepositoryProvider)
          .rescheduleReminders(eventIds);
    }
    final todoIds = [
      for (final change in result.changes)
        if (change.type == 'todo') change.id,
    ];
    if (todoIds.isNotEmpty) {
      await container.read(taskRepositoryProvider).rescheduleReminders(todoIds);
    }
  };

  try {
    await notificationService.init();
    if (Platform.isWindows) {
      await container.read(windowsReminderServiceProvider).start();
    }
    // Collect reminders that were due while Locus was closed before arming
    // the next future occurrence.
    await container.read(reminderInboxServiceProvider).start();
    if (Platform.isWindows) {
      final missed = await container
          .read(windowsReminderServiceProvider)
          .takeMissed();
      final inbox = container.read(reminderInboxServiceProvider);
      for (final reminder in missed) {
        if (reminder.kind == 'task') {
          await inbox.rememberMissedTask(
            taskId: reminder.entityId,
            title: 'Task reminder',
            reminderAt: reminder.fireAt,
          );
        } else {
          await inbox.rememberMissed(
            eventId: reminder.entityId,
            title: 'Event reminder',
            occurrenceStart: reminder.fireAt,
            reminderAt: reminder.fireAt,
          );
        }
      }
    }
    await container.read(eventRepositoryProvider).restoreFutureReminders();
    await container.read(taskRepositoryProvider).restoreAllReminders();
  } catch (error, stack) {
    // Notifications are optional; failure must not prevent the planner UI.
    await _logGlobalError(error, stack);
  }

  // If Windows was told to start Locus at sign-in, keep the registered path
  // pointing at this installation after a move or upgrade.
  try {
    await container.read(launchAtStartupServiceProvider).refreshIfEnabled();
  } catch (error, stack) {
    await _logGlobalError(error, stack);
  }

  try {
    await _initSystemTray(
      windowService,
      tooltip: await _nextEventTooltip(db),
      onMiniToday: () => _toggleMiniToday(container, windowService),
      onExit: () => _shutdown(
        db: db,
        container: container,
        notificationService: notificationService,
        windowService: windowService,
      ),
    );
  } catch (error, stack) {
    // The window must remain usable if the tray integration is unavailable.
    await _logGlobalError(error, stack);
    windowService.trayReady = false;
    windowService.minimizeToTray = false;
  }

  await _installJumpList();

  try {
    await container
        .read(quickCaptureServiceProvider)
        .init(
          onTriggered: () async {
            await _revealMainWindow();
            container.read(quickCaptureRequestProvider.notifier).request();
          },
        );
  } catch (error, stack) {
    // The planner is usable without a global hotkey.
    await _logGlobalError(error, stack);
  }

  // Hosting used to start only when the Settings switch was flipped, so a
  // reboot silently turned LAN sync off. Remember the user's choice and bring
  // it back up after the rest of startup has finished.
  try {
    await container.read(lanSyncServerProvider).startFromSavedPreference();
  } catch (error, stack) {
    // A port conflict or unavailable certificate must not stop the planner.
    await _logGlobalError(error, stack);
  }

  // Read-only calendar feeds refresh on startup and are marked stale if the
  // network or feed fails. Their cache never leaves this PC.
  unawaited(
    container
        .read(calendarSubscriptionServiceProvider)
        .refreshAll()
        .catchError((Object _) {}),
  );
}

Future<void> _runAutoBackup(ProviderContainer container) async {
  try {
    await container.read(autoBackupServiceProvider).runIfDue();
  } catch (error, stack) {
    // Automatic backups run in the background; surface failures through the
    // existing global error log instead of silently dropping them.
    await _logGlobalError(error, stack);
  }
}

/// Runs cleanup that must not be allowed to throw out of the error handler.
void _quietly(void Function() action) {
  try {
    action();
  } catch (_) {}
}

Future<String> _backupsPath() async {
  try {
    final support = await DatabasePathsResolver.secureDataDirectory();
    return '${support.path}${Platform.pathSeparator}backups';
  } catch (_) {
    return 'Application support\\backups';
  }
}

Future<void> _logGlobalError(Object error, StackTrace stack) =>
    ErrorLogService.log(error, stack);

class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    required this.error,
    required this.backupsPath,
    super.key,
  });

  final Object error;
  final String backupsPath;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Locus - Startup Error',
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Locus could not start',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The database or startup services failed to initialize. Your existing data was not intentionally replaced.',
                  ),
                  const SizedBox(height: 16),
                  SelectableText('Error: $error'),
                  const SizedBox(height: 16),
                  const Text('Recovery backups folder:'),
                  SelectableText(backupsPath),
                  const SizedBox(height: 12),
                  const Text(
                    'A detailed error log is stored as locus_error.log in the application support folder.',
                  ),
                  const StartupRecoveryButton(),
                  const StartupRawRecoveryButton(),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      try {
                        await windowManager.setPreventClose(false);
                        await windowManager.destroy();
                      } catch (_) {
                        // There is no recovery action left if the native window
                        // manager itself is unavailable.
                      } finally {
                        await _singleInstanceService.release();
                      }
                    },
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('Exit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<String> _nextEventTooltip(AppDatabase db) async {
  try {
    final now = AppClock.now().millisecondsSinceEpoch;
    final rows = await db
        .customSelect(
          'SELECT title, start_time FROM events '
          'WHERE start_time >= ? ORDER BY start_time LIMIT 1',
          variables: [Variable.withInt(now)],
        )
        .get();
    if (rows.isEmpty) return 'Locus Planner';
    final title = rows.first.read<String>('title');
    final start = DateTime.fromMillisecondsSinceEpoch(
      rows.first.read<int>('start_time'),
    );
    final time =
        '${start.hour.toString().padLeft(2, '0')}:'
        '${start.minute.toString().padLeft(2, '0')}';
    return 'Locus - Next: $title at $time';
  } catch (_) {
    return 'Locus Planner';
  }
}

Future<void> _initSystemTray(
  WindowService windowService, {
  required Future<void> Function() onExit,
  required Future<void> Function() onMiniToday,
  String tooltip = 'Locus Planner',
}) async {
  await trayManager.setIcon('assets/tray_icon.ico');
  await trayManager.setToolTip(tooltip);
  final menu = Menu(
    items: [
      MenuItem(
        key: 'show_window',
        label: 'Show Locus',
        onClick: (menuItem) => _revealMainWindow(),
      ),
      MenuItem(
        key: 'mini_today',
        label: 'Mini Today',
        onClick: (menuItem) async {
          await onMiniToday();
        },
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit',
        onClick: (menuItem) async {
          try {
            await Future.wait<void>([
              windowService.saveBounds().catchError((Object _) {}),
              onExit(),
            ]);
          } finally {
            try {
              await windowManager.setPreventClose(false);
            } finally {
              await windowManager.destroy();
            }
          }
        },
      ),
    ],
  );
  await trayManager.setContextMenu(menu);
  trayManager.addListener(_TrayListener());
  windowService.trayReady = true;
}

/// Shows the main window whether it is minimized, hidden in the tray, or
/// already visible. Used by the tray icon, the tray menu and second launches.
Future<void> _revealMainWindow() => revealWindow(
  isMinimized: windowManager.isMinimized,
  restore: windowManager.restore,
  show: windowManager.show,
  focus: windowManager.focus,
);

Future<void> _toggleMiniToday(
  ProviderContainer container,
  WindowService windowService,
) async {
  final enabled = !container.read(miniTodayModeProvider);
  container.read(miniTodayModeProvider.notifier).state = enabled;
  if (enabled) {
    await windowService.enterMiniMode();
  } else {
    await windowService.exitMiniMode();
  }
  await _revealMainWindow();
}

Future<void> _installJumpList() async {
  if (!Platform.isWindows) return;
  try {
    await const WindowsToastPlatform().updateJumpList([
      {
        'id': 'open',
        'title': 'Open Locus',
        'arguments': '',
        'description': 'Show the planner',
      },
      {
        'id': 'capture',
        'title': 'Quick capture',
        'arguments': 'locus://quick-capture',
        'description': 'Add a task without opening the full planner',
      },
      {
        'id': 'newtask',
        'title': 'New task',
        'arguments': 'locus://new-task',
        'description': 'Open the to-do editor',
      },
      {
        'id': 'mini',
        'title': 'Mini Today',
        'arguments': 'locus://mini',
        'description': 'Open the compact always-on-top view',
      },
    ]);
  } catch (error, stack) {
    await _logGlobalError(error, stack);
  }
}

Future<void> _handleActivation(
  ProviderContainer container,
  WindowService windowService,
  String? uri,
) async {
  await _revealMainWindow();
  if (uri == null) return;
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.scheme != 'locus') return;
  if (parsed.host == 'snooze') {
    final id = parsed.queryParameters['id'];
    final minutes = int.tryParse(parsed.queryParameters['min'] ?? '10') ?? 10;
    if (id != null && id.isNotEmpty) {
      await container
          .read(windowsReminderServiceProvider)
          .snooze(id, minutes.clamp(1, 120));
    }
    return;
  }
  if (parsed.host == 'open') {
    final target = itemTargetFromUri(parsed);
    if (target != null) {
      container.read(itemActivationProvider.notifier).activate(target);
    }
    return;
  }
  if (parsed.host == 'quick-capture') {
    container.read(quickCaptureRequestProvider.notifier).request();
    return;
  }
  if (parsed.host == 'new-task') {
    container.read(navigationIndexProvider.notifier).setIndex(NavPage.tasks);
    container
        .read(commandActionProvider.notifier)
        .dispatch(CommandAction.newTask);
    return;
  }
  if (parsed.host == 'mini') {
    await _toggleMiniToday(container, windowService);
    return;
  }
}

bool _shutdownStarted = false;
Timer? _backupTimer;

Future<void> _shutdown({
  required AppDatabase db,
  required ProviderContainer container,
  required NotificationService notificationService,
  required WindowService windowService,
}) async {
  if (_shutdownStarted) return;
  _shutdownStarted = true;
  _backupTimer?.cancel();
  _backupTimer = null;
  windowService.dispose();
  notificationService.dispose();
  try {
    await container.read(reminderInboxServiceProvider).markStopped();
  } catch (_) {}
  try {
    container.read(quickCaptureServiceProvider).dispose();
  } catch (_) {}
  try {
    await container.read(lanSyncServerProvider).stop();
  } catch (_) {}
  container.dispose();
  try {
    await db.close();
  } finally {
    await _singleInstanceService.release();
  }
}

class _TrayListener with TrayListener {
  @override
  void onTrayIconMouseDown() {
    unawaited(_revealMainWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }
}
