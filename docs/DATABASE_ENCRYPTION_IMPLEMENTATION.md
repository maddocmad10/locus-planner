# Database encryption — implementation status

**Status:** Phase A (reliability) and Phase B (native encryption) implemented;
Phase C is not implemented. Live encryption and automatic conversion remain
off unless explicitly enabled, and the production migration gate is still closed.
**Specifications:**
[`DATABASE_ENCRYPTION_SCHEMA.md`](DATABASE_ENCRYPTION_SCHEMA.md) v1.1 and the
`schema1.docx` *Database Reliability, Native Encryption and Recovery* schema
v1.0. The new spec explicitly recommends shipping Phase A first; this build
follows that order.

## Phase A — reliability hardening

Phase A is safe to run with production encryption still disabled. It closes the
crash windows in startup, key handling, file replacement, journal ordering,
lifecycle locking and source-to-destination parity.

| Area | Code | Behaviour |
|---|---|---|
| Startup classification | `lib/core/security/database_classifier.dart` | One explicit `DatabaseStartupState` decision before Drift opens anything: fresh, plaintext, encrypted, interrupted migration/restore/rotation, empty, unknown, corrupt or recovery-required. |
| Atomic replacement | `lib/core/security/atomic_file.dart` | Write temp → flush → read back → SHA-256 verify → replace. Windows uses `MoveFileExW(MOVEFILE_REPLACE_EXISTING \| MOVEFILE_WRITE_THROUGH)`, so the old implementation's delete-then-rename crash window is gone. |
| Lifecycle lock | `lib/core/security/database_lifecycle_lock.dart` | Cross-process advisory lock; conversion, rotation and restore take it exclusively, backup snapshots take it shared. Contention returns `LIFECYCLE_BUSY` after a bounded wait. |
| Artifact inventory | `lib/core/security/database_artifact_inventory.dart` | Enumerates conversion candidates, abandoned atomic-write siblings, quarantine directories and sidecars. An unjournaled `.encrypting-*` candidate fails classification; cleanup runs only after a safe classification and never during recovery. |
| Key identity | `lib/core/security/database_key_service.dart` | A DEK is only usable with its full record (database ID, key ID, generation, cipher profile, 32 bytes). Duplicate active keys fail closed. |
| Key store rollback point | `lib/core/security/database_key_store.dart` | The Windows DPAPI store preserves the previous committed generation as `.previous` before every replacement. |
| Journal ordering | `lib/core/security/migration_journal.dart` | Spec stages (`planned` … `completed`, rollback/recovery stages), `migrationId`, schema versions, source/temp checksums, `lastErrorCode`; forward-only except through explicit rollback/recovery states. |
| Parity | `lib/core/security/database_parity_verifier.dart` | Compares schema objects, columns, foreign keys, row counts and canonical row checksums, not just `integrity_check`. `db_security_identity` is excluded because it is written after conversion. |
| Identity anchor | `lib/core/security/database_identity.dart` | Format 3 adds `updated_at`; format-2 anchors without it stay readable and are upgraded in place. A missing or disagreeing anchor fails closed and is never recreated from external metadata. |
| Bootstrap | `lib/core/security/database_bootstrap.dart` | Takes the lifecycle lock, classifies, validates keys and metadata, verifies the anchor before Drift, journals every destructive step, verifies parity, and resolves interruption deterministically. |
| Backup snapshot | `lib/core/services/data_export_service.dart` | Logical backups take the shared lifecycle lock so they cannot overlap a conversion, rotation or raw restore. |

### Phase A test mapping

`test/database_reliability_test.dart` covers the spec groups:

- **A-START** — fresh install; recognized plaintext; newer schema; unrelated
  SQLite file; empty/truncated/unknown headers; plaintext under encrypted
  identity; missing database with metadata; keys without a database; matching
  and missing active keys; duplicate active keys; corrupt/interrupted journals;
  restore and rotation journals; bootstrap leaving an unknown file byte-identical.
- **A-KEY** — database/generation/profile mismatches, missing slot, wrong key
  length, duplicate active keys and the DPAPI `.previous` generation.
- **A-ART** — discovery of conversion candidates, atomic temporaries, quarantine
  and sidecars; cleanup policy; unjournaled-candidate rejection.
- **A-FILE** — overwrite without temporary leftovers, failed replace preserving
  the destination, verified copy and checksum rejection.
- **A-MIG** — stage round-trip, forward-only ordering, legacy stage names,
  recoverable failure markers and corrupt/unsupported journals.
- **A-PARITY** — identical databases, changed row, missing table, schema-version
  difference, identity-table exclusion and the damaged-database error.
- **A-LIFE** — exclusive contention timeout, release after failure, shared
  holders and `withLock` results.

## Phase B — native encryption

SQLite3MultipleCiphers 2.6.1 (SQLite 3.54.0) is bundled for Windows x64 and
Android. The selected track, exact versions, hashes, profile and evidence are in
[`SQLITE3MC_E0_DECISION.md`](SQLITE3MC_E0_DECISION.md).

