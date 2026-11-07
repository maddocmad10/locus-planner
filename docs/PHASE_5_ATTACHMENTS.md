# Phase 5: rich notes and local attachments

Schema **v21** adds the first part of Workstream B from the 1.5.0 plan: a
format marker for rich notes, plus local-only file and image attachments. It
extends the existing Drift schema, Riverpod providers, sync outbox and logical
backup; it does not replace them.

This phase is deliberately local-first. Attachment **metadata** travels through
the existing JSON sync channel. Blob sync (`.locusarchive`, Range downloads,
`.locus-att://` resolution) is **not** part of this phase.

## Schema changes (v20 → v21)

Additive only:

- `todo_items.notes_format TEXT NOT NULL DEFAULT 'plain'`
- `events.description_format TEXT NOT NULL DEFAULT 'plain'`
- `attachments` — synced metadata with two nullable parents and a CHECK that
  exactly one is set:
  `id, todo_id, event_id, kind, display_name, mime_type, size_bytes, sha256,
  width, height, position, created_at, updated_at`
- `attachment_blobs` — device-local cache state; never synced and never in a
  logical backup:
  `sha256, size_bytes, state, has_thumb, pinned, last_accessed_at,
  orphaned_at, fail_count`
- Indexes on `attachments(todo_id)`, `attachments(event_id)` and
  `attachments(sha256)`.

The v21 step is guarded with `_columnExists`/`_tableExists` so a migration that
starts from v16, v19 or v20 is idempotent. Existing rows keep `plain`. The sync
epoch is **not** rotated: the new columns have safe defaults and attachment
rows are new.

Outbox triggers are rebuilt for `todo_items` and `events` so their payloads
include the format columns, and new insert/update/delete triggers cover
`attachments`. `attachment_blobs` has no trigger by design.

## Format marker

Allowed values are `plain` and `md1`; anything else is coerced to `plain` on
write, sync and restore, so an older build always shows readable text.

`md1` is intentionally small: paragraphs, bold, italic, strikethrough, H1–H3,
unordered/ordered lists, task checkboxes, block quotes, fenced/inline code,
`[label](url)` links and `![alt](locus-att://<id>)` image references. Raw HTML
is never interpreted. Links are rendered as underlined text but are not opened
from the preview, and image references render as a labelled placeholder — a
note is untrusted content, and a preview must not leak IP addresses or reading
times.

## Files on disk

```text
attachments/ab/<file-id>        sealed blob
attachments/thumbs/<file-id>.t  sealed thumbnail
attachments/tmp/                partial imports and open copies
```

`<file-id>` is `HMAC-SHA256(attachKey, sha256hex)` so identical content
deduplicates without exposing the plaintext hash. Blobs are `LATTCH1` +
AES-256-GCM in 64 KiB chunks; the nonce is `prefix ‖ counter`, and the
associated data binds the header, counter and final-chunk flag. A missing,
truncated, reordered or modified chunk fails authentication.

The 32-byte `attachKey` is random per device and lives in
`flutter_secure_storage` (Windows DPAPI / Android Keystore). It is independent
of the database key, so later database encryption does not invalidate existing
attachments. It is not backed up and not synced; copying `attachments/` to
another device therefore produces unreadable files.

## Limits and processing

| Rule | Value |
| --- | --- |
| Max file size | 25 MB |
| Max attachments per item | 20 |
| Soft quota (warning) | 1 GB on the device |
| Image long edge | 2048 px |
| Thumbnail edge | 256 px |
| Image pixel cap | 50 megapixels |
| Orphan grace | 7 days |

Images are decoded in a worker isolate with the `image` package, auto-oriented,
downscaled and re-encoded as JPEG q85 (PNG when the source has alpha). EXIF is
stripped by re-encoding. `Settings > Security > Attachments > Keep original
images` stores the original bytes and preserves EXIF; the thumbnail and pixel
cap still apply.

MIME is sniffed from magic bytes. Executable and script extensions
(`.exe .msi .bat .cmd .ps1 .vbs .js .jar .lnk .scr .apk`, …) are refused, as is
PE content regardless of extension. Display names strip path separators and
control characters, collapse dots, trim to 120 characters and avoid Windows
reserved names. Disk names never derive from the display name.

## User flow

- Windows task/event dialogs and the mobile editors show a `NotesField` with an
  Edit/Preview switch and an `AttachmentStrip`.
- A new item shows “Save this item first…” because an attachment needs a real
  parent id.
- Add uses `file_picker`; images show a sealed thumbnail and open in an
  `InteractiveViewer`. Non-images use the Windows file handler; mobile shows
  metadata until the FileProvider/share flow lands.
- Delete and Undo reinsert the metadata row and clear `orphaned_at`. A startup
  sweep deletes blobs that have had no live reference for 7 days, plus
  untracked files older than one hour.

## Backup and sync

- Logical backup is now `format_version: 4`. It gains an `attachments`
  metadata section and always writes `attachments_included: false`. A v4 backup
  restores metadata through the normal merge path; it never carries blob bytes.
  A backup without the section leaves local attachments untouched.
- `attachment_blobs` and the `attachments/` directory are excluded from that
  backup.
- Android `backup_rules.xml` and `data_extraction_rules.xml` exclude
  `attachments/` for cloud backup and device transfer.
- New peers receive attachment metadata as ordinary outbox rows. Older peers
  ignore the new entity type. `SyncChangeApplier` validates the parent pair and
  cascades tombstones when a parent disappears.

