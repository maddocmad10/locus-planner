part of '../mobile_app.dart';

class _MobileSyncStatusCard extends ConsumerWidget {
  const _MobileSyncStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(mobileSyncStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final pending = status.pendingEdits;
    final clean = status.lastClean;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              status.reconciliation > 0
                  ? Icons.merge_type
                  : status.needsAttention || status.isPartial
                  ? Icons.warning_amber_outlined
                  : status.paired
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: status.needsAttention
                  ? theme.colorScheme.error
                  : status.isPartial
                  ? theme.colorScheme.tertiary
                  : null,
            ),
            title: Text(
              status.reconciliation > 0
                  ? '${status.reconciliation} local item'
                        '${status.reconciliation == 1 ? '' : 's'} need review'
                  : status.isPartial
                  ? 'Sync partial — more to transfer'
                  : status.needsAttention
                  ? '${status.attention} change'
                        '${status.attention == 1 ? '' : 's'} need attention'
                  : 'Saved on this device',
            ),
            subtitle: Text(
              [
                if (!status.paired)
                  'Not paired with a desktop'
                else if (pending > 0)
                  '$pending pending edit${pending == 1 ? '' : 's'}'
                else
                  'No pending edits',
                if (status.isPartial)
                  'Tap Sync again to continue from the saved position',
                if (clean != null)
                  'Last clean sync ${DateFormat.yMMMd().add_jm().format(clean.toLocal())}'
                else
                  'No clean sync recorded yet',
                if (status.needsRepair) 'Pairing needs repair',
              ].join(' · '),
            ),
            trailing: status.reconciliation > 0
                ? TextButton(
                    onPressed: () => _openReconciliation(context, ref),
                    child: const Text('Review'),
                  )
                : status.needsAttention || status.isPartial
                ? TextButton(
                    onPressed: () => status.isPartial && !status.needsAttention
                        ? _syncNow(context, ref)
                        : _openReview(context, ref),
                    child: Text(status.isPartial ? 'Sync' : 'Review'),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Desktop reminders reach Android after the next successful sync. '
              'A local save works offline.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReview(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _SyncAttentionDialog(),
    );
    ref.invalidate(mobileSyncStatusProvider);
  }

  Future<void> _openReconciliation(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _SyncReconciliationDialog(),
    );
    ref.invalidate(mobileSyncStatusProvider);
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    try {
      final message = await ref.read(mobileSyncClientProvider).syncNow();
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      ref.invalidate(mobileSyncStatusProvider);
    }
  }
}

class _SyncAttentionDialog extends ConsumerStatefulWidget {
  const _SyncAttentionDialog();

  @override
  ConsumerState<_SyncAttentionDialog> createState() =>
      _SyncAttentionDialogState();
}

class _SyncAttentionDialogState extends ConsumerState<_SyncAttentionDialog> {
  List<SyncRejectedRecord>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final records = await SyncReceiptStore(db).openRejections();
    if (mounted) setState(() => _records = records);
  }

  Future<void> _discard(SyncRejectedRecord record) async {
    final db = ref.read(databaseProvider);
    await SyncReceiptStore(db).discard(
      peerId: record.peerId,
      epoch: record.epoch,
      direction: record.direction,
      changeId: record.changeId,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final records = _records;
    return AlertDialog(
      title: const Text('Changes needing attention'),
      content: SizedBox(
        width: 460,
        child: records == null
            ? const Center(child: CircularProgressIndicator())
            : records.isEmpty
            ? const Text('Nothing is waiting for review.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final record = records[index];
                  return ListTile(
                    dense: true,
                    title: Text('${record.entityType} ${record.entityId}'),
                    subtitle: Text(
                      '${record.reasonCode} · ${record.attempts} attempt'
                      '${record.attempts == 1 ? '' : 's'}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _discard(record),
                      child: const Text('Discard'),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            try {
              await ref.read(mobileSyncClientProvider).syncNow();
            } catch (_) {}
            await _load();
          },
          child: const Text('Retry sync'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
