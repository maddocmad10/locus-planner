# Release decisions — Sections A, B and C

Recorded: 2026-11-18 (A/B), 2026-11-19 (C)

These decisions unblock the deferred release/security items in the Section A
list, the Section B attachments/UI list, and the Phase C recovery list. They are
product/operations decisions, not implementation status. Update this file when a
decision changes.

## 1. Live database encryption rollout

**Decision: new installs only.**

- Fresh databases are encrypted; existing plaintext databases remain untouched
  for 1.5.0.
- Automatic conversion of existing databases is not enabled in this release.
- The staged beta/migration rollout is off the table for 1.5.0 and can be
  reconsidered in a later release.

## 2. Recovery-key flow

**Decision: import + rotate.**

- Ship a recovery-key import flow in addition to creation/export.
- After importing a recovery bundle and restoring the DEK, rotate the database
  key so the old recovery bundle cannot be reused.
- The recovery flow remains passphrase-based and never stores the passphrase.

## 3. Release signing and distribution

**Decision: Play App Signing + OV Windows certificate.**

- Android uses Play App Signing with the upload key held by the project.
- Windows uses an OV code-signing certificate and the existing direct-download
  installer/ZIP route.
- EV, cloud signing and Microsoft Store distribution are not selected for
  1.5.0.

## 4. Encryption proof in CI

**Decision: require an encrypted fresh database.**

- CI/release smoke tests must fail when a freshly created release database
  starts with the plain SQLite header.
- This gate is required as part of enabling encryption for new installs.

## 5. Licence and public distribution

**Decision: proprietary EULA + Play/download.**

- Android ships through Google Play.
- Windows ships as a direct download with SHA-256 checksums and signature
  verification instructions.
- The repository licence must be changed from MIT to a proprietary EULA naming
  the legal holder.
- Microsoft Store distribution is not selected.

## 6. Android adaptive icon and Windows icon frames

**Decision: commission an adaptive set.**

- A designer supplies Android adaptive foreground/background/monochrome layers
  and Windows ICO frames at 16, 24, 32, 48, 64, 128 and 256 px.
- The tray icon is produced at 16 and 32 px with crisp edges.

## 7. Android package size

**Decision: AAB with ABI splits.**

- Publish an Android App Bundle for Play so per-device native libraries are
  delivered separately.
- Keep the currently shipped ABIs unless a later ABI decision says otherwise.
- A universal APK is not the primary public artifact.

## 8. Obfuscation and symbols

**Decision: obfuscate + archive symbols.**

- Release builds use `--obfuscate --split-debug-info`.
- Symbols are archived privately per release so crash traces remain readable.
- Symbols must never be attached to public release artifacts.

## 9. 16 KB page alignment and target SDK

**Decision: rebuild SQLite3MC for 16 KB and confirm the current Play target.**

- Rebuild the bundled SQLite3MultipleCiphers native libraries with 16 KB
  page-size compatibility.
- Verify the current Play target-SDK requirement at submission time.
- Keeping 4 KB libraries or dropping SQLite3MC are not selected.

## 10. Crash reporting

**Decision: email report only.**

- No crash-reporting SDK is added.
- The diagnostics ZIP plus a pre-addressed support email is the support path.
- If this changes later, the privacy policy and Play Data Safety form must be
  updated first.

## 11. Android native reminder log

**Decision: Kotlin ring buffer.**

- Implement a rolling, content-free 200-entry reminder delivery buffer in the
  Android alarm service.
- Record scheduled, fired and skipped-late outcomes, lateness and alarm type.
- Include the native snapshot in the diagnostics ZIP.

## 12. App-lock behavior for attachments

**Decision: rely on the existing overlay.**

- The lock overlay remains above routes and dialogs; thumbnails, the viewer and
  open actions are considered covered.
- No additional lock-state gating of `AttachmentStrip` is required for 1.5.0.

## Implementation status

- **1. New installs only:** implemented. Release builds enable encryption;
  existing plaintext databases open unchanged. The runtime encryption flag is
  set from the actual connection, so Settings and backup policy do not claim a
  plaintext database is encrypted.
- **2. Import + rotate:** implemented as a startup recovery button. It imports
  the recovery bundle, writes the recovered key/metadata, rotates the key and
  asks the user to restart.
- **3. Play + OV Windows:** build/signing gates and AAB/obfuscated release
  workflow are in place. The actual OV certificate, Play App Signing enrollment
  and repository secrets remain external.
- **4. Require encrypted DB:** implemented in Windows CI/release smoke tests via
  `tool/verify_release_bundle.dart --database`.