## B3: blob sync

The desktop server advertises `attachments-v1` and `maxBlobBytes` through
`GET /api/v1/status` (and `/api/v1/health`). New authenticated routes:

- `POST /api/v1/blobs/missing` — up to 200 SHA-256 hashes, returns the subset
  the desktop does not hold.
- `PUT /api/v1/blobs/{sha256}` — requires `Content-Length` (411 otherwise),
  caps the body at 25 MB, limits concurrent uploads, probes free disk space
  (best-effort), hashes while receiving, rejects a mismatch with 422, and only
  then seals the file into the content-addressed store.
- `GET /api/v1/blobs/{sha256}` — returns the decrypted bytes with
  `Accept-Ranges: bytes`; single `Range` requests receive 206 and
  `Content-Range`, invalid ranges receive 416.

The phone client checks the capability advert before doing any file work. It
uploads local blobs the desktop lacks, then pushes metadata, pulls metadata and
finally downloads blobs referenced by live rows. Downloads resume from a partial
file with a Range request, verify the plaintext hash, regenerate a 256 px
thumbnail for images, and record `present` / `failed` in `attachment_blobs`.
`Settings > Security > Attachments` offers **Auto** (files and images up to
2 MB), **All** and **Manual**. A 500 MB LRU cap evicts non-pinned blobs; pinned
blobs survive.

## B4: notes conflicts

`SyncChangeApplier` now merges a losing note or event description into the
winner with the deterministic `diaryMergeDivider` used by the diary. The check
is idempotent, so replaying the same change does not duplicate text. The merged
row is re-saved with outbox capture on, so the origin device and any other
paired phone receive the result. `md1` wins if either side used it.

## B5: `.locusarchive`

`LocusArchiveService` writes a logical backup plus its blobs to a
`.locusarchive` file:

- Plaintext container: `LOCUSARC1\n`, a JSON manifest (backup + blob list),
  then per-blob `sha256` / length / bytes.
- Encrypted wrapper: `LOCUSARC1E\n`, version, PBKDF2 iteration count, salt,
  nonce base and plaintext length, followed by 64 KiB AES-256-GCM chunks. AAD
  binds the header, counter and final flag.
- Restore verifies every hash before writing, skips a blob that already exists,
  writes missing blobs, and reports missing hashes without failing the metadata
  restore. A wrong passphrase, flipped byte, reordered chunk or truncated file
  fails closed.
- Settings > Data Management adds **Export Archive with Attachments** and
  **Import Archive (.locusarchive)**.
- ICS export appends “N attachment(s) omitted”; ICS import counts and ignores
  `ATTACH` without ever fetching it.

## B6: hardening

- Android openings use a `FileProvider` (`${applicationId}.fileprovider`) and
  only expose `attachments/tmp/open/`; the sealed blobs are never shared.
- Note links are only live for `http`, `https`, `mailto` and `locus-att`, and
  only open after a tap. Image references stay placeholders; no remote image is
  ever loaded.
- The app-lock overlay already covers thumbnails, the viewer and the open
  action because it sits above the Navigator.
- List subtitles use `plainTextFromMd1`, so raw markup is not shown in compact
  UI (reminders and widgets can use the same helper).
- Diagnostics must not log file names or paths; the picker error text was
  reduced to a generic message.

## B7: UI

- `Attachments` is reachable from Windows task/event dialogs and the mobile
  editors, with Edit/Preview notes and a semantic label on every tile.
- Paperclip badges with counts appear on task and event rows.
- The command palette also matches attachment display names and surfaces their
  parent task/event.
- Windows supports drag-and-drop onto the attachment strip.
- Metadata-only rows show a placeholder with **Download** and **Keep on this
  device** actions on the phone.

Still intentionally deferred: clipboard-image paste (needs a native clipboard
plugin spike), an explicit alt-text column (the sanitized display name is used
as the accessible label), and inline `locus-att://` image rendering inside the
note preview.

## Tests

- `test/phase5_migration_test.dart` — v16/v19/v20 → 21, rows intact, formats
  default to `plain`, triggers rebuilt, attachment metadata outboxed, one-parent
  CHECK enforced, `attachment_blobs` never triggers.
- `test/phase5_attachments_test.dart` — chunked crypto round-trip/tamper/
  truncation, content-addressed dedupe, plaintext absence on disk, name/MIME
  policy, service import/remove/Undo/limits, stable positions, backup v4
  metadata-only restore and the device-local image policy exclusion.
- `test/phase5_notes_widget_test.dart` — `md1` rendering (emphasis, tasks,
  image references, raw HTML), Edit/Preview format switch, new-item hint and
  attachment error/retry UI.
- `test/phase5_notes_merge_test.dart` — losing/winning notes and event
  descriptions, idempotent replay and the shared divider.
- `test/phase5_blob_sync_test.dart` — status advert, missing, upload, full and
  Range download, hash mismatch and bearer-token enforcement.
- `test/phase5_mobile_blob_sync_test.dart` — end-to-end phone ↔ desktop blob
  exchange, metadata order and the manual download policy.
- `test/phase5_archive_test.dart` — archive round-trip, wrong passphrase,
  tampered byte, missing-blob reporting.
- `test/phase5_ics_attachments_test.dart` and `test/md1_plain_test.dart`.
- `test/schema_upgrade_test.dart` — every released step, including 20 → 21.
