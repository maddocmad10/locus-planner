import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/security/database_security_options.dart';
import '../../../core/services/backup_encryption_service.dart';
import '../../../core/widgets/secret_prompt.dart';

/// First-run backup setup. "Later" keeps a visible repair action on Today.
class BackupSetupCard extends ConsumerStatefulWidget {
  const BackupSetupCard({super.key});

  @override
  ConsumerState<BackupSetupCard> createState() => _BackupSetupCardState();
}

class _BackupSetupCardState extends ConsumerState<BackupSetupCard> {
  bool? _configured;
  bool _later = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await ref.read(backupEncryptionServiceProvider).isEnabled;
    final later =
        await ref
            .read(databaseProvider)
            .getSetting(AppDatabase.backupSetupLaterKey) ==
        '1';
    if (mounted) {
      setState(() {
        _configured = enabled;
        _later = later;
      });
    }
  }

  Future<void> _setUp() async {
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Back up this planner',
      description:
          'Choose a passphrase for automatic encrypted backups. It is stored '
          'in the operating-system-protected store, not in the database.',
      confirmLabel: 'Next',
    );
    if (passphrase == null || !mounted) return;
    if (passphrase.trim().length <
        BackupEncryptionService.minPassphraseLength) {
      _message(
        'Use at least ${BackupEncryptionService.minPassphraseLength} characters.',
      );
      return;
    }
    final confirmation = await showPassphrasePrompt(
      context,
      title: 'Confirm passphrase',
      description: 'Enter the same passphrase again.',
      confirmLabel: 'Continue',
    );
    if (confirmation == null || !mounted) return;
    if (confirmation != passphrase) {
      _message('The passphrases do not match.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(backupEncryptionServiceProvider).setPassphrase(passphrase);
      await ref
          .read(databaseProvider)
          .setSetting(AppDatabase.backupSetupLaterKey, '0');
      await ref.read(autoBackupServiceProvider).runNow();
      await _load();
      if (mounted) {
        _message('Backups are set up and the first copy is verified.');
      }
    } catch (error) {
      if (mounted) _message('Could not set up backups: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _laterPressed() async {
    await ref
        .read(databaseProvider)
        .setSetting(AppDatabase.backupSetupLaterKey, '1');
    if (mounted) setState(() => _later = true);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (!DatabaseSecurity.backupsMustBeEncrypted) {
      return const SizedBox.shrink();
    }
    if (_configured == null || _configured == true) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    if (_later) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.backup_outlined, color: theme.colorScheme.error),
          title: const Text('Backup setup needed'),
          subtitle: const Text(
            'Your planner is not backed up automatically yet.',
          ),
          trailing: TextButton(
            onPressed: _saving ? null : _setUp,
            child: const Text('Set up'),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.backup_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Set up backups',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'A new encrypted installation needs a backup passphrase so Locus '
              'can save an unattended, verified copy. You can choose an '
              'independent folder later.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _saving ? null : _setUp,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline),
                  label: const Text('Set up backups'),
                ),
                TextButton(
                  onPressed: _saving ? null : _laterPressed,
                  child: const Text('Later'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
