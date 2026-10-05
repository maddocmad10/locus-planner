import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/data_export_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/providers/database_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    await NotificationService.instance.init();
    if (!mounted) return;
    setState(() {
      _eventRemindersEnabled =
          NotificationService.instance.eventRemindersEnabled;
      _focusAlertsEnabled =
          NotificationService.instance.focusAlertsEnabled;
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
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: currentThemeMode,
                  onChanged: (mode) {
                    if (mode != null) themeNotifier.setMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: currentThemeMode,
                  onChanged: (mode) {
                    if (mode != null) themeNotifier.setMode(mode);
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  value: ThemeMode.system,
                  groupValue: currentThemeMode,
                  onChanged: (mode) {
                    if (mode != null) themeNotifier.setMode(mode);
                  },
                ),
              ],
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
                  subtitle: const Text('Receive notifications for upcoming events'),
                  value: _eventRemindersEnabled,
                  onChanged: (val) async {
                    setState(() => _eventRemindersEnabled = val);
                    await NotificationService.instance
                        .setEventRemindersEnabled(val);
                  },
                ),
                SwitchListTile(
                  title: const Text('Focus Timer Alerts'),
                  subtitle: const Text('Play sound when focus session ends'),
                  value: _focusAlertsEnabled,
                  onChanged: (val) async {
                    setState(() => _focusAlertsEnabled = val);
                    await NotificationService.instance
                        .setFocusAlertsEnabled(val);
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
        leading: const Icon(Icons.download),
        title: const Text('Export Full Data (JSON)'),
        subtitle: const Text('Backup everything (Projects, Events, Diary, etc.)'),
        onTap: () async {
          final service = DataExportService(ref.read(databaseProvider));
          final success = await service.exportFullDataAsJson();

          if (success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Data exported successfully!')),
            );
          }
        },
      ),
      ListTile(
        leading: const Icon(Icons.event),
        title: const Text('Export Events as ICS (Outlook)'),
        subtitle: const Text('Compatible with Outlook, Google Calendar, Apple Calendar'),
        onTap: () async {
          final service = DataExportService(ref.read(databaseProvider));
          final success = await service.exportEventsAsIcs();

          if (success && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Events exported as .ics file!')),
            );
          }
        },
      ),
      ListTile(
  leading: const Icon(Icons.upload),
  title: const Text('Import Data (JSON)'),
  subtitle: const Text('This will replace all current data with the backup'),
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Import & Replace'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = DataExportService(ref.read(databaseProvider));
    final success = await service.importFullDataFromJson();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Import successful! Data has been restored.'
              : 'Import failed. Please check the file.'),
          backgroundColor: success ? Colors.green : Colors.red,
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
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Locus Planner'),
              subtitle: Text('Version 1.2.0 • Local-first productivity app'),
            ),
          ),
        ],
      ),
    );
  }
}