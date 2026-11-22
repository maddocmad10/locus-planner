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
        'Recovered ${result.recovered}, kept ${result.kept} deletion'
        '${result.kept == 1 ? '' : 's'}, '
        '${result.remaining} left for later.',
      );
      try {
        await ref.read(mobileSyncClientProvider).syncNow();
      } catch (_) {
        // The next ordinary sync completes the staged upload.
      }
      ref.invalidate(mobileSyncStatusProvider);
      if (mounted) Navigator.pop(context);
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
                    title: Text('${item.entityType} ${item.entityId}'),
                    subtitle: Text(item.reason),
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
