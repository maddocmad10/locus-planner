# Phase 2 — Desktop LAN sync API

This phase adds a desktop-hosted, versioned HTTP API without changing the planner's navigation or existing feature flows.

## API surface

- `GET /api/v1/health` — version/status probe; no authentication.
- `POST /api/v1/pairing/exchange` — exchanges the five-minute, one-use pairing code for a random bearer token. Request JSON: `{"code":"ABC123","deviceId":"client-install-uuid","name":"My phone"}`.
- `GET /api/v1/changes?after=0&limit=100` — reads ordered outbox records after the supplied numeric cursor. Requires `Authorization: Bearer <token>`.
- `POST /api/v1/changes/ack` — persists the paired client's acknowledged desktop cursor. Request JSON: `{"cursor":123}`.
- `POST /api/v1/changes/apply` — applies up to 200 supported inbound mutations in one database transaction and suppresses outbox echo. Requires the same bearer authentication. Request JSON: `{"changes":[{"entityType":"event","entityId":"...","operation":"upsert","payload":{"id":"...","title":"...","description":null,"start_time":...,"end_time":null,"category":"general","has_reminder":0,"reminder_minutes":10,"recurrence_rule":null}}]}`.

Supported Phase 1 entities are `project`, `event`, `project_task`, `todo`, and `diary_entry`. The Android MVP performs an initial snapshot on first sync. Sync remains manual and uses last-applied-write-wins behavior rather than a conflict-resolution UI. The caller must apply changes durably before acknowledging the cursor. Project upserts should precede task upserts; a batch is atomic, so a foreign-key failure rejects the batch.

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
