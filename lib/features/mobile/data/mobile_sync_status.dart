import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/app_database.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/services/sync_receipt_store.dart';
import '../../../core/services/snapshot_reconciliation_service.dart';
import '../data/mobile_sync_client.dart';

class MobileSyncStatusSnapshot {
  const MobileSyncStatusSnapshot({
    required this.paired,
    required this.host,
    required this.pendingEdits,
    required this.attention,
    required this.lastClean,
    required this.lastAttempt,
    required this.errorCode,
    required this.needsRepair,
    required this.peerUpdateNeeded,
    required this.reconciliation,
  });

  final bool paired;
  final String? host;
  final int pendingEdits;
  final int attention;
  final DateTime? lastClean;
  final DateTime? lastAttempt;
  final String? errorCode;
  final bool needsRepair;
  final bool peerUpdateNeeded;
  final int reconciliation;
}

/// Reads durable sync state for Today and Sync. Counts only; rejected payloads
/// stay inside the encrypted database.
final mobileSyncStatusProvider =
    FutureProvider.autoDispose<MobileSyncStatusSnapshot>((ref) async {
      final db = ref.watch(databaseProvider);
      final status = await ref.watch(mobileSyncClientProvider).status();
      final rows = await db
          .customSelect('SELECT COUNT(*) AS count FROM sync_outbox')
          .get();
      final receipts = SyncReceiptStore(db);
      final progress = await receipts.progress();
      return MobileSyncStatusSnapshot(
        paired: status.paired,
        host: status.host,
        pendingEdits: rows.first.read<int>('count'),
        attention: await receipts.openRejectionCount(),
        lastClean: (await receipts.latestClean())?.lastClean,
        lastAttempt: progress.isEmpty ? null : progress.first.lastExchange,
        errorCode: progress.isEmpty ? null : progress.first.errorCode,
        needsRepair: status.needsRepair,
        peerUpdateNeeded:
            await db.getSetting(AppDatabase.syncPeerUpdateNeededSettingKey) ==
            '1',
        reconciliation: await SnapshotReconciliationService(db).reviewCount(),
      );
    });
