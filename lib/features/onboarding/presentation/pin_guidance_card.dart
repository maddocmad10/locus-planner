import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';

/// Windows does not expose a supported "pin programmatically" verb. This card
/// gives the user the supported route through the Start apps list and can be
/// dismissed permanently.
class PinGuidanceCard extends ConsumerStatefulWidget {
  const PinGuidanceCard({super.key});

  @override
  ConsumerState<PinGuidanceCard> createState() => _PinGuidanceCardState();
}

class _PinGuidanceCardState extends ConsumerState<PinGuidanceCard> {
  bool? _dismissed;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dismissed =
        await ref
            .read(databaseProvider)
            .getSetting(AppDatabase.pinGuidanceDismissedSettingKey) ==
        '1';
    if (mounted) setState(() => _dismissed = dismissed);
  }

  Future<void> _showAppsFolder() async {
    try {
      await Process.start('explorer.exe', ['shell:AppsFolder']);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'In the apps list, right-click Locus and choose '
              '“Pin to taskbar” or “Pin to Start”.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Open Start, find Locus, right-click it and choose '
            '“Pin to taskbar” or “Pin to Start”.',
          ),
        ),
      );
    }
  }

  Future<void> _dismiss() async {
    await ref
        .read(databaseProvider)
        .setSetting(AppDatabase.pinGuidanceDismissedSettingKey, '1');
    if (mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows || _dismissed != false) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.push_pin_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pin Locus for one-click access',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pin Locus to the taskbar or Start. The taskbar menu and '
                    'jump list also offer Quick capture and Mini Today.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _showAppsFolder,
                        icon: const Icon(Icons.apps),
                        label: const Text('Show apps list'),
                      ),
                      TextButton(
                        onPressed: _dismiss,
                        child: const Text('Don’t show again'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
