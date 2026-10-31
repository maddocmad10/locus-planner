import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/secret_prompt.dart';
import '../providers/app_lock_controller.dart';

/// App-lock controls shared by desktop Settings and the Android Sync tab.
class AppLockSettingsCard extends ConsumerWidget {
  const AppLockSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(appLockControllerProvider).valueOrNull;
    final enabled = lock?.enabled ?? false;
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text(
              'Ask for a PIN when Locus opens or returns from the background. '
              'The PIN is stored only on this device and is not included in '
              'backups or sync.',
            ),
            value: enabled,
            onChanged: (value) =>
                value ? _enable(context, ref) : _disable(context, ref),
          ),
          if (enabled)
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change app lock PIN'),
              onTap: () => _change(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await showPinPrompt(
      context,
      title: 'Set app lock PIN',
      description:
          'Choose 4 to 8 digits. You will need it every time Locus starts or '
          'comes back from the background.',
      confirmLabel: 'Next',
    );
    if (pin == null || !context.mounted) return;
    final problem = AppLockController.newPinProblem(pin);
    if (problem != null) {
      _message(context, problem);
      return;
    }
    final confirmation = await showPinPrompt(
      context,
      title: 'Confirm app lock PIN',
      description: 'Enter the same PIN again.',
      confirmLabel: 'Turn on lock',
    );
    if (confirmation == null || !context.mounted) return;
    if (confirmation != pin) {
      _message(context, 'The PINs do not match.');
      return;
    }
    final error = await ref
        .read(appLockControllerProvider.notifier)
        .enable(pin);
    if (!context.mounted) return;
    _message(context, error ?? 'App lock is on.');
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final pin = await showPinPrompt(
      context,
      title: 'Turn off app lock',
      description: 'Enter your current PIN.',
      confirmLabel: 'Turn off',
    );
    if (pin == null || !context.mounted) return;
    final error = await ref
        .read(appLockControllerProvider.notifier)
        .disable(pin);
    if (!context.mounted) return;
    _message(context, error ?? 'App lock is off.');
  }

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final current = await showPinPrompt(
      context,
      title: 'Change app lock PIN',
      description: 'Enter your current PIN.',
      confirmLabel: 'Next',
    );
    if (current == null || !context.mounted) return;
    final next = await showPinPrompt(
      context,
      title: 'New app lock PIN',
      description: 'Choose 4 to 8 digits.',
      confirmLabel: 'Next',
    );
    if (next == null || !context.mounted) return;
    final problem = AppLockController.newPinProblem(next);
    if (problem != null) {
      _message(context, problem);
      return;
    }
    final confirmation = await showPinPrompt(
      context,
      title: 'Confirm new PIN',
      description: 'Enter the new PIN again.',
      confirmLabel: 'Change PIN',
    );
    if (confirmation == null || !context.mounted) return;
    if (confirmation != next) {
      _message(context, 'The PINs do not match.');
      return;
    }
    final error = await ref
        .read(appLockControllerProvider.notifier)
        .changePin(current, next);
    if (!context.mounted) return;
    _message(context, error ?? 'App lock PIN changed.');
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