- **5. Proprietary EULA + Play/download:** the repository `LICENSE` is now a
  proprietary EULA and the store/download route is documented. Legal entity,
  privacy URL, support email and Play Console setup remain external.
- **6. Commission adaptive set:** the Android adaptive XML/assets are still
  waiting on the commissioned design; this is an external asset dependency.
- **7. AAB with ABI splits:** implemented in CI and the tagged Android release
  workflow; the AAB gate verifies every shipped ABI.
- **8. Obfuscate + archive symbols:** implemented for Windows and Android
  release builds; symbols are uploaded as separate CI artifacts.
- **9. Rebuild 16 KB + target:** the release gate work is ready, but the native
  SQLite3MC rebuild needs the external NDK/source build.
- **10. Email report only:** implemented; no crash SDK is added.
- **11. Kotlin ring buffer:** implemented and included in the diagnostics ZIP.
- **12. Rely on overlay:** no code change required; accepted.

## Section B: attachments and UI

### B1. Clipboard image paste

**Decision: Windows + Android paste.**

- Add a **Paste image** action and keyboard paste on Windows.
- Add the equivalent clipboard-image flow on Android.
- This is a new platform integration, not just a button around text paste.

### B2. Image alt text

**Decision: schema v22 `attachments.alt_text`.**

- Add a nullable `alt_text` column with a numbered Drift migration.
- Carry it through sync, backup/restore and `.locusarchive` metadata.
- Add an editor field for images; existing display names remain the fallback.

### B3. Android camera capture

**Decision: camera + file picker.**

- Add a Take photo action using the camera, alongside the existing file picker.
- Camera images use the same 2048 px/EXIF-stripping/thumbnail policy as imported
  images.

### B4. Android share-sheet intake

**Decision: add Send to Locus.**

- Add an intent filter and file-provider/runtime intake so sharing a file or
  image to Locus creates a task with that attachment.
- The incoming content must pass the same untrusted-input checks as the picker.

### B5. Inline images inside paragraphs

**Decision: standalone lines only.**

- Keep the current block renderer: an image on its own line renders; an image
  inside a paragraph remains a labelled placeholder.
- A richer mixed text/image renderer is out of scope.

### B6. Mobile attachment-name search

**Decision: add mobile search.**

- Add a mobile search surface that matches task/event titles, notes and
  attachment display names.
- Reuse the existing attachment queries and result navigation.

### B7. Automatic backups and attachment bytes

**Decision: opt-in per backup.**

- Automatic backups remain metadata-only by default.
- Add an opt-in setting/checkbox that lets automatic backups include attachments
  (as an encrypted archive), with a size warning and retention policy.
- Manual `.locusarchive` exports continue to include files when selected.

### B8. Reminder and widget note text

**Decision: titles only.**

- Reminder notification bodies and widget text remain title/generic only.
- Notes are never projected onto the lock screen or home-screen widget.

### Section B implementation status

- **B1. Clipboard paste:** implemented. Windows reads CF_DIB through
  `user32`/`kernel32` FFI and re-encodes to PNG; Android reads a clipboard
  content URI through `locus_planner/clipboard`. Both feed
  `AttachmentService.importBytes`, and Windows also binds `Ctrl+V` on the
  attachment strip.
- **B2. Alt text:** implemented as schema v22. `attachments.alt_text` is
  nullable, carried by the outbox payload, validated in `SyncChangeApplier`,
  restored from backups and archives, editable from the image tile, and used as
  the semantic label when present.
- **B3. Camera:** implemented. Android shows **Take photo** via `image_picker`
  and then applies the standard image pipeline.
- **B4. Share intake:** implemented. `MainActivity` handles `ACTION_SEND` and
  `ACTION_SEND_MULTIPLE`, copies each URI into `cacheDir/shared` and hands only
  those app-private paths to Dart; `_importSharedFiles` creates a task and
  attaches the files. Unreadable items are skipped individually.
- **B5. Standalone-line images:** kept. Mixed inline text/image rendering
  remains out of scope.
- **B6. Mobile search:** implemented as a mobile search page matching task
  titles and notes, event titles/descriptions and attachment display names,
  with navigation back to the owning task or event.
- **B7. Opt-in attachment backups:** implemented. The setting
  `backup.include_attachments` defaults off; when enabled, automatic backups
  write encrypted `.locusarchive` files through `AutoBackupService` using the
  configured passphrase and keep the existing retention policy.
- **B8. Titles only:** no change; reminder and widget text remain
  title/generic.

