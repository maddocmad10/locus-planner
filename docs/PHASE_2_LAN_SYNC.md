# Phase 2 — Desktop LAN sync API

This phase adds a desktop-hosted, versioned HTTP API without changing the planner's navigation or existing feature flows.

## API surface

- `GET /api/v1/health` — version/status probe; no authentication.
- `POST /api/v1/pairing/exchange` — exchanges the five-minute, one-use pairing code for a random bearer token. Request JSON: `{"code":"ABC123","deviceId":"client-install-uuid","name":"My phone"}`.
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
3. Launch Locus, open **Settings → Device Sync (LAN)**, and enable the server. The server listens on all IPv4 interfaces on TCP port `43821`; a one-time pairing code appears and expires in five minutes.
4. Run `ipconfig` on the desktop and find its Wi-Fi IPv4 address. On the second device, replace `192.168.x.x` below with that address. Both devices must be on a trusted private Wi-Fi network; guest Wi-Fi/client isolation can block connections.
5. From a second device with `curl` available, check the health endpoint:
   ```sh
   curl http://192.168.x.x:43821/api/v1/health
   ```
6. Pair the second device, replacing `ABC123` with the code visible in desktop Settings:
   ```sh
   curl -X POST http://192.168.x.x:43821/api/v1/pairing/exchange      -H "Content-Type: application/json"      -d '{"code":"ABC123","deviceId":"phone-install-uuid","name":"Test phone"}'
   ```
   Save the returned token securely. The code is one-use. For a new pairing, stop and start the server to create a new code.
7. Prove authentication: a request without a token should return `401`; a request with the token should return `200`:
   ```sh
   curl -i http://192.168.x.x:43821/api/v1/changes
   curl -i http://192.168.x.x:43821/api/v1/changes      -H "Authorization: Bearer YOUR_TOKEN"      -H "Accept: application/json"
   ```
8. Create or edit a supported entity in the desktop app, then repeat the authenticated changes request with `?after=0&limit=100`. The resulting record should appear in `changes`. A client should only call `/changes/ack` after it has durably applied the changes.
9. Revoke the paired client from desktop Settings and verify its previously issued token now gets `401`.
10. Disable LAN sync when not needed.

If Windows Firewall blocks the connection, allow inbound TCP `43821` only on the **Private** profile. Do not expose this port on Public networks.

## Security and current scope

Pairing secrets are short-lived and single-use; bearer tokens are generated with a cryptographically secure random source and only their SHA-256 digests are persisted. Tokens can be revoked from Settings. Request bodies are size-limited and change batches are capped.

The first implementation uses plain HTTP on the local network, so bearer tokens and change payloads are not encrypted in transit. Use only a trusted private network; do not use public/guest Wi-Fi or port-forward this API to the internet. HTTPS/certificate pairing, richer client cursor management, and explicit conflict resolution are later work. This is a server/API phase, not yet a complete background two-way sync client.

## Conflict resolution

Schema version 9 adds `sync_row_versions`, one row per synced entity, kept up to date by the same SQLite triggers that fill the outbox. Each payload carries the row's version as `updated_at` (epoch milliseconds) and each change carries the originating `deviceId`.

- An incoming change is applied only if its version is newer than the local one. An exact tie is broken by device ID so both devices choose the same winner; replaying an already-applied change is a no-op.
- Deletes are versioned tombstones, so a stale upsert cannot bring back a row that was deleted later.
- A local edit is always at least one version above the row's previous version, so editing after receiving a change from a device with a fast clock still wins over it.
- Both the desktop API (`/changes/apply`) and the Android client use `SyncChangeApplier`, so the rules are identical in each direction. `/changes/apply` also reports `applied` and `skipped` counts.
- Rows that existed before the upgrade have no version until they are next edited, and an incoming change always wins over an unversioned row. Changes from a peer that predates versioning are applied unconditionally.
- Versions come from each device's wall clock. If two devices edit the same row at nearly the same moment, a clock that is far off can pick the wrong winner, so keep device clocks set automatically.
- Diary entries are also unique per date. If two different entries claim one date, the entry with the lowest ID is kept on both devices.

## Epoch check and outbox pruning

**Epoch.** Each desktop database creates a random `sync.epoch` the first time it opens. The server returns it when pairing, in snapshots and in `/changes` responses, and the phone sends it back in the `X-Locus-Epoch` header on every other request. If the header does not match, the server answers `409 epoch_mismatch`. This catches a reinstalled or rebuilt desktop, whose outbox ids restart and would otherwise make the phone's cursors meaningless. The epoch is excluded from backups on purpose, so restoring a backup never brings back an old history. The snapshot endpoint is exempt, because it is how a phone recovers.

**Cursor checks.** `/changes` also answers `409 cursor_ahead` if the phone's cursor is beyond anything the desktop ever issued, and `409 resync_required` if the phone's cursor points into rows that have been pruned.

**Resync.** On any of those three `409` errors the phone forgets its position, fetches a fresh snapshot, and pushes its own full state (live rows and delete tombstones) back to the desktop before resuming. Because both sides compare row versions, the newer edit wins and nothing on the phone is lost. It retries once; if the desktop still disagrees the error is shown.

**Pruning.**
- Desktop: after each acknowledgement, on server start and when a phone is revoked, outbox rows that every paired phone has acknowledged are deleted. With no paired phones the whole outbox is cleared, since a newly paired phone starts from a snapshot. Rows older than 60 days are deleted even if a phone never acknowledged them, so a lost phone cannot pin the outbox forever; that phone gets `resync_required` when it next connects.
- Phone: after a successful push, outbox rows up to the pushed cursor are deleted.
- `sync.outbox.pruned_through` records the highest pruned id. Outbox ids are `AUTOINCREMENT`, so pruning never reuses an id.

Not pruned yet: delete tombstones in `sync_row_versions`. They are small, and keeping them stops a stale device from resurrecting deleted rows.
