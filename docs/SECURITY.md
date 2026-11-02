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

## What is stored in plain form

The database is not encrypted at rest. Anyone with file access and the right
SQLite tools can read:

- diary entries and daily intentions;
- to-do titles, notes, tags and dates;
- event titles and descriptions;
- habit names and completion history;
- project names and progress notes.

The app lock protects the running app, not the database file. Encrypted backups
protect files that leave the machine. Full-disk encryption (BitLocker, Android
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
