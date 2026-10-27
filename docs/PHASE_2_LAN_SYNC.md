# Phase 2 — Desktop LAN sync API

This phase adds a desktop-hosted, versioned HTTP API without changing the planner's navigation or existing feature flows.

## API surface

- `GET /api/v1/health` — version/status probe; no authentication.
- `POST /api/v1/pairing/exchange` — exchanges the five-minute, one-use pairing code for a random bearer token. Request JSON: `{"code":"A1B2C3D4","deviceId":"client-install-uuid","name":"My phone"}`.
- `GET /api/v1/changes?after=0&limit=100` — reads ordered outbox records after the supplied numeric cursor. Requires `Authorization: Bearer <token>`.
- `POST /api/v1/changes/ack` — persists the paired client's acknowledged desktop cursor. Request JSON: `{"cursor":123}`.
- `POST /api/v1/changes/apply` — applies up to 200 supported inbound mutations in one database transaction and suppresses outbox echo. Requires the same bearer authentication. Request JSON: `{"changes":[{"entityType":"event","entityId":"...","operation":"upsert","payload":{"id":"...","title":"...","description":null,"start_time":...,"end_time":null,"category":"general","has_reminder":0,"reminder_minutes":10,"recurrence_rule":null}}]}`.

Supported Phase 1 entities are `project`, `event`, `project_task`, `todo`, and `diary_entry`. The Android MVP performs an initial snapshot on first sync. Sync remains manual. Conflicts are resolved per row by version (see "Conflict resolution" below) rather than by a conflict-resolution UI. The caller must apply changes durably before acknowledging the cursor. Project upserts should precede task upserts; a batch is atomic, so a foreign-key failure rejects the batch.

## Run on Windows

1. Back up the app database.
2. From the project root, run:
   ```powershell
   flutter pub get
   dart format lib/core/services/lan_sync_server.dart lib/core/providers/service_providers.dart lib/features/settings/presentation/settings_page.dart test/lan_sync_server_test.dart
   flutter analyze
   flutter test
   ```
3. Launch Locus, open **Settings → Device Sync (LAN)**, and enable the server. The server listens on all IPv4 interfaces on TCP port `43821` over HTTPS; a one-time pairing code, a QR code and the computer's security fingerprint appear, and the code expires in five minutes.
4. Run `ipconfig` on the desktop and find its Wi-Fi IPv4 address. On the second device, replace `192.168.x.x` below with that address. Both devices must be on a trusted private Wi-Fi network; guest Wi-Fi/client isolation can block connections.
5. From a second device with `curl` available, check the health endpoint:
   ```sh
   curl -k https://192.168.x.x:43821/api/v1/health
   ```
6. Pair the second device, replacing `A1B2C3D4` with the code visible in desktop Settings:
   ```sh
   curl -k -X POST https://192.168.x.x:43821/api/v1/pairing/exchange      -H "Content-Type: application/json"      -d '{"code":"A1B2C3D4","deviceId":"phone-install-uuid","name":"Test phone"}'
   ```
   Save the returned token securely. The code is one-use. For a new pairing, click **New pairing code** in desktop Settings.
7. Prove authentication: a request without a token should return `401`; a request with the token should return `200`:
   ```sh
   curl -k -i https://192.168.x.x:43821/api/v1/changes
   curl -k -i https://192.168.x.x:43821/api/v1/changes      -H "Authorization: Bearer YOUR_TOKEN"      -H "Accept: application/json"
   ```
8. Create or edit a supported entity in the desktop app, then repeat the authenticated changes request with `?after=0&limit=100`. The resulting record should appear in `changes`. A client should only call `/changes/ack` after it has durably applied the changes.
9. Revoke the paired client from desktop Settings and verify its previously issued token now gets `401`.
10. Disable LAN sync when not needed.

If Windows Firewall blocks the connection, allow inbound TCP `43821` only on the **Private** profile. Do not expose this port on Public networks.

## Security and current scope

Pairing secrets are short-lived and single-use; bearer tokens are generated with a cryptographically secure random source and only their SHA-256 digests are persisted. Tokens can be revoked from Settings. Request bodies are size-limited and change batches are capped.

All traffic is HTTPS. On first start the desktop creates a self-signed certificate and keeps it (with its key) in its database settings, which are excluded from backups, so its fingerprint stays the same across restarts and address changes. A certificate for a bare IP address cannot come from a public authority, so phones do not use one. They **pin** the certificate instead: the pairing QR code carries the desktop's address, the one-time code and the SHA-256 fingerprint of its certificate, and the phone connects only to a server presenting exactly that certificate, with no system or built-in roots trusted. Nothing, including the pairing code, is sent to any other server. This protects the bearer token and the data from other devices on the same Wi-Fi, including a device impersonating the desktop.

Without a camera, a phone can pair by address and code. It first connects without sending anything, reads the certificate fingerprint, and asks the user to confirm that it matches the fingerprint shown in desktop Settings before pairing. Compare it carefully: that comparison is what protects a manual pairing.

