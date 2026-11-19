import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/attachments/attachment_key_store.dart';
import '../widgets/secret_prompt.dart';
import 'database_bootstrap.dart';
import 'database_paths.dart';
import 'database_security_errors.dart';
import 'database_security_options.dart';
import 'recovery_envelope.dart';
import 'recovery_package_service.dart';
import 'recovery_restore_service.dart';

/// Opens the startup recovery flow for a missing/unreadable database key.
///
/// The user selects a recovery JSON file and enters its passphrase. The flow
/// imports the recovered DEK, rotates the database key so the old recovery
/// bundle cannot be reused, and asks the user to restart Locus.
class StartupRecoveryButton extends StatelessWidget {
  const StartupRecoveryButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!_isRecoverable()) return const SizedBox.shrink();
    final button = OutlinedButton.icon(
      onPressed: () => _recover(context),
      icon: const Icon(Icons.key_outlined),
      label: const Text('Recover from key file'),
    );
    return compact
        ? button
        : Padding(padding: const EdgeInsets.only(top: 16), child: button);
  }

  static bool _isRecoverable() => DatabaseSecurity.liveEncryptionEnabled;
  Future<void> _recover(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Select Locus recovery key',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;
    if (!context.mounted) return;
    final passphrase = await showPassphrasePrompt(
      context,
      title: 'Recovery passphrase',
      description:
          'Enter the passphrase used when this recovery key was created. '
          'Locus will rotate the database key after recovery.',
      confirmLabel: 'Recover',
    );
    if (passphrase == null || !context.mounted) return;
    try {
      final bundle = RecoveryBundle.decode(await File(path).readAsString());
      final opened = await RecoveryEnvelopeService.open(bundle, passphrase);
      if (opened.attachmentKey != null) {
        await SecureAttachmentKeyStore().write(opened.attachmentKey!);
      }
      await DatabaseBootstrap.importRecoveryKey(
        bundle: bundle,
        dek: opened.dek,
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Recovery complete'),
          content: const Text(
            'The database key was restored and rotated. Restart Locus to open '
            'the database with the new key. Keep the recovery file somewhere '
            'safe; it no longer matches the rotated key.',
          ),
          actions: [
            FilledButton(
              onPressed: () => exit(0),
              child: const Text('Close Locus'),
            ),
          ],
        ),
      );
    } on DatabaseSecurityException catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery failed'),
          content: Text('${error.codeName}: ${error.message}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Recovery failed'),
          content: Text('Could not read the recovery file: $error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }
}

/// Stages a raw `.locusrecovery` package from the startup error screen.
///
/// The package is verified and copied next to the database; the current files
/// are not touched. A restart applies the swap under the lifecycle lock.
class StartupRawRecoveryButton extends StatelessWidget {
  const StartupRawRecoveryButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!DatabaseSecurity.liveEncryptionEnabled) {
      return const SizedBox.shrink();
    }
    final button = OutlinedButton.icon(
      onPressed: () => _restore(context),
      icon: const Icon(Icons.restore_outlined),
      label: const Text('Restore recovery package'),
    );
    return compact
        ? button
        : Padding(padding: const EdgeInsets.only(top: 12), child: button);
  }

  Future<void> _restore(BuildContext context) async {
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
          'Enter the passphrase for this package. Locus verifies the '
          'package, stages it, and applies it the next time it starts.',
      confirmLabel: 'Restore',
    );
    if (passphrase == null || !context.mounted) return;
    final keyStore = DatabaseSecurity.keyStore;
    if (keyStore == null) {
      await _showError(context, 'The database key store is not available.');
      return;
    }
    try {
      final paths = await DatabasePathsResolver.resolve();
      await const RecoveryRestoreService().stage(
        paths: paths,
        package: File(path),
        passphrase: passphrase,
        keyStore: keyStore,
        attachmentKeyStore: SecureAttachmentKeyStore(),
      );
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Recovery staged'),
          content: const Text(
            'The package was verified and staged. Close Locus and start it '
            'again to apply the recovered database. The previous files remain '
            'in quarantine.',
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
    } on DatabaseSecurityException catch (error) {
      if (context.mounted) {
        await _showError(context, '${error.codeName}: ${error.message}');
      }
    } catch (error) {
      if (context.mounted) {
        await _showError(context, 'The package could not be staged: $error');
      }
    }
  }

  static Future<void> _showError(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Recovery failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