## Still externally required

- Privacy-policy HTTPS URL and support email address.
- Legal entity name for the EULA, installer publisher and code-signing
  certificate subject.
- Trademark/name-collision review for "Locus Planner".
- Play Console account/test-track setup and store listing assets.
- OV code-signing certificate and Play App Signing enrollment/secrets.
- Commissioned Android adaptive icon assets and Windows ICO frames.
- SQLite3MC 16 KB native rebuild (external NDK/source/toolchain).
- Physical Android validation of the encrypted fresh install, recovery import,
  clipboard paste, camera capture and share-sheet intake.

## Section C: recovery decisions

Recorded: 2026-11-19. Source: Phase C — Recovery implementation in
`schema1.docx`. Phase C services (`recovery_package_service`,
`database_recovery_service`, `logical_restore_service`, `restore_journal`,
`sync_restore_coordinator`) are not implemented yet; this section records the
choices to build against.

### C1. Sync rebase after logical restore

**Decision: guided re-pairing (Strategy B).**

- Disable automatic sync after a logical restore.
- Clear old pairing credentials from the active installation.
- Create a new device identity and pairing state, then require the user to
  re-pair.
- Perform a controlled full resync and reconcile newer peer data explicitly.
- Do not attempt Strategy A (restored snapshot as authoritative baseline) unless
  a later protocol change proves it can preserve deletions and pending changes.

### C2. Recovery envelope KDF

**Decision: PBKDF2-HMAC-SHA256.**

- Reuse the existing `KeyDerivation` path and backup-size iteration policy.
- Document the algorithm, iteration count, salt length and envelope version in
  `docs/DATABASE_ENCRYPTION_SCHEMA.md`.
- Keep the passphrase out of storage, logs, diagnostics and crash reports.

### C3. Raw recovery package format

**Decision: single `.locusrecovery` archive.**

- The archive contains the encrypted database, database identity, cipher
  profile, recovery envelope, format version, snapshot timestamp, checksums and
  the required sidecar inventory.
- It never contains the plaintext DEK or passphrase.
- The database copy is made only after writers stop, WAL is checkpointed and
  handles are closed.

### C4. Raw recovery install

**Decision: stage and swap.**

- Verify the package format, checksums, envelope identity and database integrity
  in quarantine before touching live files.
- Atomically swap the verified database, sidecars and metadata into place.
- Keep the previous files and key records for rollback until the user
  explicitly cleans them up.

### C5. Attachments in raw recovery

**Decision: include blobs and wrap the device attachment key.**

- Include the encrypted attachment store in the `.locusrecovery` archive.
- Wrap the device-local `attachKey` under the recovery envelope so a clean
  installation can read the blobs.
- Keep the raw-recovery passphrase and the attachment key separate from the
  logical-backup credential.
- A package without attachments remains valid and restores metadata only.

### C6. Start-fresh cleanup

**Decision: manual only.**

- Quarantine the old database, sidecars, metadata, journals, key records and
  envelope references.
- Keep the previous database and key recoverable until the user confirms
  deletion from **Review old artifacts**.
- Never reuse an old database ID with a new DEK.

### C7. Recovery UI placement

**Decision: extend the existing database-protection Settings card.**

- Add create, verify, export, raw restore, logical restore, change passphrase,
  identity/status, start fresh and review-artifacts actions to the card.
- Use dialogs for the individual operations; no separate recovery page in this
  phase.
- Recovery-package success is reported only after the exported file has been
  re-read, decrypted and identity-checked.

### C8. Logical-backup credentials

**Decision: prompt on every restore.**

- Never store the logical-backup passphrase in the application or OS key store.
- Request it at restore time and fail closed on a wrong or missing credential.
- The raw-recovery passphrase does not decrypt a logical backup; the UI must say
  so explicitly.

### C9. Sync epoch on restore

**Decision: rotate the sync epoch.**

- Logical restore creates a new database ID, key ID and DEK.
- It also creates a new device ID and a new sync epoch.
- Old epochs are rejected, so stale peers cannot overwrite restored state.
- Re-pairing is required before sync resumes.

### C10. Envelope lifecycle after rotation

**Decision: versioned and retired.**

- Create a new recovery envelope for the new key identity after a DEK rotation.
- Mark older envelopes as belonging to the retired database/key identity instead
  of deleting them immediately.
- Retired envelopes are retained for audit and rollback, and removed only by an
  explicit cleanup.

### C11. Changing the recovery passphrase

**Decision: rewrap the envelope.**

