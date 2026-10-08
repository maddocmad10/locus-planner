import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/error_log_service.dart';
import '../../events/data/event_repository.dart';
import '../import_failure_message.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  bool _minimizeToTray = true;
  String _version = 'Loading…';

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version}+${info.buildNumber}');
  }

  Future<void> _loadNotificationPreferences() async {
    await ref.read(notificationServiceProvider).init();
    if (!mounted) return;
    setState(() {
      _eventRemindersEnabled =
          ref.read(notificationServiceProvider).eventRemindersEnabled;
      _focusAlertsEnabled = ref.read(notificationServiceProvider).focusAlertsEnabled;
      _minimizeToTray = ref.read(windowServiceProvider).minimizeToTray;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final currentThemeMode = ref.watch(themeModeProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ==================== APPEARANCE ====================
          const Text(
            'Appearance',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: RadioGroup<ThemeMode>(
              groupValue: currentThemeMode,
              onChanged: (mode) {
                if (mode != null) themeNotifier.setMode(mode);
              },
              child: Column(
                children: [
                  const RadioListTile<ThemeMode>(
                    title: Text('Light'),
                    value: ThemeMode.light,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('Dark'),
                    value: ThemeMode.dark,
                  ),
                  const RadioListTile<ThemeMode>(
                    title: Text('System Default'),
                    value: ThemeMode.system,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          const Text(
            'Window',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              title: const Text('Close button hides to tray'),
              subtitle: const Text(
                'The X button keeps Locus running. Use the tray menu to exit.',
              ),
              value: _minimizeToTray,
              onChanged: (val) async {
                try {
                  await ref.read(windowServiceProvider).setMinimizeToTray(val);
                  if (mounted) setState(() => _minimizeToTray = val);
                } catch (error, stack) {
                  await ErrorLogService.log(error, stack);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not save window settings.')),
                    );
                  }
                }
              },
            ),
          ),

          const SizedBox(height: 24),

          // ==================== NOTIFICATIONS ====================
          const Text(
            'Notifications',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Event Reminders'),
                  subtitle: const Text(
                    'Receive notifications for upcoming events',
                  ),
                  value: _eventRemindersEnabled,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(notificationServiceProvider)
                          .setEventRemindersEnabled(val);
                      if (val) {
                        await ref
                            .read(eventRepositoryProvider)
                            .restoreFutureReminders();
                      }
                      if (mounted) setState(() => _eventRemindersEnabled = val);
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not update event reminders.')),
                        );
                      }
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Focus Timer Alerts'),
                  subtitle: const Text('Play sound when focus session ends'),
                  value: _focusAlertsEnabled,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(notificationServiceProvider)
                          .setFocusAlertsEnabled(val);
                      if (mounted) setState(() => _focusAlertsEnabled = val);
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not update focus alerts.')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ==================== DATA MANAGEMENT ====================
          const Text(
            'Data Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Create Recovery Backup'),
                  subtitle: const Text(
                    'Save a local recovery point without opening a file picker',
                  ),
                  onTap: () async {
                    final path = await ref.read(dataExportServiceProvider).createRecoveryBackup();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          path == null
                              ? 'Backup failed'
                              : 'Recovery backup created successfully',
                        ),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.download),
                  title: const Text('Export Full Data (JSON)'),
                  subtitle: const Text(
                    'Backup everything (Projects, Events, Diary, etc.)',
                  ),
                  onTap: () async {
                    final service = ref.read(dataExportServiceProvider);
                    try {
                      final success = await service.exportFullDataAsJson();
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Data exported successfully!'),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Data export failed.')),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.event),
                  title: const Text('Export Events as ICS (Outlook)'),
                  subtitle: const Text(
                    'Compatible with Outlook, Google Calendar, Apple Calendar',
                  ),
                  onTap: () async {
                    final service = ref.read(dataExportServiceProvider);
                    try {
                      final success = await service.exportEventsAsIcs();
                      if (success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Events exported as .ics file!'),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('ICS export failed.')),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('Import Data (JSON)'),
                  subtitle: const Text(
                    'This will replace all current data with the backup',
                  ),
                  onTap: () async {
                    // Show confirmation first
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Replace All Data?'),
                        content: const Text(
                          'Importing will delete your current data and replace it with the backup file.\n\nThis cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Import & Replace'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed != true) return;

                    final service = ref.read(dataExportServiceProvider);
                    final bool success;
                    try {
                      success = await service.importFullDataFromJson();
                    } catch (error) {
                      // The service has already logged it. Tell the user:
                      // returning false means "cancelled", a throw means "failed".
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(describeImportFailure(error)),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                      return;
                    }
                    if (!success) return;

                    var remindersRestored = true;
                    try {
                      await ref.read(eventRepositoryProvider).restoreAllReminders();
                    } catch (error, stack) {
                      remindersRestored = false;
                      await ErrorLogService.log(error, stack);
                    }

                    final report = service.lastRestoreReport;
                    final note = report == null || report.isClean
                        ? ''
                        : ' (${report.summary}.)';

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            remindersRestored
                                ? 'Import successful. Data restored and reminders rescheduled.$note'
                                : 'Import successful, but reminders could not be rescheduled.$note',
                          ),
                          backgroundColor:
                              remindersRestored ? Colors.green : Colors.orange,
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ==================== ABOUT ====================
          const Text(
            'About',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Locus Planner'),
              subtitle: Text('Version $_version • Local-first productivity app'),
            ),
          ),
        ],
      ),
    );
  }
}