`curl -k` in the examples below skips certificate checking, which is acceptable for a quick local test on a network you trust but is exactly what a phone does not do.

Pairing a device that is already paired (after **Forget pairing**, a reinstall, or the upgrade to HTTPS) replaces its previous entry and token. The one-time code, which is only visible on the desktop, is what authorises it. **New pairing code** in desktop Settings issues a fresh code and clears the failed-attempt count, so wrong guesses from the network cannot block pairing until the next restart.

Still true: do not use public/guest Wi-Fi or port-forward this API to the internet. Anyone who can reach the port can attempt to guess the pairing code while one is active (twenty wrong guesses stop pairing until a new code is issued), and a TLS identity that is lost or replaced makes every phone pair again.

## Conflict resolution

Schema version 9 adds `sync_row_versions`, one row per synced entity, kept up to date by the same SQLite triggers that fill the outbox. Each payload carries the row's version as `updated_at` (epoch milliseconds) and each change carries the originating `deviceId`.

- An incoming change is applied only if its version is newer than the local one. An exact tie is broken by device ID so both devices choose the same winner; replaying an already-applied change is a no-op.
- Deletes are versioned tombstones, so a stale upsert cannot bring back a row that was deleted later.
- A local edit is always at least one version above the row's previous version, so editing after receiving a change from a device with a fast clock still wins over it.
- Both the desktop API (`/changes/apply`) and the Android client use `SyncChangeApplier`, so the rules are identical in each direction. `/changes/apply` also reports `applied` and `skipped` counts.
- Rows that existed before the upgrade have no version until they are next edited, and an incoming change always wins over an unversioned row. Changes from a peer that predates versioning are applied unconditionally.
- Versions come from each device's wall clock. If two devices edit the same row at nearly the same moment, a clock that is far off can pick the wrong winner, so keep device clocks set automatically.
- Diary entries are also unique per date. If two different entries claim one date, the entry with the lowest ID keeps its ID on both devices and the other entry's text is merged into it, after a "merged from another device" divider. Both devices compute the same merged text and the merge is idempotent, so it settles after one extra exchange and nothing the user wrote is discarded. Moods are not merged: the surviving entry keeps its own mood.

## Epoch check and outbox pruning

**Epoch.** Each desktop database creates a random `sync.epoch` the first time it opens. The server returns it when pairing, in snapshots and in `/changes` responses, and the phone sends it back in the `X-Locus-Epoch` header on every other request. If the header does not match, the server answers `409 epoch_mismatch`. This catches a reinstalled or rebuilt desktop, whose outbox ids restart and would otherwise make the phone's cursors meaningless. The epoch is excluded from backups on purpose, so restoring a backup never brings back an old history. The snapshot endpoint is exempt, because it is how a phone recovers.

**Cursor checks.** `/changes` also answers `409 cursor_ahead` if the phone's cursor is beyond anything the desktop ever issued, and `409 resync_required` if the phone's cursor points into rows that have been pruned.

**Resync.** On any of those three `409` errors the phone forgets its position, fetches a fresh snapshot, and pushes its own full state (live rows and delete tombstones) back to the desktop before resuming. Because both sides compare row versions, the newer edit wins and nothing on the phone is lost. It retries once; if the desktop still disagrees the error is shown.

**Pruning.**
- Desktop: after each acknowledgement, on server start and when a phone is revoked, outbox rows that every paired phone has acknowledged are deleted. With no paired phones the whole outbox is cleared, since a newly paired phone starts from a snapshot. Rows older than 60 days are deleted even if a phone never acknowledged them, so a lost phone cannot pin the outbox forever; that phone gets `resync_required` when it next connects.
- Phone: after a successful push, outbox rows up to the pushed cursor are deleted.
- `sync.outbox.pruned_through` records the highest pruned id. Outbox ids are `AUTOINCREMENT`, so pruning never reuses an id.

Not pruned yet: delete tombstones in `sync_row_versions`. They are small, and keeping them stops a stale device from resurrecting deleted rows.

## Screen refresh and reminders after sync

Synced rows are written with raw SQL so that the outbox triggers can be suppressed. Drift cannot see raw SQL, so its `watch()` streams, which every screen is built on, would not refresh on their own. After each applied batch `SyncChangeApplier` calls `markTablesUpdated` for the tables it changed (plus the tables a project delete cascades to), on both the desktop and the phone. Changes that were skipped as stale do not trigger a refresh.

Event reminders are in-memory timers owned by `EventRepository`, which sync bypasses. `LanSyncServer.onChangesApplied` is called after a phone's changes are committed, and `main.dart` uses it to call `EventRepository.rescheduleReminders` for each changed event: a deleted event has its timer cancelled, and a new or edited one is re-armed from its stored time. A failure in this hook is logged and never fails the sync.

The Android app has no reminder implementation yet (the notification service is desktop-only), so events synced to the phone do not produce phone notifications.
