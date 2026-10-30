import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/services/data_export_service.dart';
import '../../../core/utils/app_clock.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/lan_sync_server.dart';
import '../../../core/services/sync_tls.dart';
import '../../../core/providers/quick_capture_provider.dart';
import '../../../core/services/error_log_service.dart';
import '../../events/data/event_repository.dart';
import '../import_failure_message.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  bool _eventRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  bool _minimizeToTray = true;
  bool _quickCaptureEnabled = true;
  String _version = 'Loading…';
  bool _syncBusy = false;
  bool _syncRunning = false;
  bool _syncRefreshing = false;
  String? _pairingCode;
  DateTime? _pairingExpiresAt;
  String? _fingerprint;
  String? _pairingQr;
  List<LanAddress> _lanAddresses = const [];
  String? _selectedLanAddress;
  List<Map<String, dynamic>> _pairedDevices = [];
  Timer? _syncTicker;
  int _syncTicks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _onSyncTick(),
    );
    _loadNotificationPreferences();
    _loadVersion();
    _loadSyncStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadSyncStatus(forceDetails: true));
    }
  }

  /// A pairing code is consumed on the phone, not on the desktop, so the
  /// settings page polls the server instead of only reading it once. The same
  /// ticker rebuilds the countdown and hides a code as soon as it expires.
  void _onSyncTick() {
    if (!mounted) return;
    _syncTicks++;
    final expiresAt = _pairingExpiresAt;
    if (expiresAt != null && !AppClock.now().isBefore(expiresAt)) {
      unawaited(_loadSyncStatus());
      return;
    }
    if (_pairingCode != null) setState(() {});
    if (_syncTicks % 5 == 0) unawaited(_loadSyncStatus());
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
      _eventRemindersEnabled = ref
          .read(notificationServiceProvider)
          .eventRemindersEnabled;
      _focusAlertsEnabled = ref
          .read(notificationServiceProvider)
          .focusAlertsEnabled;
      _minimizeToTray = ref.read(windowServiceProvider).minimizeToTray;
      _quickCaptureEnabled = ref.read(quickCaptureServiceProvider).enabled;
    });
  }

  Future<void> _loadSyncStatus({bool forceDetails = false}) async {
    if (_syncRefreshing) return;
    _syncRefreshing = true;
    try {
      final server = ref.read(lanSyncServerProvider);
      final devices = await server.pairedDevices();
      if (!mounted) return;
      final running = server.isRunning;
      final code = server.pairingCode;
      final expiresAt = server.pairingExpiresAt;
      final needsDetails =
          forceDetails ||
          running != _syncRunning ||
          code != _pairingCode ||
          _lanAddresses.isEmpty;
      setState(() {
        _syncRunning = running;
        _pairingCode = code;
        _pairingExpiresAt = expiresAt;
        _pairedDevices = devices;
        if (code == null) _pairingQr = null;
      });
      if (needsDetails) await _refreshPairingDetails();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
    } finally {
      _syncRefreshing = false;
    }
  }

  /// Rebuilds what a phone needs to pair: every reachable LAN address, the
  /// certificate fingerprint and the QR code for the selected address.
  Future<void> _refreshPairingDetails() async {
    final server = ref.read(lanSyncServerProvider);
    final code = server.pairingCode;
    final fingerprint = server.fingerprint;
    var addresses = const <LanAddress>[];
    if (server.isRunning) {
      try {
        addresses = await localLanInterfaces();
      } catch (error, stack) {
        await ErrorLogService.log(error, stack);
      }
    }
    if (!mounted) return;
    setState(() {
      _lanAddresses = addresses;
      if (_selectedLanAddress == null ||
          !addresses.any((item) => item.address == _selectedLanAddress)) {
        _selectedLanAddress = addresses.isEmpty
            ? null
            : addresses.first.address;
      }
      _fingerprint = fingerprint;
      _pairingCode = code;
      _pairingExpiresAt = server.pairingExpiresAt;
      _pairingQr = _buildPairingQr();
    });
  }

  String? _buildPairingQr() {
    final address = _selectedLanAddress;
    final code = _pairingCode;
    final fingerprint = _fingerprint;
    if (!_syncRunning ||
        address == null ||
        code == null ||
        fingerprint == null) {
      return null;
    }
    return SyncPairingPayload(
      host: address,
      port: ref.read(lanSyncServerProvider).boundPort ?? LanSyncServer.port,
      code: code,
      fingerprint: fingerprint,
    ).toUri().toString();
  }

  void _onLanAddressChanged(String? address) {
    if (address == null) return;
    setState(() {
      _selectedLanAddress = address;
      _pairingQr = _buildPairingQr();
    });
  }

  String _pairingExpiryLabel() =>
      pairingCodeExpiryLabel(_pairingExpiresAt, AppClock.now());

  Future<void> _newPairingCode() async {
    final server = ref.read(lanSyncServerProvider);
    server.regeneratePairingCode();
    setState(() {
      _pairingCode = server.pairingCode;
      _pairingExpiresAt = server.pairingExpiresAt;
    });
    await _refreshPairingDetails();
  }

  Future<void> _toggleLanSync(bool enabled) async {
    if (_syncBusy) return;
    setState(() => _syncBusy = true);
    try {
      final server = ref.read(lanSyncServerProvider);
      if (enabled) {
        await server.start();
        await server.saveEnabledPreference(true);
      } else {
        await server.stop();
        await server.saveEnabledPreference(false);
      }
      final devices = await server.pairedDevices();
      if (!mounted) return;
      setState(() {
        _syncRunning = server.isRunning;
        _pairingCode = server.pairingCode;
        _pairingExpiresAt = server.pairingExpiresAt;
        _pairedDevices = devices;
      });
      await _refreshPairingDetails();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not ${enabled ? 'start' : 'stop'} LAN sync: $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncBusy = false);
    }
  }

  Future<void> _revokeSyncDevice(String deviceId) async {
    try {
      await ref.read(lanSyncServerProvider).revokeDevice(deviceId);
      await _loadSyncStatus();
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
    }
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
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Close button hides to tray'),
                  subtitle: const Text(
                    'The X button keeps Locus running. Use the tray menu to exit.',
                  ),
                  value: _minimizeToTray,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(windowServiceProvider)
                          .setMinimizeToTray(val);
                      if (mounted) setState(() => _minimizeToTray = val);
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not save window settings.'),
                          ),
                        );
                      }
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Global quick capture'),
                  subtitle: Text(
                    'Press Ctrl+Shift+L anywhere to capture an event, to-do, or diary note. '
                    'Works while Locus is minimized to the tray.',
                  ),
                  value: _quickCaptureEnabled,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(quickCaptureServiceProvider)
                          .setEnabled(val);
                      if (mounted) setState(() => _quickCaptureEnabled = val);
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update quick capture.'),
                          ),
                        );
                      }
                    }
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
                  subtitle: const Text(
                    'Shown only while Locus is running, including in the tray. '
                    'Fully quitting the app cannot deliver a reminder. '
                    'A reminder more than 15 minutes late is skipped.',
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
                          const SnackBar(
                            content: Text('Could not update event reminders.'),
                          ),
                        );
                      }
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Focus Timer Alerts'),
                  subtitle: const Text(
                    'Played after the session is saved, not before',
                  ),
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
                          const SnackBar(
                            content: Text('Could not update focus alerts.'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ==================== DEVICE SYNC ====================
          const Text(
            'Device Sync (LAN)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow devices on this Wi-Fi to pair'),
                    subtitle: Text(
                      _syncRunning
                          ? 'The versioned sync API is listening on TCP port ${LanSyncServer.port}. It stays on after restart until you switch it off.'
                          : 'Starts a local API server. Only pair devices you trust.',
                    ),
                    value: _syncRunning,
                    onChanged: _syncBusy || !Platform.isWindows
                        ? null
                        : _toggleLanSync,
                  ),
                  if (!Platform.isWindows)
                    const Text(
                      'LAN hosting is currently enabled for Windows desktop builds only.',
                    ),
                  if (_syncRunning) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      'Client endpoint: https://${_selectedLanAddress ?? '<desktop-IPv4-address>'}:${LanSyncServer.port}/api/v1',
                    ),
                    if (_lanAddresses.length > 1) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'This computer has more than one network address. Choose the one on the same Wi-Fi as your phone:',
                      ),
                      RadioGroup<String>(
                        groupValue: _selectedLanAddress,
                        onChanged: _onLanAddressChanged,
                        child: Column(
                          children: [
                            for (final address in _lanAddresses)
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: address.address,
                                title: Text(address.address),
                                subtitle: Text(address.interfaceName),
                              ),
                          ],
                        ),
                      ),
                    ] else if (_lanAddresses.length == 1) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Network adapter: ${_lanAddresses.single.interfaceName}',
                      ),
                    ],
                    if (_fingerprint != null) ...[
                      const SizedBox(height: 8),
                      const Text('Security fingerprint of this computer:'),
                      SelectableText(
                        shortSyncFingerprint(_fingerprint!),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (_pairingCode != null) ...[
                      Text('One-time pairing code (${_pairingExpiryLabel()}):'),
                      SelectableText(
                        _pairingCode!,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (_pairingQr != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'In the Locus app on your phone, open Sync and scan this code:',
                        ),
                        const SizedBox(height: 8),
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(data: _pairingQr!, size: 200),
                        ),
                      ],
                      const SizedBox(height: 8),
                      const Text(
                        'Without a camera, enter the address and code on the phone and check that it shows the fingerprint above. The code is consumed after one successful pairing.',
                      ),
                    ] else
                      const Text('No active pairing code.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _newPairingCode,
                      icon: const Icon(Icons.refresh),
                      label: const Text('New pairing code'),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Paired devices (${_pairedDevices.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (_pairedDevices.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('No devices paired yet.'),
                      ),
                    for (final device in _pairedDevices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.devices),
                        title: Text(
                          device['name'] as String? ?? 'Unnamed device',
                        ),
                        subtitle: Text(device['deviceId'] as String? ?? ''),
                        trailing: IconButton(
                          tooltip: 'Revoke device access',
                          icon: const Icon(Icons.link_off),
                          onPressed: () =>
                              _revokeSyncDevice(device['deviceId'] as String),
                        ),
                      ),
                  ],
                ],
              ),
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
                    final service = ref.read(dataExportServiceProvider);
                    try {
                      await service.createRecoveryBackup();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Recovery backup created successfully'),
                        ),
                      );
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Backup failed: $error. Details were written to the error log.',
                          ),
                        ),
                      );
                    }
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
                    'Review the backup contents before importing',
                  ),
                  onTap: () async {
                    final service = ref.read(dataExportServiceProvider);
                    BackupSummary? summary;
                    try {
                      summary = await service.inspectSelectedBackup();
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(describeImportFailure(error))),
                        );
                      }
                      return;
                    }

                    if (summary == null) return;
                    final backupSummary = summary;
                    if (!context.mounted) {
                      service.discardPendingImport();
                      return;
                    }
                    var replaceEverything = false;
                    final decision = await showDialog<Map<String, bool>>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setDialogState) => AlertDialog(
                          title: Text(
                            backupSummary.isPartial
                                ? 'Partial Backup Detected'
                                : 'Review Backup Import',
                          ),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Included sections:'),
                                const SizedBox(height: 8),
                                ...backupSummary.counts.entries.map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      '${backupSummary.readableName(entry.key)}: '
                                      '${entry.value} — '
                                      '${backupSummary.importMode(entry.key)}',
                                    ),
                                  ),
                                ),
                                if (backupSummary
                                    .untouchedSections
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Sections that will stay untouched:',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    backupSummary.untouchedSections
                                        .map(backupSummary.readableName)
                                        .join(', '),
                                  ),
                                ],
                                if (backupSummary.canReplaceEverything) ...[
                                  const SizedBox(height: 12),
                                  CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    value: replaceEverything,
                                    onChanged: (value) => setDialogState(
                                      () => replaceEverything = value ?? false,
                                    ),
                                    title: const Text('Replace everything'),
                                    subtitle: const Text(
                                      'Treat missing sections as empty and remove their existing data. '
                                      'Use this only if this older backup represents your complete data.',
                                    ),
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                const Text(
                                  'Review the import plan carefully. This action cannot be undone.',
                                ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, null),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, {
                                'confirmed': true,
                                'replaceEverything': replaceEverything,
                              }),
                              child: const Text('Continue'),
                            ),
                          ],
                        ),
                      ),
                    );
                    final confirmed = decision?['confirmed'] == true;
                    replaceEverything = decision?['replaceEverything'] ?? false;

                    if (confirmed != true) {
                      service.discardPendingImport();
                      return;
                    }

                    final bool success;
                    try {
                      success = await service.importFullDataFromJson(
                        replaceEverything: replaceEverything,
                      );
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

                    try {
                      await ref.read(themeModeProvider.notifier).reload();
                      final notifications = ref.read(
                        notificationServiceProvider,
                      );
                      await notifications.reloadPreferences();
                      if (mounted) {
                        setState(() {
                          _eventRemindersEnabled =
                              notifications.eventRemindersEnabled;
                          _focusAlertsEnabled =
                              notifications.focusAlertsEnabled;
                        });
                      }
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                    }

                    var remindersRestored = true;
                    try {
                      await ref
                          .read(eventRepositoryProvider)
                          .restoreAllReminders();
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
                          backgroundColor: remindersRestored
                              ? Colors.green
                              : Colors.orange,
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
              subtitle: Text(
                'Version $_version • Local-first productivity app',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
