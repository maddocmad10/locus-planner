# Phase C: recovery

Phase C makes the encrypted installation recoverable without weakening the
local-first and offline constraints. It adds three separate workflows:

1. **Raw database recovery** from a self-contained `.locusrecovery` package.
2. **Logical restore** into a brand-new encrypted installation.
3. **Start fresh**, which quarantines the current installation and creates a new
   identity.

The workflows are never conflated. A raw-recovery passphrase unwraps the
original database key and attachment key. A logical-backup passphrase only
decrypts that backup. The UI states which credential is required.

## Recovery packages (decisions C3 and C5)

A package is a ZIP file with a fixed layout:

```text
manifest.json                 identity, schema, checksums, file list
recovery.json                 versioned RecoveryBundle (DEK + attachment key)
database/locus_planner.db     encrypted VACUUM INTO snapshot
attachments/ab/<file-id>      sealed attachment blobs (optional)
attachments/thumbs/<id>.t     sealed thumbnails (optional)
```

Creation runs while the planner is live:

- A second keyed connection runs `VACUUM INTO`, so the snapshot is a consistent
  encrypted copy and does not depend on copying a live WAL by hand.
- The manifest records the database ID, key ID, generation, cipher profile,
  schema version, SHA-256 and size of the snapshot, and per-attachment
  plaintext/sealed checksums.
- The recovery envelope reuses the existing version-2 `RecoveryBundle` and
  PBKDF2-HMAC-SHA256/AES-256-GCM implementation. It wraps the DEK and, when
  attachments are included, the 32-byte device attachment key under a separate
  `attachment-key` purpose.
- If a blob listed by `attachments`/`attachment_blobs` is missing, it is skipped
  and counted in `skippedAttachmentCount`; the UI reports the count.
- The new package is reopened and fully verified before the UI reports success:
  every checksum, every attachment (decrypted and hashed chunk by chunk), the
  envelope identity, the database identity anchor, `PRAGMA integrity_check` and
  the schema version.
- Wrong passphrases, truncation, a flipped byte, an edited manifest, an
  identity mismatch, a newer schema and unsafe archive paths all fail closed.

Verification streams files out of the archive. Attachment validation uses
`AttachmentCrypto.sealedFileSha256`, which decrypts one 64 KiB chunk at a time
and never holds a whole blob in memory.

## Staged restore (decision C4)

Raw and logical restores are **staged**, not applied while the app is running:

- `RecoveryRestoreService.stage` verifies the package into
  `recovery/staged-<timestamp>/` inside the data directory.
- The recovered DEK is written to a dedicated **staged** key slot in the OS
  key store. It never overwrites the live key slot.
- The attachment key is written to a staged slot in the attachment key store.
- A `RestoreJournal` records the target identity, previous identity, checksums,
  quarantine path and stage. It is written before any live file moves.

At the next start, `DatabaseBootstrap.open` acquires the exclusive lifecycle
lock and applies the journal **before** classification:

1. Verifies the staged database checksum and identity again.
2. Quarantines the live database, WAL/SHM/journal, metadata and migration/
   rotation journals.
3. Atomically copies the staged database into place.
4. Writes the new metadata and key record, activates it and removes the staged
   key slot.
5. For raw packages with attachments, moves the old attachment store to
   quarantine, installs the verified blobs and writes the recovered attachment
   key.
6. Verifies the installed identity, then clears the journal and staging area.

A failure attempts a rollback from quarantine, keeps the journal for a retry and
never deletes the previous database. A colliding key ID from another
installation is stashed in a staged rollback slot before the recovered key takes
the live slot.

Raw recovery retains the original database ID, key ID and generation. It is a
restore of the same database, not a new installation.

## Logical restore (decisions C1, C8 and C9)

`LogicalRestoreService` reads plain JSON or `.locusbackup` files (the latter is
decrypted with its own passphrase). It:

- creates a new database ID, key ID, DEK, device ID and sync epoch;
- creates a new encrypted database at the current schema and imports the
  logical rows with `DataExportService.restoreFromJson`;
- suppresses outbox capture while importing, then deletes any outbox rows;
- clears the paired-client list and disables auto-start LAN sync;
- stores non-secret provenance (`restore.source_database_id`,
  `restore.source_backup_sha256`, `restore.source_exported_at`,
  `restore.timestamp`, `restore.generation`);
- sets `sync.rebase_required=1`;
- keeps local attachment blobs (the imported metadata can reuse them) and does
  not replace the attachment key;
- stages the result with the same `RestoreJournal` used by raw recovery.

The logical restore deliberately does **not** import old device identity, pairing
tokens, outbox rows or stale session state.

### Sync rebase

Guided re-pairing is the chosen strategy:

- Desktop auto-start refuses to run while `sync.rebase_required` is set. The
  user enabling LAN sync in Settings clears it deliberately.
- Mobile sync unpairs and asks the user to scan the desktop QR code again; a
  successful pairing clears the flag.
- A new epoch means old peers cannot push stale changes into the restored
  database.

## Start fresh (decision C6)

`StartFreshService.request` only writes a small request file. At the next start:

- the old database, sidecars, metadata, migration/rotation/restore journals and
  `attachments/` directory move into `quarantine/start-fresh-<timestamp>/`;
- a `manifest.json` records the previous identity and explains the retention
  rule;
- **key records and recovery envelopes are preserved**;
- the normal fresh-install path creates a new database ID and the next key
  generation;
- the request is cleared only after the new metadata exists.

Quarantine cleanup is manual only. The same rule applies to raw/logical restore
quarantine directories.

## Recovery UI (decision C7)

The existing database-protection card now offers:

- Create recovery key (also writes a managed envelope copy).
- Create recovery package.
- Verify recovery package.
- Restore raw database package.
- Restore logical backup as new database.
- View database identity.
- Change recovery passphrase.
- Start fresh.
- Review old artifacts (size, date and explicit delete).

The startup error screen also offers recovery from a key file and from a
`.locusrecovery` package.

## Recovery envelopes (decisions C10 and C11)

Managed envelopes live under `recovery/envelopes/`:

- Each write creates `envelope-<microseconds>-<key>.json`.
- A passphrase change reseals the same DEK (and, when present, the attachment
  key and backup passphrase) into a new envelope, then renames the previous
  file with a `retired-` prefix.
- A DEK rotation marks all managed envelopes retired. The user creates a new
  recovery key for the new identity.
- Envelopes are never overwritten in place and never stored in the database.

## Limits and non-goals

- Logical restore currently accepts logical JSON/`.locusbackup` backups.
  `.locusarchive` (logical backup plus attachment bytes) still uses the Phase 5
  import flow into the current database.
- Raw packages include sealed attachments only when the device holds the
  attachment key and the files are present.
- Physical-device validation of package creation/restore on Android is still
  required; the automated tests use the Windows SQLite3MC runtime.
- Recovery does not fetch any content from the network.

## Tests

- `test/recovery_package_test.dart`: live-connection package creation,
  verification, wrong passphrase, truncation, attachments on/off, envelope
  attachment key, clean-install apply, sealed-file tamper detection.
- `test/logical_restore_test.dart`: new identity/key/epoch/device, settings and
  provenance, outbox clearing, quarantine, encrypted backup credential,
  encrypted/plain backups and staged-request rejection.
- `test/start_fresh_test.dart`: quarantine, key preservation, new generation,
  request clearing, artifact listing/deletion, managed envelope rewrap and
  retirement.