- Decrypt the existing envelope and re-encrypt the same DEK under the new
  passphrase into a new envelope version.
- Do not rotate the database DEK for a passphrase-only change.
- A separate database-rotation action remains available for suspected key
  compromise.

### C12. Delivery order

**Decision: C1 -> C2 -> C3 with separate gates.**

- C1: recovery package creation, verification and clean-install raw recovery.
- C2: logical restore, new identity creation and guided sync re-pairing.
- C3: start fresh, artifact quarantine/review and the operational recovery UI.
- Do not merge the three into one patch; each phase must pass its own exit gate.
- Production conversion remains disabled until raw recovery is tested, a
  verified recovery package or logical backup exists, crash injection and
  parity pass, and both release builds pass.

### Section C implementation status

- **C1. Sync rebase:** implemented as guided re-pairing. `sync.rebase_required`
  blocks desktop auto-start and forces mobile sync to unpair; a manual desktop
  enable or a successful mobile pairing clears it.
- **C2. KDF:** implemented with the existing PBKDF2-HMAC-SHA256 path
  (`RecoveryEnvelopeService`, 600,000 default iterations, NFC normalization).
- **C3. Package format:** implemented as a ZIP `.locusrecovery` with manifest,
  envelope, `VACUUM INTO` database snapshot and optional sealed attachments.
- **C4. Raw install:** implemented as stage-and-swap with quarantine, rollback,
  checksum re-verification and atomic replacement.
- **C5. Attachments:** implemented. Packages include sealed blobs, thumbnails
  and an `attachment-key` envelope entry; clean-install restore writes the key
  and blobs. Packages without attachments remain valid.
- **C6. Start fresh:** implemented as a request applied at the next start. Old
  files move to quarantine; key records and envelopes are preserved; cleanup is
  manual through Review old artifacts.
- **C7. UI:** implemented on the existing database-protection Settings card,
  with identity/status, package create/verify, raw restore, logical restore,
  passphrase change, start fresh and artifact review. The startup error screen
  also stages packages.
- **C8. Credentials:** implemented. Logical and raw passphrases are requested
  per operation and never stored. The raw passphrase is not reused for logical
  backups.
- **C9. Epoch:** implemented. Logical restore creates a new device ID and epoch,
  clears paired clients and outbox rows, and records provenance.
- **C10. Envelope lifecycle:** implemented with versioned files under
  `recovery/envelopes`; rotation marks all managed envelopes retired.
- **C11. Passphrase change:** implemented by rewrapping the same DEK into a new
  envelope version; no database rotation.
- **C12. Delivery:** implemented in C1 -> C2 -> C3 order with separate tests
  (`recovery_package_test.dart`, `logical_restore_test.dart`,
  `start_fresh_test.dart`). Crash-injection and physical-device validation
  remain release gates.

## Section D: database encryption architecture (confirmed)

Confirmed on 2026-11-19 against the D1–D12 locked decisions in
`Locus_Planner_Database_Encryption_Implementation_Schema_v1.1_Review_Verified`
(§3). No changes were requested.

| ID | Decision | Current status |
| --- | --- | --- |
| D1 | SQLite3MC, fail closed | Implemented with the pinned native library and runtime verification. |
| D2 | One frozen cipher profile | Implemented as `locus-sqlcipher4-raw-v1`, stored in the identity. |
| D3 | One random 256-bit DEK per identity | Implemented with versioned key IDs and generations. |
| D4 | Identity anchor inside the DB, metadata as a hint | Implemented; every open compares the internal anchor with the external hint. |
| D5 | Single connection factory | Implemented through `DatabaseBootstrap`; direct SQLite opens are limited to security tooling/tests. |
| D6 | Fail closed to recovery | Implemented; missing key/metadata, unknown profile and wrong keys never create a new DB or plaintext fallback. |
| D7 | Preserve plaintext until verified | Implemented in the conversion journal/candidate flow; automatic conversion remains disabled for 1.5.0. |
| D8 | Logical backups primary | Implemented; automatic backups are encrypted, and raw packages require the recovery credential. |
| D9 | Logical = new identity, raw = original identity | Implemented in Phase C. |
| D10 | Verified rotation, old key retained | Implemented; envelopes are rewrapped or retired after success. |
| D11 | Exclude sensitive state from OS backup | Implemented with Android rules and Windows non-roaming storage. |
| D12 | Explicit-consent plaintext cleanup | Implemented as **Review plaintext artifacts**: the legacy Documents copy and pre-encryption/quarantine plaintext databases are listed with size and date and deleted only after confirmation. |
