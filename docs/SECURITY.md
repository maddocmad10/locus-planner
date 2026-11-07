# Security notes

Locus is local-first. Data lives in the SQLite file on this machine and, when
the user pairs a phone, travels over the authenticated LAN sync connection.
This page states exactly what the app lock and encrypted backups protect, and
what stays in plain form.

## App lock (Windows and Android)

- The PIN is never stored. A salted PBKDF2-HMAC-SHA256 verifier is kept in the
  operating system's credential store (`locus.app_lock.pin`): Windows protected
  storage / Android Keystore. The database file does not contain the PIN.
- The app starts locked whenever a PIN is configured. Returning from the
  background locks after the user's chosen grace period (immediately, 30 s,
  1 min, 5 min or 15 min).
- Wrong attempts are rate limited: the first four are free, the fifth starts a
  30-second wait, then 60 s, 120 s, doubling up to 15 minutes. The counter and
  lock-out time are persisted in the verifier record, so killing the app does
  not reset them. Moving the system clock backwards does not shorten a wait.
- Key derivation runs on a worker isolate; the UI thread is not blocked.
- If the verifier record cannot be read or is damaged, the lock fails open:
  the user is not locked out of their own data. The error is logged and Settings
  shows a notice asking for a new PIN. This is a deliberate availability
  trade-off.
- On Android, `FLAG_SECURE` is set while the lock is enabled, so the recent-apps
  thumbnail and screenshots do not show planner content. The lock overlay is
  installed above the Navigator, so dialogs and pushed routes are covered too.
- Windows notifications may still show event/task titles on the lock screen;
  the app lock does not control the operating system's notification surface.

## Encrypted backups (`.locusbackup` and `.locusdiary`)

- Both file types use the same envelope: AES-256-GCM with a key derived from
  the passphrase with PBKDF2-HMAC-SHA256 (210,000 iterations by default).
  Version 2 normalizes the passphrase with NFC. Version 1 diary files written
  before the rewrite remain readable and use the raw old passphrase bytes.
- The authenticated data includes the format version, payload type, iteration
  count and normalization. Editing the header, the ciphertext or the tag makes
  decryption fail.
- The passphrase is never stored for manual exports. For unattended automatic
  backups it is kept in the OS credential store (`locus.backup.passphrase`);
  restoring still requires typing it.
- If automatic encryption is enabled but the passphrase cannot be read, the
  backup fails closed. The app never falls back to writing a plain JSON file.
- "Export Full Data (JSON)" remains available but is **not encrypted**. The
  diary and daily intentions are readable in that file. The UI warns before the
  first plain export.
- Restoring an encrypted diary backup never writes on top of newer local text
  without a choice: the user sees new / identical / different counts and picks
  Keep mine, Replace with backup, or Keep both. A recovery backup is written
  before any change.
- Deleting old unencrypted backups only removes `auto_*`, `manual_*` and
  `pre_import_*` `.json` files; `.locusbackup` files are left alone.

## Local attachments

Attachment **metadata** is ordinary database rows (`attachments`): the
sanitized display name, content-sniffed MIME type, size, SHA-256 and the owning
to-do or event. The **bytes** never live in SQLite. They are written under the
application-support directory:

```text
attachments/ab/<file-id>        sealed blob
attachments/thumbs/<file-id>.t  sealed 256 px thumbnail
attachments/tmp/                partial imports and open copies
```

- Each device generates a random 32-byte attachment key and stores it in the
  operating system credential store (Windows DPAPI / Android Keystore). It is
  deliberately independent of the database key in this phase, so enabling live
  database encryption later does not invalidate existing attachments.
- Blobs use AES-256-GCM in 64 KiB chunks (`LATTCH1` header). The chunk counter
  is authenticated, so truncation and reordering fail closed. The on-disk name
  is an HMAC-SHA256 of the plaintext hash, which gives deduplication without
  exposing content hashes in the file system.
- The key is never written to the database, a logical backup or the sync
  outbox. `attachment_blobs` holds only local cache state and is excluded from
  both sync and backup.
- Android cloud backup and device transfer exclude `attachments/`, for the same
  reason as the database: the key does not travel.
- Metadata syncs to a paired desktop; blob transfer is not implemented in this
  version. The logical backup (`format_version` 4) carries attachment metadata
  with `attachments_included: false` and never carries bytes.
- Import treats every file as untrusted input: names are sanitized, MIME is
  sniffed from magic bytes, executable/script extensions are refused, images
  are decoded in a worker isolate with a 50-megapixel cap, EXIF (including GPS)
  is stripped by default, and SVG/HTML are never rendered in-app.
- Nothing is auto-opened. A user tap decrypts a copy into the temporary folder
  and hands it to the operating system; the copy is removed at exit and at the
  next startup. On Android the copy is exposed only through a non-exported
  `FileProvider` scoped to `attachments/tmp/open/`.
- Blob sync uses the existing pinned-TLS, bearer-token LAN connection. Files
  are plaintext inside that authenticated connection; each device seals them at
  rest with its own key. Uploads require `Content-Length`, are capped at 25 MB,
  are hashed before commit and are limited in concurrency. Downloads support
  single Range requests and are hash-verified by the receiver.
- `.locusarchive` files use a chunked AES-256-GCM envelope: PBKDF2-HMAC-SHA256
  with NFC-normalized passphrases, a random salt and nonce base, and 64 KiB
  authenticated chunks. The header, chunk counter and final-chunk flag are
  authenticated data, so truncation, reordering and bit flips fail closed.
  The archive includes attachment bytes; the logical `.locusbackup` still does
  not.

## What is stored in plain form

The database is not encrypted at rest. Anyone with file access and the right
SQLite tools can read:

- diary entries and daily intentions;
- to-do titles, notes, tags and dates;
- event titles and descriptions;
- habit names and completion history;
- project names and progress notes;
- attachment metadata (display name, MIME type, size and content hash).

Attachment bytes are sealed with the device-local attachment key, but that key
is protected by the operating-system profile, not by the database file. The app
lock protects the running app, not the database file. Encrypted backups protect
files that leave the machine. Full-disk encryption (BitLocker, Android
file-based encryption) is the recommended protection for the database itself.

## ICS import

Calendar files are read locally. The importer resolves `TZID` values with the
IANA timezone database and a small Windows-name mapping table. Unknown zones
fall back to floating local time and are counted in the import report. Imported
events are ordinary planner rows; the source `.ics` file is not retained.

## Dependencies

PBKDF2/AES-GCM come from PointyCastle and the shared key-derivation helper.
Passphrase normalization uses `unorm_dart`; timezone resolution uses `timezone`.
Both are pinned exactly in `pubspec.yaml` and recorded in `docs/DEPENDENCIES.md`.
