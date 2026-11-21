part of '../mobile_app.dart';

class _SyncScreen extends ConsumerStatefulWidget {
  const _SyncScreen({required this.syncing, required this.onSync});
  final bool syncing;
  final Future<void> Function() onSync;
  @override
  ConsumerState<_SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<_SyncScreen> {
  final _hostController = TextEditingController();
  final _codeController = TextEditingController();
  bool _pairing = false;
  MobileSyncStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshStatus();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await ref.read(mobileSyncClientProvider).status();
    if (mounted) setState(() => _status = status);
  }

  /// Runs a pairing flow. [action] returns false when the user backed out.
  Future<void> _runPairing(Future<bool> Function() action) async {
    setState(() {
      _pairing = true;
      _error = null;
    });
    try {
      final paired = await action();
      if (!paired) return;
      _codeController.clear();
      await _refreshStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone paired. Tap Sync now to exchange data.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  /// Scanning is the safest path: the QR code carries the desktop's address,
  /// the one-time code and the certificate fingerprint, so nothing is typed
  /// and nothing can be swapped.
  Future<bool> _pairFromQr() async {
    return ref.read(appLockControllerProvider.notifier).runExternal(() async {
      final result = await Navigator.of(context).push<PairScanResult>(
        MaterialPageRoute(builder: (_) => const PairScannerPage()),
      );
      if (result is PairScanManualEntry) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Enter the desktop address and pairing code below.',
              ),
            ),
          );
        }
        return false;
      }
      if (result is! PairScanSuccess) return false;
      final payload = result.payload;
      await ref
          .read(mobileSyncClientProvider)
          .pair(
            host: '${payload.host}:${payload.port}',
            code: payload.code,
            fingerprint: payload.fingerprint,
          );
      return true;
    });
  }

  /// Manual pairing: read the certificate fingerprint from the desktop, have
  /// the user confirm it matches the one shown there, then pair.
  Future<bool> _pairManually() async {
    final client = ref.read(mobileSyncClientProvider);
    final host = _hostController.text;
    final fingerprint = await client.fetchDesktopFingerprint(host);
    if (!mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Is this your desktop?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Locus on your desktop shows a security fingerprint next to the '
              'pairing code. Pair only if it starts with exactly these '
              'characters:',
            ),
            const SizedBox(height: 12),
            SelectableText(
              shortSyncFingerprint(fingerprint),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('They match'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    await client.pair(
      host: host,
      code: _codeController.text,
      fingerprint: fingerprint,
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final durable = ref.watch(mobileSyncStatusProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Device sync', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'Connect to Locus on your desktop while both devices are on the same trusted Wi-Fi network.',
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(status?.paired == true ? Icons.link : Icons.link_off),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        status?.paired == true
                            ? 'Paired with ${status!.host}'
                            : 'Not paired',
                      ),
                    ),
                  ],
                ),
                if (status?.lastSync != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Last sync: ${DateFormat.yMMMd().add_jm().format(status!.lastSync!.toLocal())}',
                    ),
                  ),
                if (durable != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${durable.pendingEdits} pending edit'
                      '${durable.pendingEdits == 1 ? '' : 's'}',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      durable.lastClean == null
                          ? 'No clean sync recorded yet'
                          : 'Last clean sync: '
                                '${DateFormat.yMMMd().add_jm().format(durable.lastClean!.toLocal())}',
                    ),
                  ),
                  if (durable.attention > 0)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await showDialog<void>(
                            context: context,
                            builder: (_) => const _SyncAttentionDialog(),
                          );
                          await _refreshStatus();
                          ref.invalidate(mobileSyncStatusProvider);
                        },
                        icon: const Icon(Icons.warning_amber_outlined),
                        label: Text(
                          '${durable.attention} change'
                          '${durable.attention == 1 ? '' : 's'} need attention',
                        ),
                      ),
                    ),
                  if (durable.peerUpdateNeeded)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Peer update needed. This desktop does not confirm '
                        'individual changes yet, so affected local work is kept.',
                      ),
                    ),
                ],
                const SizedBox(height: 16),
                if (status?.needsRepair == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Sync now uses a verified, encrypted connection. Pair '
                      'this phone with the desktop again.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _pairing ? null : () => _runPairing(_pairFromQr),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(
                    _pairing ? 'Pairing…' : 'Scan QR code on desktop',
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No camera? Enter the details instead.',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _hostController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Desktop IP address',
                    hintText: '192.168.1.20:43821',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'One-time pairing code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pairing ? null : () => _runPairing(_pairManually),
                  icon: const Icon(Icons.phonelink_setup),
                  label: const Text('Pair with entered details'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.syncing
                      ? null
                      : () async {
                          await widget.onSync();
                          await _refreshStatus();
                        },
                  icon: widget.syncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(widget.syncing ? 'Syncing…' : 'Sync now'),
                ),
                if (status?.paired == true)
                  TextButton(
                    onPressed: () async {
                      await ref.read(mobileSyncClientProvider).unpair();
                      await _refreshStatus();
                    },
                    child: const Text('Forget pairing on this phone'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const _RemindersCard(),
        const SizedBox(height: 12),
        const AppLockSettingsCard(),
        const SizedBox(height: 12),
        const _EmptyCard(
          message:
              'Locus syncs when you open the app or bring it back to the '
              'foreground, and when you tap Sync now. There is no background '
              'sync while the app is closed; open it once before relying on '
              'changes made on the desktop.',
        ),
        const SizedBox(height: 12),
        const _EmptyCard(
          message:
              'Pairing uses the one-time code in desktop Settings → Device Sync (LAN). Sync is encrypted with HTTPS and pins the desktop certificate, so other devices on the network cannot read or impersonate it. Only use a trusted private Wi-Fi network, never public Wi-Fi.',
        ),
      ],
    );
  }
}
