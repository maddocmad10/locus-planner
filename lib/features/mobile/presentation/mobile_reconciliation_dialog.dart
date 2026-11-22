part of '../mobile_app.dart';

class _SyncReconciliationDialog extends ConsumerStatefulWidget {
  const _SyncReconciliationDialog();

  @override
  ConsumerState<_SyncReconciliationDialog> createState() =>
      _SyncReconciliationDialogState();
}

class _SyncReconciliationDialogState
    extends ConsumerState<_SyncReconciliationDialog> {
  List<SnapshotReviewItem>? _items;
  final Map<String, String> _decisions = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final items = await SnapshotReconciliationService(db).reviewItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      for (final item in items) {
        _decisions.putIfAbsent(item.changeId, () => 'leave');
      }
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final result = await SnapshotReconciliationService(
        ref.read(databaseProvider),
      ).resolve(_decisions);
      if (!mounted) return;
      _message(
        'Recovery queued: ${result.recovered} recovered, '
        '${result.kept} deletion${result.kept == 1 ? '' : 's'} kept, '
        '${result.remaining} left for later.',
      );
      try {
        await ref.read(mobileSyncClientProvider).syncNow();
      } catch (_) {
        // The next ordinary sync completes the staged upload.
      }
      ref.invalidate(mobileSyncStatusProvider);
      if (mounted) Navigator.pop(context);
    } on SnapshotReviewChangedException catch (error) {
      if (mounted) {
        _message('$error Review the updated items again.');
        await _load();
      }
    } on SnapshotRecoveryRequiresOwnerException catch (error) {
      if (mounted) _message('$error');
    } catch (error) {
      if (mounted) _message('Could not apply the reconciliation: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openArchive(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _ArchivedReconciliationsDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AlertDialog(
      title: const Text('Local items need reconciliation'),
      content: SizedBox(
        width: 560,
        height: 420,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Text('Nothing is waiting for review.')
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.displayTitle),
                    subtitle: Text(
                      [
                        if ((item.desktopName ?? item.peerId).isNotEmpty)
                          'Desktop: ${item.desktopName ?? item.peerId}',
                        item.reason,
                        if (item.attachmentCount > 0)
                          '${item.attachmentCount} attachment'
                              '${item.attachmentCount == 1 ? '' : 's'}',
                        if (item.childCount > 0)
                          '${item.childCount} linked row'
                              '${item.childCount == 1 ? '' : 's'}',
                      ].join(' · '),
                    ),
                    trailing: DropdownButton<String>(
                      value: _decisions[item.changeId] ?? 'leave',
                      items: const [
                        DropdownMenuItem(
                          value: 'leave',
                          child: Text('Leave for later'),
                        ),
                        DropdownMenuItem(
                          value: 'keep',
                          child: Text('Keep desktop deletion'),
                        ),
                        DropdownMenuItem(
                          value: 'recover',
                          child: Text('Recover as new'),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _decisions[item.changeId] = value ?? 'leave';
                      }),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _openArchive(context),
          child: const Text('Archived'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy || items == null || items.isEmpty ? null : _apply,
          child: Text(_busy ? 'Working…' : 'Apply decisions'),
        ),
      ],
    );
  }
}

class _ArchivedReconciliationsDialog extends ConsumerStatefulWidget {
  const _ArchivedReconciliationsDialog();

  @override
  ConsumerState<_ArchivedReconciliationsDialog> createState() =>
      _ArchivedReconciliationsDialogState();
}

class _ArchivedReconciliationsDialogState
    extends ConsumerState<_ArchivedReconciliationsDialog> {
  List<SnapshotReviewItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await SnapshotReconciliationService(
      ref.read(databaseProvider),
    ).archivedReviewItems();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AlertDialog(
      title: const Text('Archived recovery decisions'),
      content: SizedBox(
        width: 520,
        height: 360,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
            ? const Text(
                'No archived decisions. Retired sessions keep their '
                'staged evidence here.',
              )
            : ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.displayTitle),
                    subtitle: Text(
                      '${item.desktopName ?? item.peerId} · '
                      '${item.entityType} ${item.entityId} · ${item.reason}',
                    ),
                    trailing: const Text('Read only'),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
