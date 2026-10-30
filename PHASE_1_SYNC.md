# Phase 1 — local identity and transactional sync outbox

This phase intentionally adds no network or Bluetooth code. It establishes a durable change log that either transport can consume later.

> **Status: implemented.** Device identity and the outbox are already part of
> the app; there is no patch to apply. This document records the design and how
> to verify it. Later phases build on it (see `docs/PHASE_2_LAN_SYNC.md` and
> `docs/PHASE_3_ANDROID_MVP.md`).

## Included

- Schema version 8 introduced `sync_outbox`; schema version 9 later added per-row versions for conflict resolution.
- A stable UUID is persisted as `app_settings['sync.device_id']` and created during database open.
- SQLite triggers capture inserts, updates and deletes for `projects`, `events`, project `tasks`, global `todo_items`, and `diary_entries`. The trigger runs in the same SQLite transaction as the edit, so an edit cannot commit without its outbox row.
- Outbox rows contain an entity type, entity ID, operation (`upsert`/`delete`), JSON snapshot/tombstone, originating device ID, and creation time.
- `SyncOutboxRepository` reads ordered batches and deletes rows only after a transport reports durable acknowledgement.
- `sync.suppress_outbox` is reserved for future inbound sync. Incoming changes must set it to `1` inside the same transaction and restore it to `0` before commit, or they will echo back to the sender.

## Verify in a checkout

1. Regenerate Drift's generated code (do not hand-edit `app_database.g.dart`):

   ```powershell
   dart run build_runner build --delete-conflicting-outputs
   ```

2. Format and analyze:

   ```powershell
   dart format lib/core/db/app_database.dart lib/core/services/sync_outbox_repository.dart
   flutter analyze
   flutter test
   ```

3. Run the app against a copy of your existing database first. Take a backup before testing a migration.
4. Create/edit/delete an event, task, to-do item, and diary entry. Inspect `sync_outbox` in SQLite and confirm a matching row appears for each operation. The deletion payload should retain the deleted ID as a tombstone.
5. Confirm the device ID remains identical after restarting the app.

## Important design notes

- SQLite stores `DateTime` columns as integer timestamps with Drift's default SQLite date-time mapping. Payload timestamps are therefore transport-neutral numeric values; the future protocol should document that representation and convert consistently on decode.
- Outbox rows are not automatically discarded or coalesced. That preserves a complete sequence for Phase 1. Later, the sync engine can batch and compact safely once receiver idempotency and acknowledgement semantics are implemented.
- This first pass captures projects as well as events, project tasks, global to-do items, and diary entries. Other related tables (for example progress logs, habits, and focus sessions) are not included yet.
- Existing rows are not automatically enqueued during migration. Phase 2 needs an explicit initial-bootstrap snapshot protocol; the outbox records changes made after this migration.
- The trigger payload uses SQLite `json_object`, available in the SQLite versions normally bundled with `sqlite3_flutter_libs`. Verify this on the app's packaged SQLite build.
