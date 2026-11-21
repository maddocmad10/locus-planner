# Schema 25–29: migrations, rollback and compatibility

This release moves the Drift schema from 24 to 28. Every step is additive,
transactional and covered by `test/schema_upgrade_test.dart` plus the generated
fixtures in `test/generated_migrations/`.

## 25 — Sync reliability

New raw protocol tables:

- `sync_peer_progress` — durable per-peer, per-epoch push/pull cursor and
  timestamps. A cursor advances only after every preceding change has a durable
  outcome.
- `sync_rejected_changes` — original revision, reason code, attempts and
  resolution time for repairs.

`sync_peer_progress` starts empty. Legacy `_pushedCursor` / `_remoteCursor`
preferences are copied by `SyncReceiptStore.recoverLegacyCursors`; the clean
sync time is deliberately **not** guessed. The same step rebuilds every outbox
trigger so `fv` entries carry `[wallMs, counter, writerId]` and delete payloads
carry the tombstone counter and writer.

Rollback: keep the database; older code ignores both tables. Do not delete
`sync_rejected_changes` while repairs are open.

## 26 — Desktop calendar subscriptions

New device-local tables:

- `calendar_sources`
- `calendar_occurrences`

They are intentionally absent from `SyncChangeApplier` schemas, triggers,
logical exports, diagnostics and LAN sync. The feed URL is stored in the OS
protected secret store; the table only keeps `secret_ref`. Disconnecting removes
the secret and cascades the cached occurrences.

Rollback: the cache can be dropped without touching planner data. The secret
refs are removed by Disconnect before uninstalling; an orphaned secret is inert.

## 27 — Todoist CSV receipts

New table `import_receipts` with the primary key
`(source_kind, destination_id, file_sha256, row_number)` and indexes on
destination and fingerprint. Receipts accompany logical backups (format v5) and
are restored verbatim, including receipts whose task the user has since
deleted.

Rollback: receipts are advisory. Removing the table only means a rerun of the
same CSV can create duplicates; tasks themselves are unaffected.

## 28 — Rich recurrence

`todo_items.recurrence_spec` and `events.recurrence_spec` are nullable TEXT
columns holding a versioned JSON object. Historical `recurrence_rule` values
remain valid and authoritative. The trigger set is rebuilt so both fields travel
in snapshots, relays and field-origin maps.

The field merge treats `recurrence_rule` + `recurrence_spec` as one logical
schedule. If a peer does not send the spec half, the local pair is preserved.

Rollback: older binaries ignore the column. Deleting it is safe but loses richer
rules; keep historical rules as they are.

## 29 — Durable exchange, snapshots and occurrence identity

Additive protocol/data state:

- `sync_peer_exchange`, `sync_change_receipts` — exchange summaries and an
  immutable receipt ledger keyed by peer, epoch, direction and change id.
- `sync_peer_progress.last_trusted_server_ms`; repair rows gain
  `resolution_kind`, `last_attempt_ms`, `payload_sha256`.
- `snapshot_session` / `snapshot_item` — resumable bootstrap capture and upload.
- `todo_completions.occurrence_key` plus a partial unique index on
  `(todo_id, occurrence_key)` for known occurrences.
- `calendar_sources.coverage_start_ms`, `coverage_end_ms`, `cache_revision`.
- `share_intake_state` / `share_intake_files` — per-intake claim and per-file
  durable results.

The migration creates any missing historical raw table before altering it, adds
the Drift column through the normal upgrade path, rebuilds triggers, and leaves
all existing IDs, clocks, tombstones, reminder IDs and encryption unchanged.
Legacy cursor preferences are hints only; no clean exchange time is inferred.

Rollback: all new tables are additive. Older binaries ignore them, but they must
not write rich recurrence or accept receipt-dependent acknowledgements. Restore
a compatible verified backup only with an explicit user decision.

## Failure and rollback rules

- A failed migration leaves the original database and verified recovery copy in
  place; the existing recovery UI is used.
- Roll a feature back with its write flag first (calendar subscription, CSV
  import, richer recurrence).
- An older binary may read the newer schema but must not write richer fields.
  Recover by forward-fixing or by restoring a compatible verified backup with
  explicit user choice.
- Before tombstone pruning, `SyncTombstoneGc` rechecks paired-client progress
  inside the pruning transaction.
- A logical restore clears peer cursors and pairing credentials and sets
  `sync.rebase_required`; pending work is preserved for inspection or exported
  before replacement.
