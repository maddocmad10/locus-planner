import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/app_links.dart';
import 'calendar_feed_settings_card.dart';
import 'todoist_import_dialog.dart';
import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/attachments/attachment_types.dart';
import '../../../core/services/attachments/locus_archive.dart';
import '../../../core/services/auto_backup_service.dart';
import '../../../core/services/backup_encryption_service.dart';
import '../../../core/services/data_export_service.dart';
import '../../../core/services/diagnostics_service.dart';
import '../../../core/services/encrypted_diary_service.dart';
import '../../../core/utils/app_clock.dart';
import '../../../core/widgets/progress_dialog.dart';
import '../../../core/widgets/secret_prompt.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/landing_page_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/lan_sync_server.dart';
import '../../../core/services/sync_tls.dart';
import '../../../core/providers/quick_capture_provider.dart';
import '../../../core/services/error_log_service.dart';
import '../../../core/security/database_bootstrap.dart';
import '../../../core/security/database_key_store.dart';
import '../../../core/security/database_metadata.dart';
import '../../../core/security/database_paths.dart';
import '../../../core/security/database_security_options.dart';
import '../../../core/security/recovery_envelope.dart';
import '../../../core/security/recovery_envelope_store.dart';
import '../../../core/security/quarantine_service.dart';
import '../../../core/security/plaintext_artifact_service.dart';
import '../../../core/security/start_fresh_service.dart';
import '../../../core/security/recovery_package_service.dart';
import '../../../core/security/recovery_restore_service.dart';
import '../../../core/security/logical_restore_service.dart';
import '../../../core/services/attachments/attachment_key_store.dart';
import '../../../core/services/crypto/encrypted_envelope.dart';
import '../../events/data/event_repository.dart';
import '../../events/data/reminder_inbox_service.dart';
import '../../tasks/data/task_repository.dart';
import '../../app_lock/presentation/app_lock_settings_card.dart';
import '../../app_lock/providers/app_lock_controller.dart';
import '../import_failure_message.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage>
    with WidgetsBindingObserver {
  bool _eventRemindersEnabled = true;
  bool _taskRemindersEnabled = true;
  bool _focusAlertsEnabled = true;
  bool _hideNotificationTitles = false;
  bool _windowsSchedulingDegraded = false;
  bool _minimizeToTray = true;
  bool _quickCaptureEnabled = true;
  bool _launchAtLogin = false;
  bool _launchAtLoginSupported = false;
  bool _encryptAutomaticBackups = false;
  bool _includeAttachmentsInAutomaticBackups = false;
  BackupHealth? _backupHealth;
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
    _loadLaunchAtStartup();
    _loadBackupEncryption();
    _loadBackupStatus();
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
    final hideTitles =
        await ref
            .read(databaseProvider)
            .getSetting(AppDatabase.hideNotificationTitlesSettingKey) ==
        '1';
    final degraded =
        await ref
            .read(databaseProvider)
            .getSetting(AppDatabase.reminderSchedulingDegradedSettingKey) ==
        '1';
    if (!mounted) return;
    setState(() {
      _eventRemindersEnabled = ref
          .read(notificationServiceProvider)
          .eventRemindersEnabled;
      _taskRemindersEnabled = ref
          .read(notificationServiceProvider)
          .taskRemindersEnabled;
      _focusAlertsEnabled = ref
          .read(notificationServiceProvider)
          .focusAlertsEnabled;
      _hideNotificationTitles = hideTitles;
      _windowsSchedulingDegraded = degraded;
      _minimizeToTray = ref.read(windowServiceProvider).minimizeToTray;
      _quickCaptureEnabled = ref.read(quickCaptureServiceProvider).enabled;
    });
  }

  Future<void> _loadLaunchAtStartup() async {
    final service = ref.read(launchAtStartupServiceProvider);
    final enabled = await service.isEnabled();
    if (!mounted) return;
    setState(() {
      _launchAtLoginSupported = service.isSupported;
      _launchAtLogin = enabled;
    });
  }

  Future<void> _setLaunchAtLogin(bool enabled) async {
    try {
      final service = ref.read(launchAtStartupServiceProvider);
      final saved = await service.setEnabled(enabled);
      if (!mounted) return;
      if (!saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not change the Windows startup setting.'),
          ),
        );
        return;
      }
      setState(() => _launchAtLogin = enabled);
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not change the Windows startup setting.'),
        ),
      );
    }
  }

  Future<void> _loadBackupEncryption() async {
    try {
      final enabled = await ref.read(backupEncryptionServiceProvider).isEnabled;
      final includeAttachments =
          await ref
              .read(databaseProvider)
              .getSetting(AppDatabase.automaticBackupsIncludeAttachmentsKey) ==
          '1';
      if (mounted) {
        setState(() {
          _encryptAutomaticBackups = enabled;
          _includeAttachmentsInAutomaticBackups = includeAttachments;
        });
      }
    } catch (_) {
      // A credential-store failure leaves the switch off; backups still work
      // unencrypted and the user can retry.
    }
  }

  Future<void> _loadBackupStatus() async {
    try {
      final health = await ref.read(autoBackupServiceProvider).health();
      if (mounted) setState(() => _backupHealth = health);
    } catch (_) {
      // Backup status is advisory; the rest of Settings must stay usable.
    }
  }

  Future<void> _backUpNow() async {
    try {
      await ref.read(autoBackupServiceProvider).runNow();
      await _loadBackupStatus();
      if (mounted) _message('Backup created and verified.');
    } catch (error) {
      await _loadBackupStatus();
      if (mounted) {
        _message('Backup did not complete: $error');
      }
    }
  }

  String _backupStateLabel(BackupHealth health) => switch (health.state) {
    BackupHealthState.setupNeeded => 'Backup setup needed',
    BackupHealthState.due => 'Backup due',
    BackupHealthState.running => 'Backup running',
    BackupHealthState.verified => 'Backup verified',
    BackupHealthState.incompleteArchive => 'Incomplete archive',
    BackupHealthState.failed => 'Backup failed',
  };

  Future<String?> _askNewPassphrase({
    required String title,
    required String description,
  }) async {
    final passphrase = await showPassphrasePrompt(
      context,
      title: title,
      description: description,
      confirmLabel: 'Next',
    );
    if (passphrase == null || !mounted) return null;
    if (passphrase.trim().length <
        BackupEncryptionService.minPassphraseLength) {
      _message(
        'Use at least ${BackupEncryptionService.minPassphraseLength} '
        'characters for the passphrase.',
      );
      return null;
    }
    final confirmation = await showPassphrasePrompt(
      context,
      title: 'Confirm passphrase',
      description: 'Enter the same passphrase again.',
      confirmLabel: 'Continue',
    );
    if (confirmation == null || !mounted) return null;
    if (confirmation != passphrase) {
      _message('The passphrases do not match.');
      return null;
    }
    return passphrase;
  }

  Future<void> _exportEncryptedDiary() async {
    final passphrase = await _askNewPassphrase(
      title: 'Encrypt diary backup',
      description:
          'Choose a passphrase of at least '
          '${BackupEncryptionService.minPassphraseLength} characters. It is '
          'not stored anywhere and cannot be recovered; without it the backup '
          'stays unreadable.',
    );
    if (passphrase == null || !mounted) return;
    try {
      final saved = await runWithProgress(
        context,
        'Encrypting…',
        () => _external(
          () => ref
              .read(encryptedDiaryServiceProvider)
              .exportEncryptedDiary(passphrase),
        ),
      );
      if (!mounted) return;
      if (saved) _message('Encrypted diary backup exported.');
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not export the diary: $error');
    }
  }

  Future<void> _exportEncryptedBackup() async {
    final passphrase = await _askNewPassphrase(
      title: 'Encrypt full backup',
      description:
          'Protect projects, tasks, events, diaries and settings with one '
          'passphrase. It cannot be recovered if lost.',
    );
    if (passphrase == null || !mounted) return;
    try {
      final saved = await runWithProgress(
        context,
        'Encrypting…',
        () => _external(
          () => ref
              .read(dataExportServiceProvider)
              .exportFullDataAsEncryptedJson(passphrase),
        ),
      );
      if (!mounted) return;
      if (saved) _message('Encrypted backup exported.');
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not export the encrypted backup: $error');
    }
  }

  Future<void> _exportArchive() async {
    final passphrase = await _askNewPassphrase(
      title: 'Encrypt archive with attachments',
      description:
          'Protect the backup and every attached file with one passphrase. '
          'It cannot be recovered if lost.',
    );
    if (passphrase == null || !mounted) return;
    final path = await _external(
      () => FilePicker.platform.saveFile(
        dialogTitle: 'Export Locus Archive',
        fileName:
            'locus_archive_${DateFormat('yyyy-MM-dd').format(AppClock.now())}'
            '.locusarchive',
      ),
    );
    if (path == null || !mounted) return;
    try {
      final attachments = await ref.read(attachmentServiceProvider.future);
      if (!mounted) return;
      final built = await runWithProgress(
        context,
        'Encrypting archive…',
        () => LocusArchiveService().create(
          db: ref.read(databaseProvider),
          attachments: attachments,
          passphrase: passphrase,
          target: File(path),
        ),
      );
      if (!mounted) return;
      final missing = built.missingHashes.isEmpty
          ? ''
          : ', ${built.missingHashes.length} missing file(s) skipped';
      _message('Archive exported: ${built.blobCount} file(s)$missing.');
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not export the archive: $error');
    }
  }

  Future<void> _importArchive() async {
    final result = await _external(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['locusarchive'],
        dialogTitle: 'Open Locus Archive',
      ),
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.single.path;
    if (path == null) return;
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Open Locus Archive',
      description: 'Enter the passphrase used when this archive was exported.',
      confirmLabel: 'Open',
    );
    if (passphrase == null || !mounted) return;
    try {
      final attachments = await ref.read(attachmentServiceProvider.future);
      if (!mounted) return;
      final report = await runWithProgress(
        context,
        'Opening archive…',
        () => LocusArchiveService().restore(
          db: ref.read(databaseProvider),
          attachments: attachments,
          archive: File(path),
          passphrase: passphrase,
        ),
      );
      if (!mounted) return;
      final missing = report.missingHashes.isEmpty
          ? ''
          : ', ${report.missingHashes.length} file(s) were not in the archive';
      _message(
        'Archive imported: ${report.blobsWritten} file(s) restored$missing.',
      );
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not open the archive: $error');
    }
  }

  Future<void> _exportDiagnostics() async {
    final service = DiagnosticsService(
      ref.read(databaseProvider),
      nativeReminderStats: ref.read(nativeReminderStatsProvider),
    );
    try {
      final report = await runWithProgress(
        context,
        'Collecting diagnostics…',
        service.collect,
      );
      if (!mounted) return;
      final app = report['app'] as Map<String, dynamic>;
      final counts = report['counts'] as Map<String, int>;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export diagnostics?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version: ${app['version']}'),
                Text('Schema: ${report['database']['schema_version']}'),
                Text(
                  'Rows: ${counts['todo_items']} tasks, '
                  '${counts['events']} events, '
                  '${counts['diary_entries']} diary entries.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'The ZIP contains counts, versions, state codes, scrubbed '
                  'log lines and a content-free reminder buffer. It does not '
                  'contain titles, notes, diary text, tags, attachment names '
                  'or file names. Review diagnostics.json before sharing it.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save ZIP'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final saved = await _external(service.saveZip);
      if (!mounted) return;
      if (saved) _message('Diagnostics exported.');
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not export diagnostics: $error');
    }
  }

  Future<void> _emailDiagnostics() async {
    final service = DiagnosticsService(
      ref.read(databaseProvider),
      nativeReminderStats: ref.read(nativeReminderStatsProvider),
    );
    try {
      final saved = await _external(service.saveZip);
      if (!saved || !mounted) return;
      final opened = await launchUrl(
        Uri(
          scheme: 'mailto',
          path: AppLinks.supportEmail,
          queryParameters: {
            'subject': 'Locus diagnostics report',
            'body':
                'The diagnostics ZIP was just saved on this device. '
                'Attach that file to this email before sending it.\n\n'
                'It contains versions, counts, state codes and scrubbed logs. '
                'No titles, notes, diary text or attachment names were read.',
          },
        ),
      );
      if (!mounted) return;
      if (!opened) {
        await Clipboard.setData(ClipboardData(text: AppLinks.supportEmail));
        _message(
          'Diagnostics saved. No mail app opened; the support address '
          '${AppLinks.supportEmail} was copied. Attach the ZIP manually.',
        );
      }
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (!mounted) return;
      _message('Could not prepare the diagnostics report: $error');
    }
  }

  Future<void> _toggleIncludeAttachments(bool value) async {
    if (!_encryptAutomaticBackups) {
      _message('Enable encrypted automatic backups first.');
      return;
    }
    setState(() => _includeAttachmentsInAutomaticBackups = value);
    await ref
        .read(databaseProvider)
        .setSetting(
          AppDatabase.automaticBackupsIncludeAttachmentsKey,
          value ? '1' : '0',
        );
    if (!mounted) return;
    _message(
      value
          ? 'Automatic backups will include attachment bytes.'
          : 'Automatic backups will stay metadata-only.',
    );
  }

  Future<void> _toggleEncryptAutomaticBackups(bool value) async {
    final service = ref.read(backupEncryptionServiceProvider);
    if (!value) {
      await service.clear();
      if (!mounted) return;
      setState(() => _encryptAutomaticBackups = false);
      _message('Automatic backups are no longer encrypted.');
      return;
    }
    final passphrase = await _askNewPassphrase(
      title: 'Encrypt automatic backups',
      description:
          'Automatic and recovery backups will be .locusbackup files. The '
          'passphrase is kept in an operating-system-protected store so '
          'backups can run unattended; you will still type it when restoring.',
    );
    if (passphrase == null) return;
    try {
      await service.setPassphrase(passphrase);
      if (!mounted) return;
      setState(() => _encryptAutomaticBackups = true);
      _message('Automatic backups are encrypted.');
    } catch (error) {
      if (!mounted) return;
      _message('Could not save the backup passphrase: $error');
    }
  }

  Future<void> _deleteUnencryptedBackups() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete old unencrypted backups?'),
        content: const Text(
          'This removes only auto_*, manual_* and pre_import_* .json files. '
          'Encrypted .locusbackup files are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final count = await ref
          .read(dataExportServiceProvider)
          .deleteUnencryptedBackups();
      if (!mounted) return;
      _message(
        count == 0
            ? 'No unencrypted backups were found.'
            : 'Deleted $count unencrypted '
                  'backup${count == 1 ? '' : 's'}.',
      );
    } catch (error) {
      if (!mounted) return;
      _message('Could not delete the backups: $error');
    }
  }

  Future<bool> _confirmPlainExport() async {
    final db = ref.read(databaseProvider);
    final acknowledged = await db.getSetting(
      AppDatabase.plainBackupExportAcknowledgedSettingKey,
    );
    if (acknowledged == '1') return true;
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('The backup is not encrypted'),
        content: const Text(
          'This JSON file contains the diary and daily intentions in plain '
          'text. Anyone who can open the file can read them. Use “Export '
          'Encrypted Backup” if the file may leave this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Export anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await db.setSetting(
        AppDatabase.plainBackupExportAcknowledgedSettingKey,
        '1',
      );
      return true;
    }
    return false;
  }

  Future<void> _restoreEncryptedDiary() async {
    final service = ref.read(encryptedDiaryServiceProvider);
    String? document;
    try {
      document = await _external(service.pickEncryptedDiaryFile);
    } catch (error) {
      if (mounted) {
        _message(
          error is FormatException
              ? error.message
              : 'Could not read the diary backup.',
        );
      }
      return;
    }
    if (document == null || !mounted) return;
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Restore encrypted diary',
      description:
          'Enter the passphrase used when this backup was exported. Nothing '
          'is written until you review what will change.',
      confirmLabel: 'Next',
    );
    if (passphrase == null || !mounted) return;

    DiaryRestorePreview preview;
    try {
      preview = await runWithProgress(
        context,
        'Decrypting…',
        () => service.previewEncryptedRestore(
          document: document!,
          passphrase: passphrase,
        ),
      );
    } on FormatException catch (error) {
      if (mounted) _message(describeImportFailure(error));
      return;
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (mounted) _message('Could not read the diary backup: $error');
      return;
    }
    if (!mounted) return;
    if (preview.newCount == 0 && preview.conflictCount == 0) {
      _message(
        preview.identicalCount > 0
            ? 'Every day in that backup already matches your diary.'
            : 'No diary entries were found in that backup.',
      );
      return;
    }

    var policy = DiaryConflictPolicy.keepBoth;
    if (preview.hasConflicts) {
      final choice = await showDialog<DiaryConflictPolicy>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Review diary restore'),
          content: Text(
            '${preview.newCount} new, ${preview.identicalCount} identical, '
            '${preview.conflictCount} differ.\n\n'
            'Choose what to do with the days that differ.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, DiaryConflictPolicy.keepMine),
              child: const Text('Keep mine'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                DiaryConflictPolicy.replaceWithBackup,
              ),
              child: const Text('Replace with backup'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, DiaryConflictPolicy.keepBoth),
              child: const Text('Keep both'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      policy = choice;
    }
    if (!mounted) return;

    try {
      final report = await runWithProgress(
        context,
        'Restoring…',
        () => service.applyEncryptedRestore(preview, policy: policy),
      );
      if (!mounted) return;
      final parts = <String>[
        if (report.restored > 0)
          'restored ${report.restored} ${report.restored == 1 ? 'day' : 'days'}',
        if (report.identical > 0) '${report.identical} already identical',
        if (report.keptMine > 0) '${report.keptMine} kept as yours',
        if (report.skipped > 0) '${report.skipped} skipped',
      ];
      _message(
        parts.isEmpty
            ? 'No diary entries were changed.'
            : 'Diary restore: ${parts.join(', ')}.',
      );
    } on FormatException catch (error) {
      if (mounted) _message(describeImportFailure(error));
    } catch (error, stack) {
      await ErrorLogService.log(error, stack);
      if (mounted) _message('Could not restore the diary: $error');
    }
  }

  /// Runs a file picker or other OS activity without letting its lifecycle
  /// pauses trigger the app lock.
  Future<T> _external<T>(Future<T> Function() action) =>
      ref.read(appLockControllerProvider.notifier).runExternal(action);

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        await ref
            .read(databaseProvider)
            .setSetting(AppDatabase.syncRebaseRequiredSettingKey, '0');
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
    final landing = ref.watch(landingPageProvider);

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
            'Startup',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Start page'),
              subtitle: const Text(
                'Where Locus opens after launch. Keyboard shortcuts and the '
                'command palette still switch pages at any time.',
              ),
              trailing: landing.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : DropdownButton<LandingPage>(
                      value: landing.valueOrNull ?? LandingPage.dashboard,
                      onChanged: landing.hasError
                          ? null
                          : (page) async {
                              if (page == null) return;
                              try {
                                await ref
                                    .read(landingPageProvider.notifier)
                                    .setPage(page);
                              } catch (_) {
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Could not save the start page.',
                                    ),
                                  ),
                                );
                              }
                            },
                      items: [
                        for (final page in LandingPage.values)
                          DropdownMenuItem(
                            value: page,
                            child: Text(page.label),
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
                if (_launchAtLoginSupported)
                  SwitchListTile(
                    title: const Text('Start Locus when Windows starts'),
                    subtitle: const Text(
                      'Opens at sign-in so reminders and quick capture keep working.',
                    ),
                    value: _launchAtLogin,
                    onChanged: _setLaunchAtLogin,
                  ),
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
                    'Shown while Locus is running, including in the tray. '
                    'Anything due while it was closed appears in Today\'s '
                    'missed reminders, where you can snooze or dismiss it.',
                  ),
                  value: _eventRemindersEnabled,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(notificationServiceProvider)
                          .setEventRemindersEnabled(val);
                      var confirmed = <String>{};
                      if (Platform.isWindows) {
                        confirmed = await ref
                            .read(windowsReminderServiceProvider)
                            .reconcileStartup();
                      }
                      if (val) {
                        await ref
                            .read(eventRepositoryProvider)
                            .restoreFutureReminders(osConfirmedIds: confirmed);
                        await ref
                            .read(reminderInboxServiceProvider)
                            .rearmSnoozes();
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
                  title: const Text('Task Reminders'),
                  subtitle: const Text(
                    'Shown at the reminder time set on a to-do while Locus '
                    'is running. Completed tasks and past reminders are '
                    'not shown.',
                  ),
                  value: _taskRemindersEnabled,
                  onChanged: (val) async {
                    try {
                      await ref
                          .read(notificationServiceProvider)
                          .setTaskRemindersEnabled(val);
                      var confirmed = <String>{};
                      if (Platform.isWindows) {
                        confirmed = await ref
                            .read(windowsReminderServiceProvider)
                            .reconcileStartup();
                      }
                      if (val) {
                        await ref
                            .read(taskRepositoryProvider)
                            .restoreAllReminders(osConfirmedIds: confirmed);
                        await ref
                            .read(reminderInboxServiceProvider)
                            .rearmSnoozes();
                      }
                      if (mounted) setState(() => _taskRemindersEnabled = val);
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not update task reminders.'),
                          ),
                        );
                      }
                    }
                  },
                ),
                SwitchListTile(
                  title: const Text('Hide titles in Windows notifications'),
                  subtitle: const Text(
                    'Windows stores scheduled reminder text outside the '
                    'encrypted database and may show it on the lock screen. '
                    'This sends only a generic reminder to Windows.',
                  ),
                  value: _hideNotificationTitles,
                  onChanged: (val) async {
                    await ref
                        .read(databaseProvider)
                        .setSetting(
                          AppDatabase.hideNotificationTitlesSettingKey,
                          val ? '1' : '0',
                        );
                    await ref.read(windowsReminderServiceProvider).refresh();
                    if (mounted) {
                      setState(() => _hideNotificationTitles = val);
                    }
                  },
                ),
                if (Platform.isWindows && _windowsSchedulingDegraded)
                  ListTile(
                    leading: const Icon(Icons.warning_amber_outlined),
                    title: const Text('Some reminders could not be scheduled'),
                    subtitle: const Text(
                      'Windows rejected part of the reminder batch. Locus is '
                      'showing the missing reminders while it stays open.',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        await ref
                            .read(windowsReminderServiceProvider)
                            .refresh();
                        await _loadNotificationPreferences();
                      },
                      child: const Text('Retry'),
                    ),
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

          Card(
            child: ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Pin Locus to taskbar or Start'),
              subtitle: const Text(
                'Opens the Windows apps list. Right-click Locus and choose '
                'Pin to taskbar or Pin to Start.',
              ),
              trailing: const Icon(Icons.open_in_new),
              onTap: () async {
                try {
                  await Process.start('explorer.exe', ['shell:AppsFolder']);
                } catch (_) {
                  _message('Open Start, find Locus and right-click it to pin.');
                }
              },
            ),
          ),

          const SizedBox(height: 24),

          // ==================== SECURITY ====================
          const Text(
            'Security',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const AppLockSettingsCard(),
          const SizedBox(height: 8),
          const _DatabaseProtectionCard(),
          const SizedBox(height: 8),
          const _AttachmentsCard(),

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

          const CalendarFeedSettingsCard(),

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
                if (_backupHealth != null)
                  ListTile(
                    leading: Icon(
                      _backupHealth!.state == BackupHealthState.failed ||
                              _backupHealth!.state ==
                                  BackupHealthState.incompleteArchive
                          ? Icons.error_outline
                          : Icons.verified_outlined,
                      color:
                          _backupHealth!.state == BackupHealthState.failed ||
                              _backupHealth!.state ==
                                  BackupHealthState.incompleteArchive
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                    title: Text(_backupStateLabel(_backupHealth!)),
                    subtitle: Text(
                      [
                        if (_backupHealth!.lastVerified != null)
                          'Last verified '
                              '${DateFormat.yMMMd().add_jm().format(_backupHealth!.lastVerified!.toLocal())}'
                        else
                          'No verified backup yet',
                        if (_backupHealth!.nextDue != null)
                          'Next due '
                              '${DateFormat.yMMMd().add_jm().format(_backupHealth!.nextDue!.toLocal())}',
                        if (_backupHealth!.missingFiles > 0)
                          '${_backupHealth!.missingFiles} attachment file'
                              '${_backupHealth!.missingFiles == 1 ? '' : 's'} missing',
                        if (_backupHealth!.failureCode != null &&
                            _backupHealth!.failureCode!.isNotEmpty)
                          'Repair: ${_backupHealth!.failureCode}',
                        if (_backupHealth!.independentVerified != null)
                          'Independent copy verified '
                              '${DateFormat.yMMMd().add_jm().format(_backupHealth!.independentVerified!.toLocal())}',
                        if (_backupHealth!.independentFailure != null)
                          'Independent copy failed: '
                              '${_backupHealth!.independentFailure}',
                      ].join(' · '),
                    ),
                    trailing: TextButton(
                      onPressed: _backUpNow,
                      child: const Text('Back up now'),
                    ),
                  ),
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
                    'Not encrypted: the diary is readable in the file',
                  ),
                  onTap: () async {
                    if (!await _confirmPlainExport()) return;
                    if (!context.mounted) return;
                    final service = ref.read(dataExportServiceProvider);
                    try {
                      final success = await _external(
                        service.exportFullDataAsJson,
                      );
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
                  leading: const Icon(Icons.enhanced_encryption_outlined),
                  title: const Text('Export Encrypted Backup'),
                  subtitle: const Text(
                    'Everything in one .locusbackup file, protected by a passphrase',
                  ),
                  onTap: _exportEncryptedBackup,
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Export Archive with Attachments'),
                  subtitle: const Text(
                    'Everything plus the attachment bytes, in one encrypted '
                    '.locusarchive file',
                  ),
                  onTap: _exportArchive,
                ),
                ListTile(
                  leading: const Icon(Icons.unarchive_outlined),
                  title: const Text('Import Archive (.locusarchive)'),
                  subtitle: const Text(
                    'Restore data and attachment files from an encrypted archive',
                  ),
                  onTap: _importArchive,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.schedule_send_outlined),
                  title: const Text('Encrypt automatic backups'),
                  subtitle: const Text(
                    'Automatic and recovery backups use .locusbackup files. '
                    'The passphrase is kept in an operating-system-protected '
                    'store.',
                  ),
                  value: _encryptAutomaticBackups,
                  onChanged: _toggleEncryptAutomaticBackups,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.inventory_2_outlined),
                  title: const Text('Include attachments in automatic backups'),
                  subtitle: const Text(
                    'Uses the configured backup passphrase. Automatic archives '
                    'can become large; the seven newest are kept.',
                  ),
                  value: _includeAttachmentsInAutomaticBackups,
                  onChanged: _encryptAutomaticBackups
                      ? _toggleIncludeAttachments
                      : null,
                ),
                ListTile(
                  leading: const Icon(Icons.folder_shared_outlined),
                  title: const Text('Independent backup folder'),
                  subtitle: Text(
                    'A second verified copy for protection against losing this PC',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final selected = await FilePicker.platform.getDirectoryPath(
                      dialogTitle: 'Choose an independent backup folder',
                    );
                    if (selected == null) return;
                    await ref
                        .read(databaseProvider)
                        .setSetting(
                          AppDatabase.backupIndependentDirectoryKey,
                          selected,
                        );
                    await _backUpNow();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Delete old unencrypted backups'),
                  subtitle: const Text(
                    'Removes old auto_*, manual_* and pre_import_* .json files',
                  ),
                  onTap: _deleteUnencryptedBackups,
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
                      final success = await _external(
                        service.exportEventsAsIcs,
                      );
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
                  leading: const Icon(Icons.event_available),
                  title: const Text('Import Events from ICS'),
                  subtitle: const Text(
                    'Add events from Outlook, Google Calendar or Apple Calendar',
                  ),
                  onTap: () async {
                    final service = ref.read(dataExportServiceProvider);
                    try {
                      final preview = await _external(
                        service.previewEventsFromIcs,
                      );
                      if (preview == null || !context.mounted) return;
                      if (preview.eventCount == 0) {
                        _message('No events were found in the calendar file.');
                        return;
                      }

                      final simplified = preview.simplifiedSeries;
                      final summary =
                          '${preview.eventCount} event'
                          '${preview.eventCount == 1 ? '' : 's'}, '
                          '${simplified.length} recurring series cannot be '
                          'represented exactly, ${preview.allDayCount} all-day, '
                          '${preview.timezoneFallbacks} with an unknown time '
                          'zone.';
                      final keepSimplified = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Import calendar events'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(summary),
                                if (simplified.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  const Text('Simplified series:'),
                                  const SizedBox(height: 4),
                                  Text(
                                    simplified.take(8).join(', '),
                                    style: const TextStyle(
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  if (simplified.length > 8)
                                    Text('and ${simplified.length - 8} more…'),
                                ],
                                if (preview.overrideCount > 0) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    '${preview.overrideCount} modified '
                                    'occurrence${preview.overrideCount == 1 ? '' : 's'} '
                                    'will be imported as separate events.',
                                  ),
                                ],
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancel'),
                            ),
                            if (simplified.isNotEmpty)
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text(
                                  'Import without those series',
                                ),
                              ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Import'),
                            ),
                          ],
                        ),
                      );
                      if (keepSimplified == null || !context.mounted) return;

                      final report = await _external(
                        () => service.importIcs(
                          preview,
                          keepSimplified: keepSimplified,
                        ),
                      );
                      if (!context.mounted) return;

                      if (report.total > 0) {
                        await ref
                            .read(eventRepositoryProvider)
                            .restoreFutureReminders();
                      }
                      if (!context.mounted) return;
                      final parts = <String>[
                        if (report.imported > 0) '${report.imported} new',
                        if (report.updated > 0) '${report.updated} updated',
                        if (report.simplifiedSkipped > 0)
                          '${report.simplifiedSkipped} simplified '
                              'series skipped',
                        if (report.overridesImported > 0)
                          '${report.overridesImported} modified '
                              'occurrences',
                        if (report.skipped > 0)
                          '${report.skipped} invalid '
                              '${report.skipped == 1 ? 'entry' : 'entries'} '
                              'skipped',
                        if (report.attachmentsIgnored > 0)
                          '${report.attachmentsIgnored} attachment'
                              '${report.attachmentsIgnored == 1 ? '' : 's'} '
                              'ignored',
                      ];
                      _message(
                        parts.isEmpty
                            ? 'No events were imported.'
                            : 'Calendar import: ${parts.join(', ')}.',
                      );
                    } catch (error, stack) {
                      await ErrorLogService.log(error, stack);
                      if (!context.mounted) return;
                      final detail = error is FormatException
                          ? ' Import failed: ${error.message}'
                          : '';
                      _message('Could not import the calendar file.$detail');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('Import Todoist CSV'),
                  subtitle: const Text(
                    'Preview an exported project, choose a destination and keep '
                    'receipts so a rerun does not duplicate tasks',
                  ),
                  onTap: () => TodoistImportDialog.show(context),
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Export Diary (Encrypted)'),
                  subtitle: const Text(
                    'Password-protected backup of diary entries only, using AES-256-GCM',
                  ),
                  onTap: _exportEncryptedDiary,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_open_outlined),
                  title: const Text('Restore Diary (Encrypted)'),
                  subtitle: const Text(
                    'Add or update diary entries from an encrypted backup',
                  ),
                  onTap: _restoreEncryptedDiary,
                ),
                ListTile(
                  leading: const Icon(Icons.upload),
                  title: const Text('Import Data (JSON or .locusbackup)'),
                  subtitle: const Text(
                    'Review the backup contents before importing; encrypted '
                    'files ask for their passphrase',
                  ),
                  onTap: () async {
                    final service = ref.read(dataExportServiceProvider);
                    BackupSummary? summary;
                    Future<String?> prompt(String message) =>
                        showPassphrasePrompt(
                          context,
                          title: 'Encrypted backup',
                          description: message,
                          confirmLabel: 'Open',
                        );
                    try {
                      summary = await _external(
                        () => service.inspectSelectedBackup(prompt: prompt),
                      );
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
                      success = await _external(
                        () => service.importFullDataFromJson(
                          replaceEverything: replaceEverything,
                          prompt: prompt,
                        ),
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
                          _taskRemindersEnabled =
                              notifications.taskRemindersEnabled;
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
                      await ref
                          .read(taskRepositoryProvider)
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

          // ==================== HELP ====================
          const Text(
            'Help',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Export diagnostics'),
                  subtitle: const Text(
                    'A local, scrubbed ZIP with versions, counts and logs. '
                    'No titles, notes, diary text or file names.',
                  ),
                  onTap: _exportDiagnostics,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Send diagnostics by email'),
                  subtitle: const Text(
                    'Save the ZIP, then open a pre-addressed email draft',
                  ),
                  onTap: _emailDiagnostics,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text('Troubleshooting'),
                  subtitle: const Text(
                    'Pairing, firewall, notification and battery guidance',
                  ),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Troubleshooting'),
                      content: const SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sync cannot find the desktop',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Keep Locus running on the desktop, put both '
                              'devices on the same Wi-Fi, and allow Locus '
                              'through the firewall on that network profile. '
                              'If discovery is blocked, enter the desktop IP '
                              'and port shown in Device Sync.',
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Reminders do not appear',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Allow notifications and exact alarms for Locus. '
                              'On Android, exclude Locus from aggressive '
                              'battery optimisation; the exact path differs by '
                              'manufacturer.',
                            ),
                            SizedBox(height: 12),
                            Text(
                              'Attachments',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Names and metadata sync as ordinary rows. File '
                              'bytes transfer during a sync; the phone policy '
                              'in Security > Attachments controls automatic '
                              'downloads.',
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
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
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Locus Planner'),
                  subtitle: Text(
                    'Version $_version • Local-first productivity app',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Open-source licences'),
                  subtitle: const Text(
                    'Flutter packages and bundled SQLite3MultipleCiphers',
                  ),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Locus Planner',
                    applicationVersion: _version,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Local attachment policy.
///
/// Files are stored encrypted on this device only. The switch below controls
/// whether imported images keep their original pixels (which also keeps EXIF)
/// or are downscaled and re-encoded, which strips EXIF including GPS.
class _AttachmentsCard extends ConsumerStatefulWidget {
  const _AttachmentsCard();

  @override
  ConsumerState<_AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends ConsumerState<_AttachmentsCard> {
  bool _keepOriginal = false;
  String _downloadPolicy = AttachmentRules.downloadPolicyAuto;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final keep = await db.getSetting(AttachmentRules.keepOriginalSettingKey);
    final policy = await db.getSetting(
      AttachmentRules.downloadPolicySettingKey,
    );
    if (!mounted) return;
    setState(() {
      _keepOriginal = keep == '1';
      _downloadPolicy =
          policy == AttachmentRules.downloadPolicyAll ||
              policy == AttachmentRules.downloadPolicyManual
          ? policy!
          : AttachmentRules.downloadPolicyAuto;
      _loaded = true;
    });
  }

  Future<void> _setKeepOriginal(bool enabled) async {
    setState(() => _keepOriginal = enabled);
    await ref
        .read(databaseProvider)
        .setSetting(
          AttachmentRules.keepOriginalSettingKey,
          enabled ? '1' : '0',
        );
  }

  Future<void> _setDownloadPolicy(String value) async {
    setState(() => _downloadPolicy = value);
    await ref
        .read(databaseProvider)
        .setSetting(AttachmentRules.downloadPolicySettingKey, value);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.attach_file),
            title: Text('Attachments'),
            subtitle: Text(
              'Files and images are stored encrypted on this device. Their '
              'names and metadata sync to a paired desktop; the bytes do not '
              'leave this device in this version.',
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.high_quality_outlined),
            title: const Text('Keep original images'),
            subtitle: const Text(
              'Off by default: long edges above ${AttachmentRules.maxLongEdge} '
              'px are downscaled, EXIF including GPS is stripped, and a '
              'thumbnail is generated. Turn this on to keep the original '
              'pixels (EXIF is preserved).',
            ),
            value: _keepOriginal,
            onChanged: _loaded ? _setKeepOriginal : null,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Download attachments on the phone'),
            subtitle: const Text(
              'Auto downloads files and images up to 2 MB; All downloads '
              'everything; Manual leaves a download button on each tile.',
            ),
            trailing: DropdownButton<String>(
              value: _downloadPolicy,
              onChanged: _loaded
                  ? (value) {
                      if (value != null) _setDownloadPolicy(value);
                    }
                  : null,
              items: const [
                DropdownMenuItem(
                  value: AttachmentRules.downloadPolicyAuto,
                  child: Text('Auto'),
                ),
                DropdownMenuItem(
                  value: AttachmentRules.downloadPolicyAll,
                  child: Text('All'),
                ),
                DropdownMenuItem(
                  value: AttachmentRules.downloadPolicyManual,
                  child: Text('Manual'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.straighten),
            title: Text('Limits'),
            subtitle: Text(
              'Up to ${AttachmentRules.maxPerItem} attachments per item, '
              '${AttachmentRules.maxFileBytes ~/ (1024 * 1024)} MB each. '
              'The app warns above '
              '${AttachmentRules.softQuotaBytes ~/ (1024 * 1024 * 1024)} GB '
              'of local attachment storage.',
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only summary of where sensitive state lives and whether live database
/// encryption is active. Enabling it is deliberately not offered here: live
/// encryption and automatic conversion are deployment switches, not user
/// actions.
class _DatabaseProtectionCard extends StatelessWidget {
  const _DatabaseProtectionCard();

  @override
  Widget build(BuildContext context) {
    final encrypted = DatabaseSecurity.actualEncryptionEnabled;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              encrypted ? Icons.lock_outline : Icons.lock_open_outlined,
            ),
            title: const Text('Database encryption'),
            subtitle: Text(
              encrypted
                  ? 'On. Cipher profile: '
                        '${DatabaseSecurity.profile.profileId}.'
                  : 'Off. The database is a standard SQLite file. Live '
                        'encryption and automatic conversion are enabled only '
                        'by deployment configuration after release '
                        'validation.',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Sensitive data location'),
            subtitle: Text(
              Platform.isWindows
                  ? r'%LOCALAPPDATA%\LocusPlanner (does not roam)'
                  : 'The app-private application-support directory',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('Android backup rules'),
            subtitle: const Text(
              'The database, key metadata, migration journal and local '
              'backups are excluded from cloud backup and device transfer.',
            ),
          ),
          if (encrypted) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: const Text('Create recovery key'),
              subtitle: const Text(
                'Write a passphrase-protected recovery file now. Without it, '
                'reinstalling Windows or resetting the profile can make the '
                'encrypted database unreadable.',
              ),
              onTap: () => _createRecoveryKey(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Create recovery package'),
              subtitle: const Text(
                'Save the encrypted database, its identity, the recovery '
                'envelope and optional attachment files in one verified '
                '.locusrecovery file.',
              ),
              onTap: () => _createRecoveryPackage(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Verify recovery package'),
              subtitle: const Text(
                'Check the envelope, database identity, checksums and '
                'attachment contents without changing anything.',
              ),
              onTap: () => _verifyRecoveryPackage(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restore_outlined),
              title: const Text('Restore raw database package'),
              subtitle: const Text(
                'Stage a .locusrecovery package and replace the database at '
                'the next restart. The current files are quarantined first.',
              ),
              onTap: () => _restoreRecoveryPackage(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Restore logical backup as new database'),
              subtitle: const Text(
                'Import a JSON or .locusbackup file into a fresh encrypted '
                'database with a new identity. Devices must re-pair afterwards.',
              ),
              onTap: () => _restoreLogicalBackup(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('View database identity'),
              subtitle: const Text(
                'Database, key, generation and cipher profile for support.',
              ),
              onTap: () => _showDatabaseIdentity(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change recovery passphrase'),
              subtitle: const Text(
                'Rewrap the managed recovery key with a new passphrase. The '
                'database key is not rotated.',
              ),
              onTap: () => _changeRecoveryPassphrase(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('Start fresh'),
              subtitle: const Text(
                'Quarantine the current database and create a new identity at '
                'the next restart. Old key records are preserved.',
              ),
              onTap: () => _startFresh(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.inventory_outlined),
              title: const Text('Review old artifacts'),
              subtitle: const Text(
                'Inspect quarantined databases, backups and attachment files '
                'and delete them only when you are sure.',
              ),
              onTap: () => _reviewArtifacts(context),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Review plaintext artifacts'),
              subtitle: const Text(
                'Find the legacy Documents database and any pre-encryption '
                'plaintext backups. Delete them only after verifying the '
                'encrypted database.',
              ),
              onTap: () => _reviewPlaintextArtifacts(context),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createRecoveryKey(BuildContext context) async {
    final keyStore = DatabaseSecurity.keyStore;
    if (keyStore == null) {
      _message(context, 'The database key store is not available.');
      return;
    }
    final versions = await keyStore.listVersions();
    if (!context.mounted) return;
    if (versions.isEmpty) {
      _message(context, 'No database key was found.');
      return;
    }
    final active = versions.firstWhere(
      (record) => record.active,
      orElse: () => versions.last,
    );
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Recovery passphrase',
      description:
          'Choose at least '
          '${BackupEncryptionService.minPassphraseLength} characters. This '
          'passphrase is not stored; without it the recovery file is useless.',
      confirmLabel: 'Continue',
    );
    if (passphrase == null ||
        passphrase.trim().length <
            BackupEncryptionService.minPassphraseLength) {
      return;
    }
    final backupPassphrase = await BackupEncryptionService().read();
    if (!context.mounted) return;
    try {
      final attachmentKey = await SecureAttachmentKeyStore().read();
      final bundle = await RecoveryEnvelopeService.seal(
        dek: active.bytes,
        databaseId: active.databaseId,
        keyId: active.keyId,
        keyGeneration: active.generation,
        cipherProfileId: active.cipherProfileId,
        passphrase: passphrase,
        backupPassphrase: backupPassphrase,
        attachmentKey: attachmentKey,
      );
      await RecoveryEnvelopeService.verify(
        bundle: bundle,
        passphrase: passphrase,
        expectedDek: active.bytes,
      );
      try {
        final paths =
            DatabaseRuntimeContext.current?.paths ??
            await DatabasePathsResolver.resolve();
        await RecoveryEnvelopeStore(
          paths.recoveryEnvelopesDirectory,
        ).write(bundle, retireExisting: true);
      } catch (_) {
        // The exported file is still valid; the managed copy is an extra
        // convenience for the passphrase-change action.
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Locus recovery key',
        fileName:
            'locus_recovery_${DateFormat('yyyy-MM-dd').format(AppClock.now())}'
            '.json',
      );
      if (path == null) return;
      await File(path).writeAsString(bundle.encode(), flush: true);
      if (context.mounted) {
        _message(
          context,
          'Recovery key saved. Keep it somewhere separate from the database.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not create the recovery key: $error');
      }
    }
  }

  Future<
    ({
      DatabasePaths paths,
      DatabaseMetadata metadata,
      DatabaseKeyRecord active,
    })?
  >
  _recoveryData(BuildContext context) async {
    final keyStore = DatabaseSecurity.keyStore;
    if (keyStore == null) {
      _message(context, 'The database key store is not available.');
      return null;
    }
    final paths =
        DatabaseRuntimeContext.current?.paths ??
        await DatabasePathsResolver.resolve();
    final metadata = await DatabaseMetadataStore(paths.metadataFile).read();
    if (!context.mounted) return null;
    if (metadata == null) {
      _message(context, 'The database identity metadata is missing.');
      return null;
    }
    DatabaseKeyRecord? active;
    for (final record in await keyStore.listVersions()) {
      if (record.keyId == metadata.activeKeyId) active = record;
    }
    if (!context.mounted) return null;
    if (active == null) {
      _message(context, 'The active database key is unavailable.');
      return null;
    }
    return (paths: paths, metadata: metadata, active: active);
  }

  Future<String?> _askNewPassphrase(BuildContext context) async {
    final first = await showPassphrasePrompt(
      context,
      title: 'Recovery passphrase',
      description:
          'Use at least ${RecoveryPackageService.minPassphraseLength} '
          'characters. This passphrase is not stored; the package is useless '
          'without it.',
      confirmLabel: 'Continue',
    );
    if (first == null) return null;
    if (!context.mounted) return null;
    if (first.trim().length < RecoveryPackageService.minPassphraseLength) {
      _message(
        context,
        'Use at least ${RecoveryPackageService.minPassphraseLength} '
        'characters.',
      );
      return null;
    }
    if (!context.mounted) return null;
    final second = await showPassphrasePrompt(
      context,
      title: 'Confirm recovery passphrase',
      description: 'Enter the same passphrase again.',
      confirmLabel: 'Create',
    );
    if (second == null) return null;
    if (!context.mounted) return null;
    if (second != first) {
      _message(context, 'The passphrases do not match.');
      return null;
    }
    return first;
  }

  Future<void> _createRecoveryPackage(BuildContext context) async {
    final data = await _recoveryData(context);
    if (data == null || !context.mounted) return;
    final passphrase = await _askNewPassphrase(context);
    if (passphrase == null || !context.mounted) return;
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Locus recovery package',
      fileName:
          'locus_recovery_'
          '${DateFormat('yyyy-MM-dd').format(AppClock.now())}'
          '.${RecoveryPackageService.extension}',
      type: FileType.custom,
      allowedExtensions: [RecoveryPackageService.extension],
    );
    if (path == null || !context.mounted) return;
    try {
      final result = await runWithProgress(
        context,
        'Creating and verifying the recovery package...',
        () => const RecoveryPackageService().create(
          paths: data.paths,
          metadata: data.metadata,
          dek: data.active.bytes,
          passphrase: passphrase,
          target: File(path),
          attachmentKeyStore: SecureAttachmentKeyStore(),
        ),
      );
      if (!context.mounted) return;
      final skipped = result.manifest.skippedAttachmentCount;
      _message(
        context,
        'Recovery package created and verified: '
        '${result.manifest.attachmentFileCount} attachment files, '
        '${_formatSize(result.archiveBytes)}.'
        '${skipped == 0 ? '' : ' $skipped attachment files were missing and '
                  'were not included.'}',
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not create the recovery package: $error');
      }
    }
  }

  Future<void> _verifyRecoveryPackage(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [RecoveryPackageService.extension],
      dialogTitle: 'Select a Locus recovery package',
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Recovery passphrase',
      description: 'Enter the passphrase used when this package was created.',
      confirmLabel: 'Verify',
    );
    if (passphrase == null || !context.mounted) return;
    try {
      final manifest = await runWithProgress(
        context,
        'Verifying the recovery package...',
        () => const RecoveryPackageService().verify(
          archive: File(path),
          passphrase: passphrase,
        ),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recovery package verified'),
          content: Text(
            'Database: ${manifest.databaseId}\n'
            'Created: ${DateFormat.yMMMd().add_Hm().format(manifest.createdAt.toLocal())}\n'
            'Schema: ${manifest.schemaVersion}\n'
            'Attachment files: ${manifest.attachmentFileCount}'
            '${manifest.skippedAttachmentCount == 0 ? '' : '\nSkipped at creation: ${manifest.skippedAttachmentCount}'}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Verification failed: $error');
      }
    }
  }

  Future<void> _restoreRecoveryPackage(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [RecoveryPackageService.extension],
      dialogTitle: 'Select a Locus recovery package',
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Recovery passphrase',
      description:
          'Enter the passphrase for this package. It is used once to unwrap '
          'the database key and is not stored.',
      confirmLabel: 'Continue',
    );
    if (passphrase == null || !context.mounted) return;
    try {
      final manifest = await runWithProgress(
        context,
        'Verifying the recovery package...',
        () => const RecoveryPackageService().verify(
          archive: File(path),
          passphrase: passphrase,
        ),
      );
      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Replace this database?'),
          content: Text(
            'The package contains the database '
            '${manifest.databaseId}, created '
            '${DateFormat.yMMMd().add_Hm().format(manifest.createdAt.toLocal())}'
            ', with ${manifest.attachmentFileCount} attachment files.\n\n'
            'The current database and key material will be moved to '
            'quarantine. Locus must restart to finish the restore.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stage restore'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      final keyStore = DatabaseSecurity.keyStore;
      if (keyStore == null) {
        _message(context, 'The database key store is not available.');
        return;
      }
      final paths =
          DatabaseRuntimeContext.current?.paths ??
          await DatabasePathsResolver.resolve();
      if (!context.mounted) return;
      await runWithProgress(
        context,
        'Staging the database restore...',
        () => const RecoveryRestoreService().stage(
          paths: paths,
          package: File(path),
          passphrase: passphrase,
          keyStore: keyStore,
          attachmentKeyStore: SecureAttachmentKeyStore(),
        ),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore staged'),
          content: const Text(
            'Close Locus and start it again to finish the restore. The '
            'previous database remains in quarantine until you review it.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (Platform.isAndroid) {
                  SystemNavigator.pop();
                } else {
                  exit(0);
                }
              },
              child: const Text('Close Locus'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not stage the restore: $error');
      }
    }
  }

  Future<void> _restoreLogicalBackup(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'locusbackup'],
      dialogTitle: 'Select a Locus logical backup',
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    String? passphrase;
    try {
      final raw = await File(path).readAsString();
      if (EncryptedEnvelope.looksEncrypted(raw)) {
        if (!context.mounted) return;
        passphrase = await showPassphrasePrompt(
          context,
          title: 'Backup passphrase',
          description:
              'Enter the passphrase for this encrypted backup. It is used '
              'once during the import and is not stored.',
          confirmLabel: 'Continue',
        );
        if (passphrase == null || !context.mounted) return;
      }
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not read the backup: $error');
      }
      return;
    }

    if (!context.mounted) return;
    final keyStore = DatabaseSecurity.keyStore;
    if (keyStore == null) {
      _message(context, 'The database key store is not available.');
      return;
    }
    final paths =
        DatabaseRuntimeContext.current?.paths ??
        await DatabasePathsResolver.resolve();
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create a new installation?'),
        content: const Text(
          'The backup is imported into a new encrypted database with a new '
          'database identity, key and device identity. The current database '
          'is quarantined. Local attachment files are kept, but devices will '
          'need to pair again after the restart.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Stage restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final result = await runWithProgress(
        context,
        'Building a new database from the backup...',
        () => const LogicalRestoreService().stage(
          paths: paths,
          backup: File(path),
          passphrase: passphrase,
          keyStore: keyStore,
          attachmentKeyStore: SecureAttachmentKeyStore(),
        ),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Logical restore staged'),
          content: Text(
            '${result.report.isClean ? 'All rows were imported' : result.report.summary}'
            ' into a new database. Close Locus and start it again to use it. '
            'Devices must re-pair because the sync identity changed.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (Platform.isAndroid) {
                  SystemNavigator.pop();
                } else {
                  exit(0);
                }
              },
              child: const Text('Close Locus'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not stage the logical restore: $error');
      }
    }
  }

  Future<void> _showDatabaseIdentity(BuildContext context) async {
    final data = await _recoveryData(context);
    if (data == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Database identity'),
        content: SelectableText(
          'Database: ${data.metadata.databaseId}\n'
          'Key: ${data.metadata.activeKeyId}\n'
          'Generation: ${data.metadata.keyGeneration}\n'
          'Cipher profile: ${data.metadata.cipherProfileId}\n'
          'Encryption: '
          '${data.metadata.encryptionEnabled ? 'on' : 'off'}\n'
          'Data directory: ${data.paths.dataDirectory.path}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRecoveryPassphrase(BuildContext context) async {
    final data = await _recoveryData(context);
    if (data == null || !context.mounted) return;
    final store = RecoveryEnvelopeStore(data.paths.recoveryEnvelopesDirectory);
    final current = await store.current();
    if (!context.mounted) return;
    if (current == null) {
      _message(
        context,
        'No managed recovery key was found. Create a recovery key first.',
      );
      return;
    }
    if (!current.isCurrentFor(data.metadata)) {
      _message(
        context,
        'The managed recovery key belongs to an older database identity. '
        'Create a new recovery key for this database.',
      );
      return;
    }
    final oldPassphrase = await showPassphrasePrompt(
      context,
      title: 'Current recovery passphrase',
      description: 'Enter the passphrase for the managed recovery key.',
      confirmLabel: 'Continue',
    );
    if (oldPassphrase == null || !context.mounted) return;
    final newPassphrase = await _askNewPassphrase(context);
    if (newPassphrase == null || !context.mounted) return;
    try {
      await runWithProgress(
        context,
        'Rewrapping the recovery key...',
        () => store.changePassphrase(
          oldPassphrase: oldPassphrase,
          newPassphrase: newPassphrase,
          attachmentKeyStore: SecureAttachmentKeyStore(),
        ),
      );
      if (context.mounted) {
        _message(
          context,
          'Recovery passphrase changed. The previous envelope was retired, not '
          'deleted.',
        );
      }
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not change the passphrase: $error');
      }
    }
  }

  Future<void> _startFresh(BuildContext context) async {
    final paths =
        DatabaseRuntimeContext.current?.paths ??
        await DatabasePathsResolver.resolve();
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start with a new database?'),
        content: const Text(
          'At the next restart, Locus will move the current database, its '
          'metadata, journals and attachment files to quarantine and create a '
          'brand-new identity and key.\n\n'
          'Old key records and recovery envelopes are preserved. You can '
          'review or delete the quarantined files only from Review old '
          'artifacts. This cannot be undone from inside the new database.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Start fresh'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await runWithProgress(
        context,
        'Preparing the start-fresh request...',
        () => const StartFreshService().request(paths: paths),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Start fresh staged'),
          content: const Text(
            'Close Locus and start it again. The current data will be moved '
            'to quarantine and a new database will be created.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                if (Platform.isAndroid) {
                  SystemNavigator.pop();
                } else {
                  exit(0);
                }
              },
              child: const Text('Close Locus'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (context.mounted) {
        _message(context, 'Could not prepare a fresh start: $error');
      }
    }
  }

  Future<void> _reviewArtifacts(BuildContext context) async {
    final paths =
        DatabaseRuntimeContext.current?.paths ??
        await DatabasePathsResolver.resolve();
    if (!context.mounted) return;
    var artifacts = await const QuarantineService().list(paths);
    if (!context.mounted) return;
    if (artifacts.isEmpty) {
      _message(context, 'No quarantined artifacts were found.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Quarantined artifacts'),
          content: SizedBox(
            width: 520,
            child: artifacts.isEmpty
                ? const Text('Nothing remains in quarantine.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final artifact in artifacts)
                        ListTile(
                          title: Text(artifact.name),
                          subtitle: Text(
                            '${_formatSize(artifact.bytes)} - '
                            '${DateFormat.yMMMd().add_Hm().format(artifact.modifiedAt.toLocal())}',
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete permanently',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text('Delete this artifact?'),
                                  content: Text(
                                    '${artifact.name} will be deleted '
                                    'permanently. This may remove the only '
                                    'remaining copy of old data.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              try {
                                await const QuarantineService().delete(
                                  paths,
                                  artifact.path,
                                );
                                artifacts = await const QuarantineService()
                                    .list(paths);
                                setDialogState(() {});
                              } catch (error) {
                                if (dialogContext.mounted) {
                                  _message(
                                    dialogContext,
                                    'Could not delete the artifact: $error',
                                  );
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reviewPlaintextArtifacts(BuildContext context) async {
    final paths =
        DatabaseRuntimeContext.current?.paths ??
        await DatabasePathsResolver.resolve();
    if (!context.mounted) return;
    var artifacts = await const PlaintextArtifactService().list(paths);
    if (!context.mounted) return;
    if (artifacts.isEmpty) {
      _message(context, 'No plaintext database artifacts were found.');
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Plaintext database artifacts'),
          content: SizedBox(
            width: 560,
            child: artifacts.isEmpty
                ? const Text('No plaintext artifacts remain.')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final artifact in artifacts)
                        ListTile(
                          title: Text(artifact.label),
                          subtitle: Text(
                            '${artifact.path}\n'
                            '${_formatSize(artifact.bytes)} - '
                            '${DateFormat.yMMMd().add_Hm().format(artifact.modifiedAt.toLocal())}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: 'Delete plaintext copy',
                            icon: const Icon(Icons.delete_forever_outlined),
                            onPressed: () async {
                              final confirmed = await showDialog<bool>(
                                context: dialogContext,
                                builder: (confirmContext) => AlertDialog(
                                  title: const Text(
                                    'Delete this plaintext copy?',
                                  ),
                                  content: const Text(
                                    'This is an unencrypted copy of planner '
                                    'data. Delete it only after the encrypted '
                                    'database opens correctly and you have a '
                                    'verified recovery package. This cannot '
                                    'be undone.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(confirmContext, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed != true) return;
                              try {
                                await const PlaintextArtifactService().delete(
                                  paths,
                                  artifact,
                                );
                                artifacts =
                                    await const PlaintextArtifactService().list(
                                      paths,
                                    );
                                setDialogState(() {});
                              } catch (error) {
                                if (dialogContext.mounted) {
                                  _message(
                                    dialogContext,
                                    'Could not delete the copy: $error',
                                  );
                                }
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes bytes';
  }

  static void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
