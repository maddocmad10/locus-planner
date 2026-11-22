# Schema 29 → 30 remediation

Schema 30 is additive. It carries the durability fields required by the 1.6.1
fix specification without changing existing ids, tombstones, outbox rows or
keys. The pre-upgrade backup runs before this migration.

## Stores

| Store | Schema 30 change |
| --- | --- |
| `sync_change_receipts` | nullable `entity_type`, `entity_id`, `capability_version`; entity index |
| `sync_rejected_changes` | nullable `capability_version` |
| `sync_peer_exchange` | `outcome`, `continuation_cursor`, `requested_count`, `accounted_count`, `error_code`, `updated_at` |
| `snapshot_session` | `committed_item_count`, `capture_complete`, `retired_at`, `peer_name`; one active session per peer/epoch |
| `snapshot_item` | `reviewed_revision`, `reviewed_digest`, `upload_change_id`; `approved_upload` disposition |
| `snapshot_recovery_map` | `(snapshot_id, entity_type, original_id)` → one `recovered_id` |
| `todo_items` | `due_kind` (`legacy_instant`, `date_only`, `instant`, `undated`), `due_date_key`, `undated_generation` |
| `todo_completions` | `slot_kind`, `slot_date`, `slot_generation` |
| `todo_completion_aliases` | proven duplicate completion ids → canonical completion id |
| `share_intake_files` | `retry_count`, `reason_code` |
| `share_intake_state` | `completed_at` |

## Invariants

- A completion id is `task id + pre-advance occurrence slot`. Reachable
  duplicates get an alias so replay or deletion of a legacy id reaches the
  canonical row; uncertain rows stay for review.
- An already acknowledged change is never rewritten under its old change id.
  A recovered row receives a fresh change id and an `approved_upload` envelope.
- `last_clean_ms` advances only when both streams are exhausted, every requested
  row is accounted for, and no repair or review decision remains. Partial pages
  retain a continuation cursor and report **Partial**.
- A capture is committed with its inventory and item count in one transaction.
  Empty captured inventories are valid. Edits after the captured frontier stay
  in the incremental outbox.
- Review is scoped to the active peer, epoch and snapshot. A decision is
  revalidated against the current row version inside the write transaction.
- Recovery follows typed foreign-key edges; it no longer updates columns of an
  unrelated entity that happens to share a literal id. `foreign_key_check` runs
  before commit.

## Legacy behaviour

- Existing `due_date` values stay `legacy_instant` until an explicit edit. Their
  historical completion ids and occurrence keys are preserved.
- A schema-29 capture keeps its staged rows. Sessions with an unproven capture
  are retired rather than silently treated as complete, so their evidence can
  be reviewed from the archive view.
- Missing receipt identity or capability fields remain null; they are not
  guessed from an unrelated cursor or preference.
- A preference cursor is seeded into SQLite only when the saved peer and epoch
  prove it belongs to the same pairing.

## Rollback

Schema 30 is additive, so a compatible older build can open the same file after
the pre-upgrade backup is restored. Do not delete the backup until the new
build has opened, synced and passed `PRAGMA foreign_key_check`.
