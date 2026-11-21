# Sync hardening (schema v23, 1.6)

This is the first slice of the 1.6 sync-hardening release from
`Locus planner new schema.docx`.

## Implemented

### Schema v23

All additive raw-SQL objects, with no epoch rotation:

- `sync_row_versions.hlc_counter INTEGER NOT NULL DEFAULT 0`
- `sync_field_versions (entity_type, entity_id, field, updated_at,
  hlc_counter, device_id)` — one row per edited field.
- `sync_clock (id = 1, last_wall, last_counter)`
- `sync_log` — one row per sync attempt (30-day retention is a follow-up job).
- `sync_conflicts` — losing field/delete values for review (30-day retention is
  a follow-up job).

The migration runs from every released schema (v4 through v22) and rebuilds the
outbox triggers. Generated migration fixtures now include v23.

### Hybrid logical clock (S1/S2)

Local edits advance `sync_clock` and stamp the row and every changed field with
`(wall_ms, counter, device_id)`. The wall value is strictly increasing even
when the system clock stalls or steps backwards, so a 1.5 peer that only reads
`updated_at` still sees a newer version.

- Outbox payloads carry `hlc_counter` and `fv`.
- `fv` contains every tracked field version, not only the fields changed by the
  statement, so an unrelated later row edit cannot overwrite a field edited on
  the other device through the row-version fallback.
- Incoming wall clocks are clamped to `now + 10 minutes`.
- A phone records the median of the last five `serverTimeMs` samples in
  `sync.clock_skew_ms`; local trigger versions use that corrected clock.
- `sync_clock` is advanced on receive with the standard HLC rule.

### Per-field merge

First wave: `todo`, `project_task`, `event`, `habit`, `project`.

The applier compares each field version before writing. Losing values are
recorded in `sync_conflicts`; rich note/description text still uses the
deterministic merge divider. Legacy payloads without `fv` keep the unchanged
row-level path, and unknown keys are ignored, so 1.5 peers continue to sync.

### Network guard (S5)

`NetworkGuard` accepts loopback, RFC1918, link-local and IPv6 unique-local
addresses. CGNAT (`100.64.0.0/10`) is opt-in through
`sync.allow_cgnat`. Every request is checked before authentication; blocked
requests receive `403 network_not_allowed`.

### Capabilities and pairing

- Server advertises `sync-hlc-v1`, `sync-fields-v1` and `sync-skew-v1`.
- Health, status, pairing, changes and snapshot responses include
  `serverTimeMs`.
- Pairing codes are 10 Crockford base32 characters and compare in constant
  time.

### Tombstone GC (S3, partial)

`SyncTombstoneGc` removes tombstones older than 180 days when no outbox row
references them and every currently paired client has acknowledged the outbox
head. It records `sync.tombstone_horizon_ms`, and snapshot/status/changes
responses expose `tombstoneHorizonMs`. The returning-phone "delete locally
below the horizon" rule is not wired into `MobileSyncClient` yet.

### Sync activity (S4, storage)

`SyncActivityService` writes one `sync_log` row per applied push, lists the last
50 attempts, lists open `sync_conflicts`, marks them reviewed, and prunes both
after 30 days. The Settings Activity/Conflicts panel and Restore-mine action
are still pending.

### Token lifetime (S6, partial)

Paired clients carry `tokenIssuedAt`, `tokenExpiresAt`, `lastSeenAt` and
`lastSeenIp`. Authentication slides a 90-day expiry, returns
`401 token_expired`, and `POST /api/v1/token/rotate` issues a new token while
keeping the previous one valid for five minutes. The phone rotates when fewer
than 14 days remain. Per-IP exponential pairing backoff is still pending.

## Not yet implemented

- Returning-phone tombstone-horizon resync rule (S3).
- Settings Activity/Conflicts UI and Restore-mine (S4).
- Per-IP pairing backoff; token-expiry grace retry on the phone (S6).
- Bluetooth RFCOMM transport (1.8), Windows closed-app reminders/presence
  (1.7), Linux (1.9) and iOS (2.0).

## Tests

- `test/sync_hlc_test.dart` — two devices edit different fields offline and
  converge; a far-future version is clamped.
- `test/sync_versioning_test.dart` — existing row-level version tests still
  pass.
- `test/network_guard_test.dart` — private/public/CGNAT ranges.
- Schema upgrade suites cover every released version through v23.