| Area | Code | Behaviour |
|---|---|---|
| Native loading | `lib/core/security/sqlite3mc.dart` | Installs the platform loader, exposes explicit `FfiSqlite3` bindings, verifies `sqlite3mc_version()` and runs a full encrypted round-trip probe once per process. |
| Bundled libraries | `third_party/sqlite3mc/` | Windows DLL installed next to the runner; Android `libsqliteX.so` packaged for each ABI via `jniLibs`. |
| Key application | `lib/core/security/cipher_profile.dart` | Frozen `locus-sqlcipher4-raw-v1` profile: SQLCipher v4 compatibility, raw 256-bit key, 4096-byte pages, memory-only temp storage and FILL memory cleaning, in a fixed PRAGMA order. |
| Encrypted open | `lib/core/security/database_bootstrap.dart` | Verifies the runtime, key record and internal identity anchor before Drift opens or migrates the database; `isolateSetup` configures Drift's background isolate. |
| Conversion | `lib/core/security/database_bootstrap.dart` | Verified safety copy → journal → quarantine → plaintext snapshot → `PRAGMA rekey` → identity anchor → integrity + parity → atomic replace → metadata. Refuses to run without the explicit migration switch. |
| Rotation | `lib/core/security/database_rotation_service.dart`, `rotation_journal.dart` | Rekeys a verified candidate to a new generation, keeps the pre-rotation encrypted copy and the old key record, commits metadata before activating the new key, and recovers or rolls back an interrupted rotation. |
| Recovery material | `lib/core/security/recovery_envelope.dart` | `RecoveryBundle.isCurrentFor` identifies an envelope that belongs to a pre-rotation key. A reseal keeps the same DEK. |
| Migration switch | `lib/core/security/database_security_options.dart` | `LOCUS_DB_ENCRYPTION=1` loads the cipher; `LOCUS_DB_MIGRATION=1` additionally allows automatic plaintext conversion. Without the second switch the original file is left byte-identical. |

### Phase B test mapping

`test/database_encryption_test.dart` covers:

- **B-NATIVE** — bundled runtime version, cipher pragma, encrypted header,
  reopen with the correct key, wrong-key rejection, temp-store and page size.
- **B-CIPHER** — explicit profile/PRAGMA order, raw-key literal and rekey
  statement.
- **B-CONV** — end-to-end schema-16 conversion, parity against the quarantined
  plaintext, reopen through startup, refusal without the migration switch, and
  recovery when the process dies after replacement but before metadata commit.
- **B-ROT** — rekey to a new generation, old key/copy retention, recovery after
  replacement before activation, rollback of an unreplaced candidate, and stale
  recovery material identification.

`integration_test/sqlite3mc_e0_test.dart` runs the same encrypted round trip on
an Android device/emulator.

## Phase C — not implemented

Raw encrypted-database recovery packages, logical restore orchestration, sync
rebasing and start-fresh UI remain Phase C. The classification states and
journals for interrupted restore/rotation exist, but no workflow creates a
restore package or rewraps the new DEK after rotation. Production migration
stays disabled until Phase C recovery is tested.

## Existing security components

The following remain in place and are reused by Phase A:

| Area | Code | Behaviour |
|---|---|---|
| Process gate | `lib/core/security/database_security_options.dart` | Encryption is off unless `LOCUS_DB_ENCRYPTION=1` or `true`. |
| Cipher profiles | `lib/core/security/cipher_profile.dart` | Registry, raw-key syntax, PRAGMA order and SQLite3MC runtime probe. |
| Startup decision model | `lib/core/security/database_bootstrap.dart` | Creates, opens, migrates or fails closed before Drift touches the file. |
| Key storage | `lib/core/security/database_key_store.dart` | Versioned key slots; Windows DPAPI under `%LOCALAPPDATA%\LocusPlanner\keys`, secure storage elsewhere. |
| Key lifecycle | `lib/core/security/database_key_service.dart` | Fresh generation, load, activate and retire; never regenerates for an existing identity. |
| External hint | `lib/core/security/database_metadata.dart` | Non-secret, atomic metadata. Treated as untrusted. |
| Internal anchor | `lib/core/security/database_identity.dart` | `db_security_identity` table inside the database is the authority. |
| Recovery bundle | `lib/core/security/recovery_envelope.dart` | v2, per-purpose AES-256-GCM, PBKDF2-HMAC-SHA256 (600,000 iterations), mandatory AAD. |
| Migration journal | `lib/core/security/migration_journal.dart` | Durable stages used to resume or roll back an interrupted conversion. |
| File handling | `lib/core/security/database_file_inspector.dart` | Header classification, sidecar handling, SHA-256 and quarantine. |
| Sensitive paths | `lib/core/security/database_paths.dart` | Windows uses `%LOCALAPPDATA%\LocusPlanner` (non-roaming); one-time consistent move from the legacy location. |
| Backup passphrase | `lib/core/security/backup_passphrase_store.dart` | Windows DPAPI file in the non-roaming directory; migrates the legacy credential-store value on first read. |
| Settings surface | `lib/features/settings/presentation/settings_page.dart` | Read-only protection card shows the encryption gate, storage location and Android backup exclusions. |
| Pre-upgrade backup | `lib/core/db/database_maintenance.dart` | Plaintext and encrypted sources are backed up without creating a plaintext copy of an encrypted database. |

### Startup rules

- Missing file + no metadata → create a new identity and key.
- Plaintext file + no metadata → controlled conversion when encryption is on
  **and** `LOCUS_DB_MIGRATION` explicitly allows it; otherwise the file is left
  untouched and startup fails closed.
- Encrypted file + metadata + key → verify the SQLite3MC runtime, the key record
  and the internal identity, then checkpoint and back up before a Drift upgrade.
- Encrypted file without metadata/key, plaintext under an encrypted identity,
  an unknown profile, a missing cipher runtime, or a zero-length file → fail
  closed with a recovery error. No key is regenerated and no empty database is
  created.

### Windows key storage

The DEK store is a DPAPI-protected blob at
`%LOCALAPPDATA%\LocusPlanner\keys\database_keys.dat`. It is deliberately not
the roaming `flutter_secure_storage_windows` file: that plugin deletes its JSON
store when decryption fails. The new store preserves a damaged blob so the
failure can be diagnosed.

### Android backup exclusions

Android 11 (`backup_rules.xml`) and Android 12+ (`data_extraction_rules.xml`)
exclude the database, its `-wal`/`-shm`/`-journal` sidecars, metadata, migration,
restore and rotation journals, the lifecycle lock, conversion and rotation
candidates, `quarantine/` and `backups/`. A cloud or device-transfer restore
cannot bring back database bytes whose device-local key is gone.

## Backup format v3

`DataExportService.buildBackupJson` now:

- reads every table in **one transaction** so the manifest and payload come
  from the same snapshot;
- writes `format_version: 3`, `database_schema_version`,
  `source_database_id`, `backup_encryption`, `payload_sha256` and a `tables`
  manifest with row counts and per-table SHA-256 values;
- keeps the existing top-level section keys so older consumers still work.

`BackupImportPlan.parse` accepts v1, v2 and v3, verifies the payload checksum
and per-table manifest before writing anything, and still imports legacy
top-level-only files. A mismatch is a hard `FormatException`.

Automatic and recovery backups are written through a temp file → flush →
read-back verification → atomic replace path. Retention runs only after the new
file is durable. The `last_auto` cadence marker is only updated after success.

### Fail-closed backup policy

When live encryption is enabled (or the backup policy is marked as requiring
encryption), an automatic backup with no backup passphrase throws instead of
writing plaintext JSON. Manual plaintext export remains a separate, explicitly
warned user action.

## E0 status and remaining blockers

The bundled SQLite3MC runtime passes the full encrypted round trip on Windows
(development and release-bundle DLLs) and on an Android API 37 emulator. The
release APK contains the expected per-ABI libraries and the Windows release
bundle contains the DLL. Details and hashes are recorded in
[`SQLITE3MC_E0_DECISION.md`](SQLITE3MC_E0_DECISION.md).

Live encryption and automatic conversion are still off by default. Before
production migration:

1. Repeat the runtime test and schema-16 conversion on a physical Android
   release device.
2. Exercise interrupted conversion and rotation on both platforms with crash
   injection.
3. Prove temporary-storage behaviour for large sorts, index builds and imports
   on Android.
4. Complete Phase C recovery (raw package and logical restore) and test a
   clean-device unwrap.
5. Only then set `LOCUS_DB_ENCRYPTION=1` and `LOCUS_DB_MIGRATION=1` in the
   release environment.

The backup passphrase moved to the same non-roaming location:
`%LOCALAPPDATA%\LocusPlanner\backup_passphrase.dat`, protected with DPAPI. On
first read the new store migrates a value written by older builds from
`flutter_secure_storage` and removes the legacy copy only after the new write
succeeds. A damaged DPAPI file is kept in place and surfaces an error asking the
user to enter the passphrase again, rather than silently disabling encryption
or deleting the evidence.

## Test coverage

- `test/database_security_test.dart` — profiles, metadata, identity, file
  inspector, migration journal, path resolution (plaintext move, Documents
  fallback, in-place journal), key service, recovery envelope (wrong
  passphrase/AAD), atomic files, backup passphrase stores and the Windows DPAPI
  key store.
- `test/database_reliability_test.dart` - Phase A startup classification, key
  identity validation, atomic replacement, journal ordering, source/destination
  parity and lifecycle-lock contention.
- `test/database_encryption_test.dart` - Phase B runtime proof, cipher profile,
  schema-16 conversion, conversion crash recovery, DEK rotation and rotation
  crash recovery.
- `integration_test/sqlite3mc_e0_test.dart` - on-device Android runtime proof.
- `test/backup_v3_test.dart` — v3 manifest, checksum tampering, durable writes,
  fail-closed automatic backups and plaintext-backup cleanup.
- `test/backup_encryption_test.dart` — encrypted envelope behaviour and updated
  v3 assertion.
- `test/database_backup_test.dart` — pre-upgrade snapshot naming and directory
  creation.
