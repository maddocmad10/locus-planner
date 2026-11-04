# LOCUS PLANNER

## Database Encryption Implementation Schema

### Architecture, migration, recovery, backup and release-hardening specification

**Version 1.1 — review-verified final design**

| Document control | Value |
|---|---|
| Target application | Locus Planner — Flutter desktop (Windows) and Android companion |
| Current database layer | Drift + SQLite; current schema version 16 |
| Specification version | 1.1 (supersedes 1.0 of 3 November 2026) |
| Date | 3 November 2026 |
| Status | Design review complete. **E0 has not passed. Production migration is blocked.** |
| Review basis | Direct inspection of `C:\Users\hp\locus_planner_windows`: `pubspec.yaml`, `pubspec.lock`, `docs/DEPENDENCIES.md`, `README.md`, `lib/core/db/app_database.dart`, `lib/core/services/data_export_service.dart`, `lib/core/services/auto_backup_service.dart`, `lib/core/services/backup_encryption_service.dart`, `android/app/src/main/res/xml/backup_rules.xml`, `android/app/src/main/res/xml/data_extraction_rules.xml`, and the published Drift/SQLite3MC documentation. |
| Locked runtime versions | `drift` 2.31.0, `drift_dev` 2.31.0, `sqlite3` 2.9.4, `sqlite3_flutter_libs` 0.5.42, `flutter_secure_storage` 9.2.4, `pointycastle` 4.0.0 |
| Manifest constraints | `drift: ^2.20.0`, `drift_dev: ^2.20.0`, `sqlite3: ^2.4.0`, `sqlite3_flutter_libs: ^0.5.24`, `flutter_secure_storage: ^9.2.4` |

> **Primary recommendation (unchanged in direction, narrowed in scope).** Use transparent SQLite page encryption with SQLite3MultipleCiphers (SQLite3MC), after E0 proves one of the two dependency paths in §4. Keep live-database encryption, logical-backup encryption and the recovery envelope as three separate layers. Do not ship a plaintext fallback, an automatic key regeneration, or a partial Android OS restore.

---

## 0. Review disposition

All seven required corrections and all seven additional release blockers supplied with the review are accepted. One clarification is attached to each where the review was directionally correct but did not go far enough. This revision also adds the findings from a direct code review (O1–O8, below), which are release blockers in their own right.

### 0.1 Reviewer-required corrections

| ID | Review point | Verified in the current tree | Disposition | Addressed in |
|---|---|---|---|---|
| R1 | The illustrative build-hook snippet will not work with the locked dependencies. `drift` resolves to 2.31.0, `sqlite3` to 2.9.4, `sqlite3_flutter_libs` to 0.5.42. | Yes. `pubspec.lock` lines 204, 912 and 920; `sqlite3` 2.9.4 still documents `sqlite3_flutter_libs` and has no root build hook. Drift's hook-based SQLite3MC route is documented for Drift 2.32+ and `sqlite3` 3.x. | **Agree.** E0 must choose either a coordinated upgrade or a custom native SQLite3MC integration. The snippet may remain illustrative only and must not be treated as an executable configuration. | §4 |
| R2 | §9.4 conflates logical-backup recovery with raw encrypted-database recovery. | Yes. The logical backup is JSON (`buildBackupJson`, `data_export_service.dart:313`) and contains application rows, not the live database file. Import creates rows in the current database; it does not need the old DEK. | **Agree.** Split into two workflows. Logical recovery creates a new database, new DEK and new identity. The recovery package is primarily for raw-database/key recovery. | §8.2, §8.5, §8.7 |
| R3 | Android OS backup can preserve the encrypted database while omitting its Keystore-protected DEK, producing an unopenable restore. | Yes. `backup_rules.xml` and `data_extraction_rules.xml` exclude only three `sharedpref` files. The planner database, sidecars, metadata and backups are not excluded. | **Agree.** Exclude the live database and all related state from cloud backup and device transfer; rely on explicit logical exports. Add the “encrypted/unknown, no metadata” startup state. Test cloud restore and device-to-device transfer. | §6, §9 |
| R4 | §4/§3 do not define the DEK or cipher profile precisely. A random 32-byte value is not a SQLite3MC key specification; `hexkey` is a hex-encoded passphrase, not necessarily a raw key. | Yes. SQLite3MC distinguishes passphrase-KDF keys (`PRAGMA key` / `PRAGMA hexkey`) from raw keys (`PRAGMA key = "x'…'"` for SQLCipher, `PRAGMA key = 'raw:…'` for sqleet). PRAGMA order and cipher parameters materially change the file format. | **Agree.** Add a versioned cipher-profile registry, exact raw-key encoding, PRAGMA ordering, page/HMAC/KDF settings, runtime extension verification and profile persistence. | §5.2, §5.3, §5.4 |
| R5 | §10.1 says to update the recovery envelope during rotation, but the recovery passphrase is deliberately not stored, so the app cannot rewrap the new DEK without the user. | Yes. Only the backup passphrase has a secure-store slot (`backup_encryption_service.dart`). No recovery passphrase is stored. | **Agree.** Rotation must preserve the old DB/key until the new DB reopens, prompt for the recovery passphrase to create a new envelope, or mark the old envelope as pre-rotation/stale. Changing only the recovery passphrase is a rewrap, not a key rotation. | §10 |
| R6 | File-level crash safety needs explicit sidecar, atomic-write, flush/fsync, crash-point and parity/checksum requirements. | Yes. The current conversion design is directionally correct but not sufficient; the existing code also has concrete file-copy gaps (O2, O3). | **Agree.** Add `-wal`, `-shm`, `-journal`, temp-file and directory-sync rules; enumerate every crash point; require per-table parity or stable checksums, not only row counts. | §7 |
| R7 | The legacy Documents database and other plaintext copies remain outside the encryption boundary. | Yes. `README.md:177-179` says the old Documents file is copied and “left in place as a backup.” `backupDatabaseBeforeUpgrade()` also leaves `.bak` files, and `deleteUnencryptedBackups()` does not remove them. | **Agree.** Add a complete plaintext-artifact inventory, ownership, retention and cleanup policy. Include the legacy Documents copy, pre-migration `.bak`, plaintext automatic/manual/pre-import exports, migration temp files and optional JSON exports. | §11 |

### 0.2 Additional release blockers from the review

| ID | Review point | Verified in the current tree | Disposition | Addressed in |
|---|---|---|---|---|
| B1 | Clean-device recovery needs the backup credential as well as the recovery credential. | Yes. `BackupEncryptionService` stores the backup passphrase in `flutter_secure_storage`; a clean device does not have it. The recovery package described in §4.4 wraps only the DEK. | **Agree.** Define a recovery bundle that either wraps both credentials under the recovery passphrase, or explicitly requires two credentials. Never claim a logical backup is recoverable without its credential. | §5.6, §8.6 |
| B2 | Automatic backups can remain plaintext when no backup passphrase is configured. | Yes. `buildAutomaticBackup()` returns plain JSON when `passphrase == null` (`data_export_service.dart:417-426`). `createRecoveryBackup()` uses the same path. | **Agree.** After live encryption is enabled, automatic, pre-import, pre-upgrade and migration-safety backups must fail closed if no backup credential is available. Manual plaintext export remains a separate, explicitly warned action. The pre-encryption plaintext safety copy is a narrow, documented exception. | §8.4 |
| B3 | Backup creation needs transactional and durability requirements. | Yes. `buildBackupJson()` performs many independent reads with no single read transaction. `AutoBackupService` and `createRecoveryBackup()` write directly to the final path with no temp/rename, flush, read-back or validation. | **Agree.** Require one consistent read snapshot, temp-file write, flush, atomic rename, reopen/decrypt/validate, and only then update last-success and prune. Always retain a last-known-good backup. | §8.4 |
| B4 | Logical restore is not complete sync-state recovery. | Yes. Backup v2 omits `sync_outbox`, `sync_row_versions`, `sync.device_id`, `sync.epoch`, `sync.outbox.pruned_through`, paired clients and TLS state. Restore currently inserts rows with sync triggers active. | **Agree.** Define a new device ID and sync epoch, reset/rebase outbox and row-version state, require re-pairing/full resync, and prevent tombstone resurrection. Add optional sync metadata only in a versioned backup format, not by silently restoring old identity. | §8.6 |
| B5 | “Start fresh” must preserve the old key as well as the old files. | The current §11.3 says to preserve old files but not the old key slot. | **Agree.** Quarantine the database, metadata, journal and sidecars under the old identity; retain the versioned secure-store key slot; create the fresh database under a new database ID and key ID. | §10.4, §11 |
| B6 | E0 needs broader coverage. | The current E0 list covers create/reopen/wrong-key only. | **Agree.** Add copied schema-16 plaintext conversion, raw-DEK rekey/rotation, interrupted conversion and sidecars, encryption of physical-backup targets, SQLite temporary-store behavior during large sorts/migrations, and cipher-profile persistence across dependency upgrades. | §13.2 |
| B7 | Add an internal identity anchor and mandatory envelope AAD. | No internal anchor exists today; external metadata does not exist yet. | **Agree.** Store `databaseId`, key ID/generation and cipher-profile ID inside the encrypted database. Treat external metadata as an untrusted hint. Bind database ID, key ID, purpose, format version and cipher-profile version into recovery-envelope AES-GCM AAD. | §5.3, §5.4, §5.6 |

### 0.3 New findings from this review

| ID | Finding | Why it matters | Addressed in |
|---|---|---|---|
| O1 | On Windows, `getApplicationSupportDirectory()` is `RoamingAppData`, and `flutter_secure_storage_windows` 3.1.2 stores its DPAPI-encrypted JSON file in that same directory. The plugin deletes the whole file when it cannot decrypt it. | A roaming-profile copy, a new machine, or a corrupted secure-store file can remove the DEK (and all other secrets) at once. The encrypted database then becomes unrecoverable unless a recovery package exists. | §5.5, §9.2 |
| O2 | `_resolveDatabaseFile()` copies only `locus_planner.db` with `File.copy`, not `-wal`/`-shm` (and not `-journal`). | A legacy database in WAL mode can lose committed transactions during the one-time Documents-to-AppData copy. This is a pre-existing data-loss path that encryption migration would inherit. | §7.3, §7.8 |
| O3 | `backupDatabaseBeforeUpgrade()` opens the database with an unkeyed `sqlite3.open()` and runs `VACUUM INTO` on every startup before Drift opens it. | Once the database is encrypted, this path either fails or produces a plaintext/unknown copy. It also runs before the encryption-aware connection factory and cannot distinguish encrypted from plaintext. | §7.3, §7.9 |
| O4 | `buildBackupJson()` is not a single snapshot, and `createRecoveryBackup()` writes directly to its final path. | Concurrent writes can produce a backup that never existed as a database state; a crash can leave a truncated file that looks like a valid backup. | §8.4 |
| O5 | `deleteUnencryptedBackups()` removes only `auto_*`, `manual_*` and `pre_import_*` `.json` files. It does not remove `*.pre-migration-*.bak`, the legacy Documents database, migration temp files or failed conversion copies. | The plaintext inventory in R7 is incomplete in the implementation, not only in the schema. | §11 |
| O6 | SQLite3MC 2.6+ encrypts temporary files by default, but the exact build and `PRAGMA temp_store` settings must be proven. A build that spills plaintext temp data defeats at-rest encryption during large sorts, index creation and migrations. | Migration and large reports can write plaintext to disk outside the encrypted main file. | §5.2, §13.2 |
| O7 | The desktop single-instance check can return `checkFailed` and allow startup; it is a convenience lock, not a hard migration lock. | Two processes must never convert, rekey or replace the database concurrently. | §7.1 |
| O8 | The existing crypto stack is PBKDF2-HMAC-SHA256 + AES-256-GCM (`EncryptedEnvelope`), while the schema suggests Argon2id for the recovery envelope. | Adding a second KDF/library without versioning and benchmarks increases attack surface and failure modes. Reuse the reviewed primitives with a new version and AAD, or adopt a vetted Argon2id implementation explicitly. | §5.6 |

### 0.4 Verdict

**The design is directionally correct, but the schema as written is not implementable with the locked dependency set and is not safe to migrate users’ only database.** The correct sequence is:

1. Complete E0 with one explicit dependency path (§4) and freeze the cipher profile (§5.2).
2. Complete the key-store and identity work (§5), including the Windows roaming/key-loss issue.
3. Revise backup and recovery before E1/E3 (§8), including the two-credential model and sync rebase.
4. Implement crash-atomic conversion and the full plaintext-artifact policy (§7, §11).
5. Keep production migration gated until E0 passes, the recovery bundle is verified on a clean device, and Android cloud restore/device transfer and Windows roaming have been tested.

### 0.5 What changed from v1.0

| v1.0 area | v1.1 change |
|---|---|
| §3.2 dependency spike | Replaced the illustrative hook with two explicit E0 paths and verified locked versions (§4). |
| §4.1–§4.3 key hierarchy | Added key IDs/generations, cipher profiles, raw-key syntax, internal identity anchor and untrusted metadata (§5). |
| §7 conversion | Added sidecar handling, journal stages, atomic replacement, crash-point recovery and full parity/checksum verification (§7). |
| §8 startup | Added the “encrypted/unknown, no metadata” state, plaintext-under-encrypted-identity failure, unsupported profile and quarantine states (§6). |
| §9 backup/restore | Split logical and raw recovery, added backup v3 manifest, transactional creation, credential matrix and sync rebase (§8). |
| §10 rotation | Added envelope rewrap/stale-envelope handling and old-key retention (§10). |
| §11 UI | Added credential/path clarity and quarantine behavior (§12). |
| §12 testing | Added the E0 matrix, failure injection, clean-device and OS-backup tests (§13). |
| §14–§15 release | Added Android/Windows OS-backup gates and plaintext-artifact acceptance criteria (§9, §11, §15). |
| New | Review disposition, code-verified findings O1–O8, Windows roaming/DPAPI and legacy WAL-copy issues (§0, §9). |

---

## 1. Purpose and scope

This document defines the implementation design for encrypting Locus Planner’s live SQLite database at rest. The goal is to protect the local database file when the device is powered off, the file is copied from disk, or an OS backup/transfer captures it, while preserving the existing Drift data model, Windows/Android support, backup/restore behavior and local-first workflow.

The design covers:

- Encryption library selection and native integration boundaries.
- Database encryption key generation, storage, recovery, rotation and quarantine.
- Safe conversion of existing plaintext databases, including the legacy Documents location.
- Startup behavior, interrupted migrations and failure handling.
- Logical backup, raw encrypted-database backup, recovery and clean-device restore.
- Android OS backup and Windows roaming behavior.
- Application changes, test strategy, rollout phases and release criteria.

### 1.1 Three separate protection layers

| Layer | Protects | Key/credential | Must not be conflated with |
|---|---|---|---|
| Live database page encryption | The SQLite main file and its sidecars at rest | Random 256-bit DEK, versioned by key ID | Logical backup encryption or the recovery passphrase |
| Logical backup encryption | Exported JSON/`.locusbackup` files outside the app | Backup passphrase (or explicit plaintext export) | The live DEK |
| Recovery bundle | The DEK, and optionally the backup credential, for a clean device | User recovery passphrase | The live database password or the backup passphrase |

### 1.2 Out of scope

Encryption does not protect data while the app is unlocked and the database is open. It is not a substitute for OS account security, device encryption, app-session locking, malware protection, screen privacy, or secure handling of exported files. It does not make a weak backup passphrase strong. It does not protect data already copied into an unencrypted export before encryption was enabled.

### 1.3 Both platforms have a local database

The Android companion is not only a remote UI. `lib/features/mobile/mobile_app.dart` and `mobile_reminder_service.dart` read and write the local `AppDatabase`, and `mobile_sync_client.dart` applies sync changes to it. The Android backup rules therefore matter for real planner data, not only for pairing state.

---

## 2. Verified project baseline and implications

| Area | Observed baseline | Implementation implication |
|---|---|---|
| Database | Drift-backed SQLite; `currentSchemaVersion = 16` | Encryption is a storage-layer change; it does not require a Drift schema-version increment by itself. |
| Connection | `LazyDatabase _openConnection()` calls `backupDatabaseBeforeUpgrade(file)` and then `NativeDatabase.createInBackground(file)` (`app_database.dart:1438-1443`). | Centralize opening in an encryption-aware factory. The key and cipher profile must be applied before Drift reads or writes anything. |
| Pre-upgrade backup | `backupDatabaseBeforeUpgrade()` directly opens SQLite via `sqlite3.sqlite3.open(file.path)` and runs `VACUUM INTO` (`app_database.dart:1450-1493`). | This unkeyed open is incompatible with an encrypted database. It must be encryption-aware and must never create a plaintext copy of an encrypted database. |
| Legacy location | `_resolveDatabaseFile()` copies `Documents/locus_planner.db` to app support with `File.copy` (`app_database.dart:1500-1516`). The README says the old file is left in place. | Copy `-wal`/`-shm`/`-journal` consistently or use a SQLite backup. The legacy plaintext copy remains a threat and a cleanup obligation. |
| Key storage | `flutter_secure_storage` 9.2.4 is present. | Use a dedicated key-store adapter with versioned slots. Do not assume the plugin is a durable vault; see O1. |
| Backup encryption | `BackupEncryptionService` protects optional automatic backups and stores the passphrase in secure storage. | Keep it as a separate backup layer. On a clean device the stored passphrase is unavailable; the recovery bundle or the user must supply it. |
| Automatic backups | 24-hour interval, seven retained backups; success timestamp updated after success. | Preserve cadence/retention, but add fail-closed behavior, single-snapshot export, temp/rename, read-back validation and last-known-good retention. |
| Logical backup contents | `buildBackupJson()` exports 12 user-data sections plus `app_settings`; transient sync settings are excluded. `sync_outbox` and `sync_row_versions` are not exported. | A logical restore is not a sync-state restore. Define a new device ID/epoch and full resync/rebase. |
| Android backup | `backup_rules.xml` and `data_extraction_rules.xml` exclude only `FlutterSharedPreferences.xml`, `FlutterSecureStorage.xml` and `locus_reminders.xml`. | The planner database and sidecars are currently eligible for cloud backup/device transfer. Change the policy before encryption ships. |
| Windows path | `path_provider_windows` maps application support to `WindowsKnownFolder.RoamingAppData`. | The DB, metadata and `flutter_secure_storage.dat` can roam. A DPAPI user-scope blob may not decrypt on another machine, and the plugin deletes corrupt files. |
| Tests | A mixture of native SQLite and in-memory Drift tests. | Keep fast in-memory business-logic tests; add native encrypted integration tests and failure injection. |

### 2.1 Dependency facts that change the design

| Package | Manifest | Locked | Relevant fact |
|---|---|---|---|
| `drift` | `^2.20.0` | 2.31.0 | Supports `NativeDatabase.createInBackground(..., setup:)`; the hook-based SQLite3MC route is documented for 2.32+. |
| `drift_dev` | `^2.20.0` | 2.31.0 | Must move with `drift` if Option A is chosen. |
| `sqlite3` | `^2.4.0` | 2.9.4 | No root `hook/` implementation. README still points Flutter users to `sqlite3_flutter_libs`; SQLite3MC is documented for the WASM path. |
| `sqlite3_flutter_libs` | `^0.5.24` | 0.5.42 | 0.5.x is EOL (`0.6.0+eol`); its Windows CMake downloads SQLite 3.52.0 from `sqlite.org` and builds a plain `sqlite3.dll`. It does not build SQLite3MC. |
| `flutter_secure_storage` | `^9.2.4` | 9.2.4 | Windows implementation 3.1.2 uses a DPAPI-encrypted JSON file in application support and deletes it on decrypt/parse failure. Android uses Keystore-backed storage; backup rules exclude the shared-prefs file. |
| `pointycastle` | `^4.0.0` | 4.0.0 | Existing PBKDF2/AES-GCM path; no Argon2id dependency is present. |

> **Evidence.** `pubspec.lock` reports `drift` 2.31.0 (line 204), `drift_dev` 2.31.0 (line 212), `sqlite3` 2.9.4 (line 912), `sqlite3_flutter_libs` 0.5.42 (line 920), `flutter_secure_storage` 9.2.4 (line 305). The `sqlite3` 2.9.4 package has no `hook/` directory and its README still describes `sqlite3_flutter_libs` for Android/Windows. Drift 2.31.0's `native.dart` already exposes `setup:` and `isolateSetup:` on `createInBackground`.

---

## 3. Architecture and locked decisions

| ID | Decision | Requirement |
|---|---|---|
| D1 | Encryption library | SQLite3MC, subject to E0 choosing Option A or B in §4. Fail closed if the cipher extension is unavailable. |
| D2 | Cipher profile | One versioned profile ID, frozen in E0, stored with the database identity. No silent library-default drift. |
| D3 | Key hierarchy | One random 256-bit DEK per database identity; key ID and generation are versioned. |
| D4 | Identity anchor | `databaseId`, `keyId`, `keyGeneration`, `cipherProfileId` and format version live inside the encrypted database and in external metadata. External metadata is an untrusted hint. |
| D5 | Connection factory | Every production connection, maintenance open, backup and migration goes through one encryption-aware factory. |
| D6 | Startup | Missing key, missing metadata with an encrypted-looking file, unsupported profile, or wrong key leads to recovery, never to plaintext migration or a new empty database. |
| D7 | Migration | Original plaintext file is preserved until the encrypted replacement is independently reopened and verified; conversion is crash-atomic with sidecars and a journal. |
| D8 | Backups | Logical backups are the primary portable format. Automatic backups are encrypted after encryption is enabled. Raw encrypted-database backups are optional and require the recovery credential. |
| D9 | Recovery | Logical recovery creates a new database and identity. Raw recovery reopens the original database with the original DEK. The recovery bundle wraps the DEK and, optionally, the backup credential. |
| D10 | Rotation | New key ID/DEK, verified replacement, then envelope rewrap or explicit stale-envelope marking. Old key is retained until success. |
| D11 | OS backup | Android excludes the live database, sidecars, metadata, journal, quarantine and backup directory from cloud backup/device transfer. Windows moves sensitive state out of roaming or explicitly fails closed on roaming. |
| D12 | Plaintext cleanup | Every plaintext artifact is enumerated, labeled, retained only as long as necessary, and removed with explicit user consent after verification. |

---

## 4. E0 — dependency, native integration and cipher gate

### 4.1 Why the illustrative hook does not work

The schema’s snippet:

```yaml
hooks:
  user_defines:
    sqlite3:
      source: sqlite3mc
```

is the current Drift-documented route for **Drift 2.32+ and `sqlite3` 3.x**. It is not implemented by `sqlite3` 2.9.4. With the locked tree, adding that block does not select a SQLite3MC native library; the app continues to use the plain SQLite built by `sqlite3_flutter_libs` or the OS library. The snippet must remain illustrative until E0 changes the dependency set.

### 4.2 Option A — coordinated upgrade

Upgrade `drift`, `drift_dev`, `sqlite3` (and the native packaging route) together:

- `drift` / `drift_dev` at a version that supports the hook-based SQLite3MC source (2.32+).
- `sqlite3` 3.x with the root build hook.
- Remove `sqlite3_flutter_libs` if the hook supplies the native library, or reconfigure it only if the selected version still requires it.
- Add the `hooks:` block at the pub workspace root (or app pubspec if not a workspace).
- Regenerate Drift code and test every migration from schema 16.
- Verify Windows DLL/asset packaging and Android ABI packaging in release builds.

**Risks:** Drift API changes, native-assets build changes, Android NDK/ABI issues, Windows installer changes, loss of the known-good SQLite build, and a larger regression surface. This must be a standalone persistence change, not bundled with UI work.

### 4.3 Option B — custom SQLite3MC native integration on the pinned versions

Keep Drift 2.31.0 / `sqlite3` 2.9.4 and ship SQLite3MC yourself:

- Build SQLite3MC with the same SQLite feature set the app relies on (JSON, FTS5 if used, RTREE if used, math functions, session/preupdate if used, `SQLITE_TEMP_STORE=2` or an explicit `temp_store` policy).
- Windows x64: ship a signed `sqlite3mc.dll` (or a replacement `sqlite3.dll`) next to the app and load it explicitly; do not fall back to `winsqlite3.dll`.
- Android: ship `arm64-v8a`, `armeabi-v7a` and `x86_64` libraries under `jniLibs`; verify 16 KB page-size compatibility and Play Store packaging.
- Disable/remove `sqlite3_flutter_libs` so two SQLite providers cannot be loaded.
- Pin the SQLite3MC source tag and a checksum; do not download an unpinned native library at build time.
- Verify `PRAGMA cipher` and the SQLite3MC version at runtime, not only in a debug assert.

**Risks:** ongoing security patching, ABI/feature mismatch, custom build reproducibility, store review, and a larger maintenance burden. This is acceptable only if E0 proves it on real release artifacts.

### 4.4 E0 must freeze these values

E0 is not complete until it records, in a checked-in `cipher_profile` document and code registry:

1. SQLite3MC version, source/checksum, and exact build flags.
2. Cipher scheme (`sqlcipher`, `chacha20`, or another supported scheme).
3. Raw-key versus passphrase-KDF mode, exact key encoding, and the exact `PRAGMA key`/`PRAGMA hexkey`/raw-literal syntax.
4. PRAGMA order, including `cipher`, `legacy`, `kdf_iter`, `kdf_algorithm`, `hmac_algorithm`, page size, `cipher_salt` (if applicable), and `key`.
5. Journal mode and WAL behavior for rekey/conversion.
6. `temp_store` behavior and SQLite3MC temporary-file encryption.
7. `memory_security` setting.
8. Runtime extension verification (`PRAGMA cipher`, version string, or a known SQLite3MC-only function).
9. Wrong-key behavior and the exact error classification.
10. `VACUUM INTO` / `PRAGMA rekey` behavior on an encrypted source and on a plaintext source.

### 4.5 E0 go/no-go gate

Do not start E1 or E3 until E0 passes on **real Windows release** and **real Android release** artifacts:

- The selected SQLite3MC library is bundled and loaded; `PRAGMA cipher` succeeds.
- A new encrypted database can be created, written, closed and reopened with the same key.
- A wrong key fails without creating a replacement database or writing to the file.
- An unkeyed SQLite connection cannot read the encrypted database.
- WAL, checkpoint, `integrity_check`, `foreign_key_check` and physical backup/reopen work.
- The key is applied before any schema access in the background isolate (`setup:` callback ordering).
- The exact raw/passphrase key syntax is proven; a `hexkey` string is not mistaken for a raw key.
- Schema-16 plaintext conversion (including the legacy Documents copy and sidecars) preserves data and survives interrupted conversion.
- Raw-DEK rekey/rotation works and preserves the cipher profile.
- Physical-backup targets are encrypted and reopen with the same key.
- Large sorts, index creation and migrations do not spill plaintext temp data.
- The cipher profile survives a dependency upgrade (open an old DB with the new build).

---

## 5. Key hierarchy, cipher profile and identity

### 5.1 Data Encryption Key (DEK)

| Property | Requirement |
|---|---|
| Algorithm/key size | 32 random bytes from a cryptographically secure generator. |
| Purpose | Encrypt/decrypt the live SQLite database only. Never reused for backups, sync, TLS or the recovery envelope. |
| Lifetime | Stable for one database identity; changed only by an explicit, verified rotation. |
| Identity | Every DEK has a `keyId` (for example `key-0001`) and a `keyGeneration` integer. |
| Persistence | Platform-backed secure storage under a versioned slot, for example `locus.db.dek.v1.key-0001`. The slot name is never derived solely from a user-visible value. |
| Exposure | Never log, print, serialize to diagnostics, include in crash reports, sync payloads or ordinary preferences. |
| Deletion | Delete an old slot only after the replacement database has reopened, the internal anchor and metadata are committed, and the new recovery envelope has been verified. Retain the old slot while a quarantine/rollback copy exists. |

### 5.2 Cipher profile

A 32-byte value is not a cipher specification. SQLite3MC needs a scheme, a key mode, key encoding, PRAGMA order and format parameters. The following are **candidate profiles**; E0 must freeze exactly one and record its `profileId` with the database.

| Field | Candidate P1 (SQLCipher v4 compatibility) | Candidate P2 (SQLite3MC native ChaCha20) |
|---|---|---|
| `profileId` | `locus-sqlcipher4-raw-v1` | `locus-sqleet-raw-v1` |
| `cipher` | `sqlcipher` | `chacha20` |
| `legacy` | `4` (SQLCipher v4 parameter set) | `0` (non-legacy) |
| `keyMode` | raw 256-bit | raw 256-bit |
| Key syntax | `PRAGMA key = "x'<64 hex chars>'"` | `PRAGMA key = 'raw:<64 hex chars>'` |
| Key encoding | 32 bytes as 64 lowercase hex characters; blob literal | 32 bytes as 64 lowercase hex characters; `raw:` literal |
| Passphrase variant | `PRAGMA key = '<passphrase>'` with KDF | `PRAGMA key = '<passphrase>'` with KDF |
| Page size | 4096 | 4096 |
| KDF | Not used for raw key; if passphrase, SQLCipher default `kdf_iter=256000`, `kdf_algorithm=SHA512` | Not used for raw key; if passphrase, record exact KDF parameters |
| HMAC/auth | Per-page HMAC-SHA512 (SQLCipher v4 default) | Poly1305 per page (sqleet) |
| `plaintext_header_size` | `0` | `0` |
| `temp_store` | `MEMORY` (verify no plaintext spill) | `MEMORY` (verify no plaintext spill) |
| `memory_security` | `FILL` if compiled in | `FILL` if compiled in |
| Journal mode | WAL for normal operation; test rekey constraints | WAL for normal operation; test rekey constraints |

**Non-negotiable key rules:**

- `PRAGMA hexkey` is a **hex-encoded passphrase**, not a raw key. Do not use it to apply a random DEK unless the exact SQLite3MC version documents that it bypasses KDF. If the design wants raw-key application, use the documented raw literal for the chosen cipher.
- A raw SQLCipher key is `PRAGMA key = "x'<64 hex>'";`. A raw sqleet key is `PRAGMA key = 'raw:<64 hex>';`. A 96-character form (key + 16-byte salt) is only for the cases documented by SQLite3MC.
- `PRAGMA key` returns `ok` even for a wrong key. After applying it, execute a real read (`SELECT count(*) FROM sqlite_master;`) and only then treat the database as open.
- Configure cipher parameters **before** `PRAGMA key`; do not run cipher configuration inside a transaction. `PRAGMA rekey` cannot be rolled back like a normal transaction.
- If `plaintext_header_size` is used, the cipher salt cannot live in the header; retrieve/store it as non-secret metadata and supply it before key application. Avoid this option unless a platform requirement forces it.

> **Reference.** SQLite3MC documents the 3-step order: optional `PRAGMA cipher`, optional cipher parameters, then `PRAGMA key`. It documents raw-key literals for SQLCipher and sqleet, and states that `hexkey` is a hex-encoded passphrase. Drift documents the `setup:` callback as the place to apply `PRAGMA key` before Drift uses the database.

### 5.3 External metadata (untrusted startup hint)

Store non-secret metadata outside the encrypted database. It must never contain the DEK or a reversible representation of it.

```json
{
  "formatVersion": 2,
  "databaseId": "db-<uuid>",
  "activeKeyId": "key-0001",
  "keyGeneration": 1,
  "cipherProfileId": "locus-sqlcipher4-raw-v1",
  "encryptionEnabled": true,
  "databaseFile": "locus_planner.db",
  "createdAt": "2026-11-03T12:00:00Z",
  "lastOpenedAt": "2026-11-03T12:00:00Z"
}
```

Metadata is an **untrusted hint**, not the source of truth. A copied, stale, edited or missing metadata file must not cause the app to open a different database, generate a new key, or run plaintext migration.

### 5.4 Internal identity anchor

Add a small table inside the encrypted database (created by the app, not by Drift codegen, so it does not change the schema version merely by existing):

```sql
CREATE TABLE IF NOT EXISTS db_security_identity (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  database_id TEXT NOT NULL,
  key_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL,
  cipher_profile_id TEXT NOT NULL,
  format_version INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
```

On every successful open:

1. Read the internal anchor using the supplied key.
2. Compare `database_id`, `key_id`, `key_generation` and `cipher_profile_id` with external metadata and the recovery record.
3. If they disagree, fail closed and enter recovery. Do not “repair” by overwriting the anchor.
4. If external metadata is missing but the file decrypts with a known key, treat it as a recovery/repair case that requires explicit confirmation before rewriting metadata.
5. If the file does not decrypt and the header is not plaintext SQLite, do not attempt plaintext migration.

The anchor is the only trusted statement of “which database is this?” after decryption. It also prevents a stale metadata file from pointing at a different database file.

### 5.5 Key store requirements

Use a `DatabaseKeyStore` abstraction with:

- `read(keyId)`, `write(keyId, bytes)`, `delete(keyId)`, `listVersions()`.
- A dedicated, versioned slot per database identity; do not overwrite the only copy during rotation.
- Atomic write (temp + rename) and a verification read-back.
- No automatic deletion on a decryption error. A missing/corrupt key is a recovery condition, not a reason to erase evidence.
- No key material in logs, crash reports, analytics or error messages.

**Windows (blocking finding O1):** `flutter_secure_storage_windows` 3.1.2 stores a single DPAPI-encrypted JSON file at `getApplicationSupportDirectory()/flutter_secure_storage.dat`, which is `RoamingAppData`. It deletes the file on `FormatException` or `WindowsException` during load. Consequences:

- The DEK, backup passphrase, TLS private key and app-lock verifier can all disappear together.
- A roaming profile copied to another machine may fail DPAPI decryption, and the plugin then deletes the file.
- A corrupted file is not a recoverable “missing key” state; the evidence is removed.

**Required action:** move the live database, metadata, journal, backups and the DEK blob to a **non-roaming** location (`%LOCALAPPDATA%` or a dedicated app directory), and use a dedicated key store that does not auto-delete on failure. Options:

1. A small Windows DPAPI wrapper using the existing `win32` dependency, writing a versioned key blob under `%LOCALAPPDATA%\LocusPlanner\keys\`.
2. Windows Credential Manager via a dedicated adapter.
3. A patched/forked `flutter_secure_storage_windows` that does not delete the file and supports an explicit path.

At minimum, E0 must prove a simulated roaming/new-user scenario reaches a recovery screen and does not silently create a new database. Do not ship the current plugin behavior as the sole DEK store without this test.

**Android:** use Android Keystore-backed storage, verify behavior after app-data clear, reinstall, lock-screen change and device transfer, and treat any read failure as recovery. Keep the existing backup exclusion for `FlutterSecureStorage.xml`; do not rely on OS backup to carry the key.

### 5.6 Recovery envelope and recovery bundle

The recovery passphrase is never stored. The envelope wraps the DEK, and optionally the active backup passphrase, with a versioned KDF and AES-256-GCM. Bind all identifying fields as associated data.

```json
{
  "format": "locus.db.recovery",
  "formatVersion": 2,
  "purpose": "database-dek",
  "databaseId": "db-<uuid>",
  "keyId": "key-0001",
  "keyGeneration": 1,
  "cipherProfileId": "locus-sqlcipher4-raw-v1",
  "kdf": {
    "algorithm": "PBKDF2-HMAC-SHA256",
    "iterations": 600000,
    "salt": "<base64>",
    "passphraseNormalization": "NFC"
  },
  "cipher": "AES-256-GCM",
  "nonce": "<base64>",
  "wrappedDek": "<base64>",
  "tag": "<base64>"
}
```

If the bundle also wraps the backup credential, use a **separate** envelope entry with its own salt, nonce and AAD (`purpose: "backup-credential"`), not a single blob that hides which credential failed. The bundle may contain:

- `database-dek`: 32-byte DEK, bound to database ID/key ID/cipher profile.
- `backup-credential`: the backup passphrase, bound to the backup format and creation time.
- `metadata`: non-secret identifiers and a creation timestamp.

**AAD is mandatory.** It must include at least: format name, format version, purpose, database ID, key ID, key generation, cipher-profile ID, and (for the backup credential) backup format version. Any mismatch must fail authentication, not fall back to “try another credential”.

**KDF choice (O8):** Reuse the existing PBKDF2-HMAC-SHA256 + AES-256-GCM stack for the first version, with a versioned iteration count (start at 600,000, benchmark on low-end Android, never below the app’s existing 210,000 floor). If Argon2id is adopted later, add it as a new envelope version with a vetted implementation and a documented migration path. Do not silently change the KDF or iteration count for an existing envelope.

**Verification:** Immediately after creating a recovery envelope, unwrap it in memory with the entered passphrase and compare the recovered DEK to the active DEK. Only then tell the user recovery is configured. Test a clean-device unwrap before enabling production migration.

### 5.7 Credential matrix

| Operation | Live DEK | Recovery passphrase | Backup passphrase |
|---|---|---|---|
| Normal app open | Required (secure store) | Not required | Not required |
| Create logical backup (automatic) | Not required | Not required | Required after encryption is enabled; fail closed if absent |
| Create manual plaintext export | Not required | Not required | Not required, but explicit warning |
| Restore logical backup | Not required; new DB gets a fresh DEK | Not required | Required to decrypt the backup |
| Raw encrypted DB recovery | Old DEK recovered from bundle | Required | Not required |
| Key rotation | Old + new DEK | Required to create a new envelope, or envelope is marked stale | Not required |
| Change recovery passphrase | Same DEK | Old + new passphrase | Not required |

---

## 6. Connection lifecycle and startup decision model

### 6.1 Connection sequence

1. Acquire the migration/backup lock (see §7.1). If a hard lock cannot be acquired, do not migrate or replace files.
2. Resolve the database path and file identity.
3. Read external metadata (if present) and inspect the first 16 bytes of the database file.
4. Classify the file: missing, plaintext SQLite (`SQLite format 3\0`), encrypted/unknown, empty/zero-length, or corrupt.
5. Resolve the expected identity, key ID, key generation and cipher profile.
6. Load the DEK from the key store only for the expected identity. Do not generate a new key for an existing file.
7. Create the native SQLite connection with the cipher profile, apply cipher parameters and the key **before any schema access**, then run a real read (`SELECT count(*) FROM sqlite_master`).
8. Verify the internal identity anchor and external metadata agreement.
9. Run `PRAGMA integrity_check`/`quick_check` and `foreign_key_check` as appropriate.
10. Hand the configured connection to Drift.

Use `NativeDatabase.createInBackground(file, setup: ...)` (or the equivalent verified API) so the key is applied in the background isolate before Drift uses the database. Prove the ordering in E0; do not rely on a debug assert.

### 6.2 Startup decision table

| Detected state | Required behavior |
|---|---|
| No database, no metadata, no key | Create a new database with a newly generated DEK, new database ID, new key ID and current cipher profile. Persist the key before first use. |
| Plaintext SQLite database, no encryption metadata | Offer the controlled plaintext-to-encrypted migration. Do not silently overwrite or encrypt in place. |
| Plaintext SQLite database, metadata says encrypted | **Fail closed / recovery.** A plaintext file under an encrypted identity is a rollback, tamper or failed-conversion signal. Never open it as normal plaintext. |
| Encrypted/unknown file, metadata and key available | Open with the recorded cipher profile; verify identity and integrity. |
| Encrypted/unknown file, metadata missing | **Treat as encrypted/unknown and enter recovery.** Never attempt plaintext migration based only on the absence of metadata. |
| Encrypted/unknown file, key missing | Stop normal startup and show recovery. Never generate a replacement key. |
| Wrong key / authentication failure | Controlled unlock/recovery error; preserve files and diagnostic state. Do not delete or overwrite. |
| Metadata corrupt or unsupported format version | Fail closed and offer recovery/export support. Do not infer plaintext state. |
| Metadata exists, database file absent | Data-loss/recovery condition. Do not create an empty database under the same identity. |
| Migration journal indicates interrupted conversion | Resume or roll back using the explicit stage; never guess from file existence alone. |
| Cipher profile unsupported by this build | Fail closed with “unsupported encryption format”; do not try the library default. |
| Encryption extension unavailable or `PRAGMA cipher` fails | Fail closed; do not fall back to plaintext. |
| Quarantine directory present | Offer restore/cleanup; do not ignore it. |
| Zero-length database file | Treat as interrupted creation; recovery/cleanup path, not a valid new database. |

### 6.3 Error taxonomy

- `RECOVERY_REQUIRED`: key missing/unavailable or identity anchor unreachable.
- `UNLOCK_FAILED`: supplied recovery credential is wrong.
- `DATABASE_DAMAGED`: integrity/HMAC failure on the encrypted file.
- `MIGRATION_INTERRUPTED`: safe resume/rollback available.
- `UNSUPPORTED_ENCRYPTION`: app build cannot open this cipher profile/format.
- `KEY_STORE_CORRUPT`: secure store read/decrypt failure; preserve evidence.
- `IDENTITY_MISMATCH`: internal anchor and metadata disagree.
- `PLAINTEXT_UNDER_ENCRYPTED_IDENTITY`: fail closed; never migrate automatically.

Log error codes and stages, never keys, passphrases, salts used as secrets, raw envelopes or SQL containing key material.

---

## 7. Plaintext-to-encrypted conversion

### 7.1 Preconditions and exclusive access

- Enter maintenance mode: stop sync, reminders, background jobs, auto-backup and all database writes.
- Close the Drift database and every direct SQLite connection. Confirm no file handles remain.
- Acquire a hard migration lock (OS file lock) in addition to the UI single-instance check. If the lock cannot be acquired, abort; do not treat “check failed” as permission to proceed.
- Checkpoint WAL and close cleanly. Decide explicitly whether to copy sidecars or use a SQLite backup API.
- Check free disk space: source + sidecars + pre-encryption backup + temp encrypted copy + verification headroom.
- Require at least one of: a verified recovery bundle, or a verified encrypted logical backup, or explicit informed consent that key loss is irreversible. Record the choice in the migration journal.
- Never begin conversion on a file that failed `integrity_check` or whose identity cannot be established.

### 7.2 Durable migration journal

Write the journal as a small JSON file next to the database, using temp + flush + atomic rename. Include:

```json
{
  "formatVersion": 1,
  "databaseId": "db-<uuid>",
  "stage": "TEMP_CREATED",
  "sourcePath": "...",
  "sourceSidecars": ["...-wal", "...-shm"],
  "backupPath": "...",
  "tempPath": "...",
  "quarantinePath": "...",
  "oldKeyId": null,
  "newKeyId": "key-0001",
  "newKeyGeneration": 1,
  "cipherProfileId": "locus-sqlcipher4-raw-v1",
  "sourceChecksum": "sha256:...",
  "tempChecksum": "sha256:...",
  "startedAt": "...",
  "updatedAt": "...",
  "pid": 1234
}
```

Stages:

```text
NOT_STARTED
  -> PRECHECK_OK
  -> SNAPSHOT_CREATED
  -> KEY_CREATED
  -> TEMP_CREATED
  -> ENCRYPTION_APPLIED
  -> ENCRYPTED_DATABASE_VERIFIED
  -> DATABASE_REPLACED
  -> METADATA_COMMITTED
  -> MIGRATION_COMPLETE
```

A stage is complete only when its output is durable. On startup, use the journal, file existence, file header, key availability and checksums together; never a single signal.

### 7.3 File-level requirements (including sidecars)

- Do not use only `File.copy` on a live SQLite database. It can miss `-wal`/`-shm` and produce a database that is missing committed transactions.
- Prefer a SQLite consistent snapshot:
  - Open the source read-only, checkpoint/close cleanly, then use `VACUUM INTO` or the SQLite backup API; or
  - Copy the main file and all sidecars only after a successful checkpoint and with the source closed, and verify the copy by opening it and running integrity checks.
- Handle `-wal`, `-shm` and rollback `-journal` explicitly. Record them in the journal.
- Never attach stale sidecars from the old plaintext database to the encrypted replacement. Move old sidecars to quarantine or delete them only after the replacement has been verified.
- Create temp files on the same volume as the target where possible, with restrictive permissions.
- Write metadata/journal/temp files with `flush` (and, where supported, an fsync of the file and parent directory).
- Use an atomic replacement primitive:
  - Windows: `MoveFileEx`/`ReplaceFile` with write-through semantics where available.
  - POSIX/Android: rename within the same filesystem, then fsync the directory.
- If the platform cannot provide atomic replacement, do not claim crash safety; use a recovery journal and a clearly documented fallback.

### 7.4 Conversion procedure

1. Preflight: maintenance mode, hard lock, close all handles, checkpoint WAL, capture checksums, check disk space, confirm recovery/backup or explicit consent.
2. Create a consistent plaintext snapshot. Prefer a logical encrypted backup if a backup credential is already configured; otherwise create a labeled plaintext safety copy with restrictive permissions and a cleanup deadline.
3. Generate the new DEK, key ID and key generation; write the key slot with atomic write and read-back verification.
4. Persist the migration journal and the new identity metadata as “pending”.
5. Create a temporary copy on the same volume. Do not modify the original.
6. Apply encryption to the temporary copy using the exact SQLite3MC path for the selected version:
   - Plaintext source: `PRAGMA rekey` on the temporary database (or the documented conversion path), with the correct cipher/profile ordering.
   - Encrypted source: use `PRAGMA rekey`/the documented rekey path only after proving it preserves the profile.
7. Close the temp connection, reopen with the new key, and verify:
   - `PRAGMA integrity_check` and `foreign_key_check`.
   - Schema/table/index/trigger parity.
   - The internal identity anchor.
   - Per-table row counts and stable checksums.
   - `sync_row_versions`, `sync_outbox` head and `sqlite_sequence`.
   - Representative application queries.
8. Close all handles. Write the `ENCRYPTED_DATABASE_VERIFIED` stage.
9. Replace atomically:
   - Rename the original (and sidecars) to a quarantine directory under the old identity.
   - Rename the verified temp file into the live path.
   - Flush/fsync.
   - Write `DATABASE_REPLACED`.
10. Update metadata and journal to the new identity; write `METADATA_COMMITTED`.
11. Reopen through the normal connection factory and run a post-restart verification.
12. Only then mark `MIGRATION_COMPLETE`; retain the old key slot and quarantine until the user confirms, then clean up.
13. Never delete the only plaintext copy before the encrypted replacement has been independently reopened and verified.

### 7.5 Crash-point recovery

| Crash point | Required recovery behavior |
|---|---|
| After preflight, before key creation | No changes to live DB; clean temp/journal; restart normally. |
| After key creation, before temp creation | Delete/unused key slot only if no database references it; otherwise keep and resume. |
| After temp creation, before encryption | Original intact; resume from temp or discard and retry. |
| After rekey, before replacement | Original intact; temp may be encrypted. Verify temp; either complete replacement or discard temp and keep original. Never attach temp sidecars to the original. |
| After replacement, before metadata commit | Inspect journal + file header + key; if the new file decrypts and verifies, finish metadata; otherwise restore quarantine. Do not open as plaintext. |
| After metadata commit, before complete | Reopen and verify; finish or roll back using quarantine/key slot. |
| After secure-store update, before metadata update | Key generation/journal disambiguates; keep old slot; never generate a new key. |
| During quarantine move | Use a deterministic quarantine name and journal; recover by checking both paths and checksums. |

### 7.6 Verification: parity, not spot checks

Migration is not verified by row counts and a few representative IDs. Require:

- Full schema parity: `sqlite_master` tables, columns, indexes, triggers, views, constraints.
- `PRAGMA integrity_check` = ok and `PRAGMA foreign_key_check` empty.
- Per-table row count and a stable, order-insensitive checksum of canonical row values.
- `sqlite_sequence` values for auto-increment tables.
- `sync_row_versions` contents (including tombstones) and `sync_outbox` head/pruned-through.
- `app_settings` non-transient rows.
- Application-level invariants (for example one daily plan per day key, no orphan plan items, no task with missing project).
- A post-restart query through the real connection factory, not only the migration connection.

Use a canonical serialization (sorted rows, deterministic type encoding) so checksums are reproducible across platforms. Store the expected checksums in the migration journal and compare after reopen.

### 7.7 `VACUUM INTO` and rekey cautions

- Do not assume `VACUUM INTO` on an encrypted source produces an encrypted target with the same key/profile. The target is a new database; cipher inheritance is not guaranteed. E0 must prove the exact behavior.
- `PRAGMA rekey` is the documented way to encrypt an existing plaintext database or change a key, but it is not a normal rollbackable transaction. It must not run inside a transaction.
- SQLite3MC documentation notes WAL/rekey constraints for encrypting a plain database. Change journal mode as required and test the exact version.
- After rekey, close and reopen; do not trust the same connection’s cached state.
- For a pre-upgrade backup of an already encrypted database, use an encryption-aware snapshot. Never open an encrypted file with the unkeyed `backupDatabaseBeforeUpgrade()` path.

### 7.8 Legacy Documents copy

`_resolveDatabaseFile()` currently copies only the main file. A legacy database may have `-wal`/`-shm`; a plain `File.copy` can lose committed data. Replace this with:

- A clean checkpoint/close followed by a consistent snapshot; or
- A read-only open + `VACUUM INTO`/backup API into a temp file, then atomic rename.

After the app-support database is verified, the legacy Documents copy is still plaintext. Offer the user a clear choice: remove it, move it to a labeled encrypted archive, or keep it with an explicit warning that it is outside the encryption boundary. Do not silently leave it as the only backup while claiming the database is encrypted.

### 7.9 Pre-upgrade backup must be encryption-aware

`backupDatabaseBeforeUpgrade()` runs before the connection factory. It must be moved behind the encryption-aware bootstrap:

- If the file is plaintext and unversioned/older, create a plaintext pre-upgrade snapshot as today, but label it and clean it up after migration.
- If the file is encrypted, open it with the correct key/profile (or skip the pre-upgrade backup and rely on a verified logical backup). Do not create a plaintext `VACUUM INTO` copy.
- If the file is encrypted but the key is missing, do not create an empty/plaintext backup; enter recovery.
- If the file is not recognizable as SQLite and metadata is absent, do not attempt plaintext migration.

---

## 8. Backup and restore design

### 8.1 Two distinct recovery models

| Model | What is restored | Credential | Key/identity outcome |
|---|---|---|---|
| Logical backup recovery | Application rows from a JSON/`.locusbackup` file | Backup passphrase (if encrypted) | Create a **new** target database with a fresh DEK, new database ID and new key ID. Never require the old DEK. |
| Raw encrypted database recovery | The original encrypted SQLite file (plus sidecars) | Recovery passphrase to unwrap the original DEK | Reopen the **original** database with its original key ID/cipher profile. Do not import into a new database. |

The recovery package is primarily for raw-database/key recovery. A logical backup must remain usable without the old DEK, provided its own backup credential is available.

### 8.2 Backup format v3

The current format v2 is a set of JSON sections. Add a versioned, authenticated manifest and per-table checksums. A logical backup should include:

```json
{
  "format_version": 3,
  "database_schema_version": 16,
  "source_database_id": "db-<uuid>",
  "created_at": "...",
  "app_version": "...",
  "backup_encryption": "AES-256-GCM",
  "kdf": { "algorithm": "PBKDF2-HMAC-SHA256", "iterations": 600000, "salt": "...", "passphraseNormalization": "NFC" },
  "payload_sha256": "...",
  "tables": {
    "events": { "rows": 0, "sha256": "..." },
    "projects": { "rows": 0, "sha256": "..." }
  },
  "sections": { "...": "..." }
}
```

Do not put the database DEK, key ID or recovery secret in the logical backup. `source_database_id` is provenance only. If sync metadata is included in a future version, mark it explicitly as advisory and never let an old device ID/epoch override the restore target’s new identity.

### 8.3 Transactional and durable backup creation

For every automatic, pre-import, pre-upgrade, migration-safety and recovery backup:

1. Open one consistent read snapshot for all exported tables (a single read transaction, or a SQLite backup/`VACUUM INTO` for a physical backup). Do not run independent queries that can see different committed states.
2. Build the payload and manifest in memory or a temp file.
3. Write to a temp file in the same directory; flush the file; close it.
4. Atomically rename to the final name.
5. Reopen the completed file, decrypt/authenticate it, parse it, verify the manifest, per-table counts/checksums and schema compatibility.
6. Only after validation update `last_successful_backup_at` and prune older backups.
7. Always retain a last-known-good backup; never prune the only validated copy.
8. On any failure, leave the previous last-known-good backup untouched and surface an error; do not update the success timestamp.

After live encryption is enabled:

- Automatic backups must **fail closed** if no backup passphrase is configured. Do not silently write plaintext `auto_*.json`.
- Pre-import and pre-upgrade backups must use the same encrypted path; if no credential is available, block the operation or require the user to configure one.
- Manual plaintext export may remain, but only behind an explicit warning and the existing `backup.plain_export_acknowledged` setting. It must not be the automatic path.
- The pre-encryption migration safety copy is a special case: it is necessarily plaintext. Label it, restrict permissions, record it in the journal, and delete/quarantine it after the encrypted database is verified. Prefer requiring an encrypted logical backup before migration so this plaintext copy is not the only safety net.

### 8.4 Logical restore procedure

1. Authenticate/decrypt the backup with the backup credential before touching the live database.
2. Validate format/version, schema compatibility, manifest checksums and per-table counts.
3. Stop sync and all writes; acquire the maintenance lock.
4. Create a recovery backup of the current live database (encrypted, validated) or confirm the user has one.
5. Create a temporary target database with a **new** database ID, **new** DEK, **new** key ID and the current cipher profile. Do not reuse the old DEK.
6. Import/validate data in a transaction. If the import fails, discard the temp target; the old database remains untouched.
7. Run integrity, foreign-key and application-level validation.
8. Atomically replace/point the app at the new database; preserve the old database/key under quarantine until the new one reopens.
9. Reopen through the normal factory; verify the internal anchor, schema and checksums.
10. Create a new recovery envelope for the new database; optionally set a new backup passphrase. Mark old envelopes as pre-restore/stale.
11. Only then report restore success and update backup/restore status.

Do not require the original database DEK for this workflow. If the backup is encrypted, the backup credential is the only required secret.

### 8.5 Sync-state recovery and rebase (B4)

Current logical backups omit `sync_outbox`, `sync_row_versions`, `sync.device_id`, `sync.epoch`, `sync.outbox.pruned_through`, paired clients and TLS state. A restore therefore cannot resume the old sync history safely.

Define this behavior:

- A logical restore is a **new local dataset**, not a continuation of the old sync identity.
- Generate a new `deviceId` and a new `sync.epoch`.
- Clear `sync_outbox`, reset `sync.outbox.pruned_through`, and rebuild `sync_row_versions` deterministically for restored rows (or clear it and let the first local edit/import establish versions under the new epoch).
- Suppress sync outbox triggers during the import, or generate outbox rows only after the new epoch is established. Do not let the import inherit old outbox IDs/cursors.
- Unpair/re-pair devices and require a full resync/rebase. Do not merge restored rows with an old sync cursor.
- Define tombstone policy explicitly: a restored row must not resurrect a deletion that is newer in another device’s history. If the backup lacks tombstones, require a full authoritative resync or a user-confirmed merge; never assume absence means “not deleted.”
- Test: restore after deleting a row on another device; restore with pending outbox changes; restore a backup from a device that was later wiped; restore into an already-paired installation.

A future backup format may include sync metadata, but it must still be rebased to the new device/epoch unless the user explicitly chooses a “restore this exact device identity” workflow (which requires the old key/pairing state and should be rare).

### 8.6 Recovery bundle and clean-device flow

A clean-device flow must state which credential is needed:

1. **Logical backup path:** install app → choose logical backup → enter backup passphrase → create new database/identity → import → validate → create new recovery envelope.
2. **Raw database path:** install app → copy the encrypted database and sidecars into place (or select a raw backup) → choose recovery bundle → enter recovery passphrase → unwrap original DEK → verify internal anchor → open original database → optionally create a new envelope for the same key/identity.
3. If the recovery bundle wraps both the DEK and the backup passphrase, the user enters one recovery passphrase and the app can offer both paths. Clearly label which credential is being unwrapped.
4. If the bundle wraps only the DEK, logical recovery still requires the backup passphrase; the UI must say so before the user relies on the backup.

Test both paths on a clean install, with the old app data removed, on Windows and Android.

### 8.7 Raw encrypted database backup/recovery

- Create a consistent physical backup: close/checkpoint, or use the SQLite backup API; if copying live, include all sidecars and verify the copy.
- Record the database ID, key ID, key generation, cipher profile and checksum in the backup manifest.
- Verify the raw backup by opening it read-only with the key and running `integrity_check`.
- Recovery unwraps the **original** DEK using the recovery bundle and reopens the original database. Do not import it into a new database unless the user explicitly chooses a logical conversion.
- If the original DEK is unavailable, raw recovery is impossible; do not claim otherwise.
- Do not make raw encrypted DB copies the only backup format.

---

## 9. Android OS backup and Windows roaming

### 9.1 Android policy

**Chosen policy: exclude the live database and all related state from cloud backup and device-to-device transfer; use explicit logical exports.** An OS-restored encrypted database without its Keystore DEK is at best useless and at worst a confusing “corrupt database” state. Do not rely on OS backup to carry the key.

Update `backup_rules.xml` (Android 11 and older) and `data_extraction_rules.xml` (Android 12+) to exclude, in both `<cloud-backup>` and `<device-transfer>`:

- The live database file (`locus_planner.db`) and its `-wal`, `-shm`, `-journal` sidecars.
- The encryption metadata file (for example `locus_planner.db.meta.json`).
- The migration journal and any quarantine/rollback directory.
- The app’s automatic/manual/pre-import backup directory if it can contain plaintext files.
- Any key material shared-prefs file (keep the existing `FlutterSecureStorage.xml` exclusion).

Use the correct Android storage domain for the actual path. `path_provider`’s application support directory on Android is the app files directory, so the database is normally in `domain="file"`, not `domain="database"`. Verify the exact path on a device before shipping; do not copy a rule that excludes the wrong domain.

**Simplest safe option:** set `android:allowBackup="false"` for the app and provide explicit export/import. If backup is kept enabled, the exclusions above are mandatory and must be tested. Either way, test:

- Google cloud backup restore on a fresh install.
- Device-to-device transfer (Android 12+ `device-transfer`).
- Restore after app-data clear and after reinstall.
- Restore when the secure-store key is absent: the app must show recovery, not create an empty database.

### 9.2 Windows roaming and secure storage

`path_provider_windows` maps application support to `RoamingAppData`. `flutter_secure_storage_windows` 3.1.2 stores its DPAPI file in the same directory. A roaming profile, a new machine, or a profile migration can copy the encrypted database and the DPAPI blob together, but DPAPI user-scope decryption may fail on the new machine; the plugin then deletes the blob. This is a key-loss path, not just a UX issue.

Required design change:

- Store the live database, metadata, journal, quarantine and backups under `%LOCALAPPDATA%` (non-roaming), or a dedicated non-roaming directory.
- Store the DEK in a dedicated key store in that non-roaming location (DPAPI file with no auto-delete, Credential Manager, or an equivalent adapter).
- Keep only non-sensitive UI preferences in roaming storage.
- If roaming is deliberately supported, use a key store whose recovery behavior is proven and document the threat model. Do not rely on the current plugin’s auto-delete behavior.
- Test a simulated roaming copy/new Windows user: the app must enter recovery and must not generate a new key or delete the only key blob.

**Existing installations:** moving the database from Roaming to Local must be a controlled, journaled migration, not a path change that creates a new empty database. Use the same consistent-snapshot, verify, atomic-replace and quarantine rules as §7; keep the old location until the new one reopens, and only then remove/quarantine the old copy. Test an upgrade from the current 1.4.0 layout.

---

## 10. Key rotation, recovery envelope and encryption disablement

### 10.1 Rotation

Rotation is a maintenance operation, not an incidental startup action.

1. Preflight: verified recovery bundle and/or encrypted logical backup; stop writes, sync and background jobs; acquire the hard lock; close all connections.
2. Create a new key ID and 32-byte DEK; write the new key slot with read-back verification. Keep the old slot.
3. Create a verified temporary copy of the database and rekey it to the new DEK using the selected cipher profile.
4. Reopen the temporary database with the new key; verify integrity, foreign keys, schema, identity anchor and per-table parity.
5. Atomically replace the live database; write a rotation journal with old/new key IDs and stages.
6. Reopen through the normal factory and verify again.
7. Ask the user for the recovery passphrase to create a **new** recovery envelope for the new key, or explicitly mark the previous envelope as “pre-rotation, invalid for the current database.” Do not silently update an envelope you cannot unwrap.
8. Only after the new database and envelope are verified, delete/retire the old key slot. Retain it while a quarantine/rollback copy exists.
9. If any step fails, retain the original database/key pair and expose a clear recovery state.

### 10.2 Changing only the recovery passphrase

Changing the recovery passphrase is a **rewrap of the same DEK**, not a database key rotation:

- Unwrap the existing envelope with the old passphrase.
- Create a new envelope with a new salt/nonce and a new AAD (same database ID/key ID/profile).
- Verify the new envelope by unwrapping it.
- Delete/invalidate the old envelope only after verification.
- Do not change the database file or DEK.

### 10.3 Disabling encryption

Do not provide a casual toggle. If decryption/export is ever supported, require:

- A verified encrypted backup and recovery envelope.
- An explicit warning about plaintext exposure and residual copies.
- Explicit confirmation.
- A temporary plaintext database on a secure local path, atomic replacement, verification, and a cleanup plan for plaintext temp files and backups.
- Re-encryption or secure deletion guidance; do not claim secure erasure on SSDs/flash.

### 10.4 “Start fresh” / quarantine

If the user explicitly chooses to start fresh after a key-loss or identity failure:

- Quarantine the old database, `-wal`, `-shm`, `-journal`, metadata, migration journal and recovery envelopes under a clearly named old-identity directory.
- Retain the old versioned secure-store key slot; do not delete it.
- Create a new database under a new database ID, key ID and key generation.
- Offer export/recovery of the quarantine before any cleanup.
- Require explicit confirmation; “start fresh” must never be the default action.

---

## 11. Plaintext artifact inventory and cleanup

| Artifact | Location/creator | Plaintext? | Required policy |
|---|---|---|---|
| Live database before migration | App support | Yes | Convert; preserve until encrypted replacement verified; then quarantine/delete with consent. |
| Legacy Documents database | `Documents/locus_planner.db` | Yes | Consistent copy (including sidecars); after verification, offer removal/move; warn that Documents may be OneDrive-synced. |
| Legacy sidecars | `Documents/locus_planner.db-wal`/`-shm`/`-journal` | Yes | Copy with the main file or checkpoint; never leave stale sidecars attached to a new file. |
| Pre-migration `.bak` | `backupDatabaseBeforeUpgrade()` | Yes | Label, restrict permissions, record in journal, delete/quarantine after verification; do not leave indefinitely. |
| Migration temp files | Temp conversion path | Yes before rekey | Restrictive permissions, same-volume temp, cleanup on success/failure, no plaintext sidecars after replacement. |
| Automatic backups | `backups/auto_*.json` or `.locusbackup` | Currently can be plaintext | Fail closed after encryption; migrate existing plaintext backups or warn/delete with consent. |
| Manual/recovery backups | `backups/manual_*` | Can be plaintext | Encrypt after encryption; if plaintext, explicit warning and cleanup. |
| Pre-import backups | `backups/pre_import_*` | Can be plaintext | Encrypt or fail closed; delete/retain per policy. |
| Manual JSON/ICS exports | User-selected path | Yes | Explicit warning; user-owned; not covered by live DB encryption. |
| Quarantine directory | Old DB/key identity | Encrypted (old key) | Retain until user confirms; document old key slot; cleanup with consent. |
| `flutter_secure_storage.dat` | Windows app support (roaming) | DPAPI-encrypted secrets | Move to non-roaming; do not auto-delete; include in key-loss testing. |
| SQLite temp files | OS temp/app temp | Must be encrypted or avoided | Use SQLite3MC 2.6+ temp encryption and/or `temp_store=MEMORY`; test large sorts/migrations; clean app-private temp. |
| Crash dumps/logs | OS/app logs | Must not contain keys | Redact; never log SQL with key material or envelope contents. |
| OS/cloud copies | OneDrive, roaming profile, Android backup | Varies | Exclude live DB/sidecars/metadata; document residual copies; test restore. |

**Cleanup rules:**

- Never delete the only copy before the encrypted replacement/recovery is verified.
- `deleteUnencryptedBackups()` must be expanded to identify `.bak`, legacy Documents files, migration temp files and failed conversion copies. Do not silently delete manual user exports without confirmation.
- Use OS-supported deletion and explain residual limitations on SSDs/flash. Do not claim secure erasure.
- Record every retained plaintext artifact in the security UI with its path, age and reason.

---

## 12. UI and user experience

### 12.1 Security & Data Protection page

- Live database encryption status: encrypted, migrating, recovery required, unsupported.
- Database ID, key ID/generation, cipher profile ID (non-secret).
- Recovery bundle status: not configured, verified, stale/pre-rotation, missing.
- Backup credential status and last successful validated backup.
- Manual backup action; explicit plaintext export warning.
- Clear explanation of what encryption protects and what it does not.
- No keys, salts used as secrets, raw envelopes or cipher diagnostics.

### 12.2 Migration screen

- Explain why migration is happening and that a backup is being created.
- Show meaningful stages, not a fake percentage.
- Warn not to close the app or power off.
- Offer resume/rollback if interrupted.
- Do not delete the plaintext safety copy before successful verification.
- Require recovery/backup or explicit informed consent before starting.

### 12.3 Recovery screen

- Explain that the existing database is encrypted and the key is unavailable.
- Allow selecting a recovery bundle and entering the recovery passphrase.
- Explain the difference between logical backup recovery (backup passphrase) and raw database recovery (recovery passphrase).
- Do not offer “start fresh” as the default or silently create an empty database.
- If the user explicitly starts fresh, quarantine the old files and key slot with clear confirmation.

---

## 13. Testing strategy

### 13.1 Key and envelope tests

- DEK generation produces exactly 32 random bytes.
- Key-store persistence/retrieval across restarts; versioned slots; no overwrite of the active slot.
- Missing key, corrupted key blob, wrong key and secure-store delete/failure do not create a replacement database.
- Recovery envelope round-trip with correct passphrase; wrong passphrase/tampered AAD fails.
- Recovery envelope AAD binds database ID, key ID, generation, purpose, format and cipher profile.
- Rotation failure preserves the original DB/key pair; old envelope is not silently claimed valid.
- Changing only the recovery passphrase rewraps the same DEK.

### 13.2 E0 native integration matrix

| ID | Test | Windows | Android |
|---|---|---|---|
| E0-01 | Create encrypted DB, write, close, reopen with same key | Required | Required |
| E0-02 | Wrong key fails; no empty DB, no write, no key regeneration | Required | Required |
| E0-03 | Unkeyed SQLite cannot read the encrypted DB | Required | Required |
| E0-04 | `PRAGMA cipher`/version check passes at runtime in release | Required | Required |
| E0-05 | Key applied before first schema access in background isolate | Required | Required |
| E0-06 | Raw-key syntax exactly as specified; `hexkey` not misused | Required | Required |
| E0-07 | WAL write, checkpoint, close, reopen, `integrity_check` | Required | Required |
| E0-08 | Schema-16 plaintext copy converts without data loss | Required | Required |
| E0-09 | Legacy Documents copy (including WAL/SHM) converts or migrates safely | Required | N/A |
| E0-10 | Interrupted conversion at every stage; sidecar handling | Required | Required |
| E0-11 | Raw-DEK rekey/rotation; old key retained; new key reopens | Required | Required |
| E0-12 | Physical-backup target is encrypted and reopens with the key | Required | Required |
| E0-13 | Large sort/index/migration temp-store behavior; no plaintext spill | Required | Required |
| E0-14 | Cipher profile persists across a dependency upgrade | Required | Required |
| E0-15 | `VACUUM INTO`/`PRAGMA rekey` on encrypted source behaves as specified | Required | Required |
| E0-16 | Windows roaming/new-user simulated copy: recovery, no key deletion | Required | N/A |
| E0-17 | Android cloud restore: recovery, not empty DB | N/A | Required |
| E0-18 | Android device-to-device transfer: recovery, not empty DB | N/A | Required |
| E0-19 | Release artifact contains the correct native library/ABI; no system fallback | Required | Required |
| E0-20 | Memory/temp cleanup and no key material in logs | Required | Required |

### 13.3 Migration and failure injection

- Fresh installation creates an encrypted database.
- Existing schema-16 plaintext database migrates without data loss.
- Legacy database location migration works together with encryption migration.
- Pending WAL writes are preserved; sidecars are handled correctly.
- Simulate process termination at every journal stage, including after rekey/before replace, after replace/before metadata, and after key-store update/before metadata.
- Failed temp conversion, failed verification, failed replacement, low disk space, read-only files, permission errors.
- Corrupt metadata, missing key, missing database, zero-length file, plaintext file under an encrypted identity.
- Post-restart verification through the real factory.
- Full per-table parity/checksums, not only row counts.

### 13.4 Backup and restore matrix

- Automatic backup with no credential: fails closed after encryption; no plaintext file.
- Automatic backup with credential: one snapshot, temp/rename, reopens/decrypts, validates, only then updates timestamp/prunes.
- Crash during backup write: previous last-known-good remains; no truncated “valid” file.
- Logical restore: new database ID/DEK/key ID; old DEK not required; new recovery envelope created.
- Raw restore: original DEK unwrapped; original database reopens; identity anchor matches.
- Clean-device logical restore: backup passphrase required; app creates new identity.
- Clean-device raw restore: recovery passphrase required; app reopens original identity.
- Sync rebase: new device ID/epoch; outbox/row versions reset; tombstones do not resurrect; full resync/re-pair.
- Backup/restore across app versions and schema versions.
- Android cloud backup/device transfer: excluded files absent; explicit export works.
- Windows roaming copy: recovery, not silent key loss.

### 13.5 Application data validation

Compare all major domains before/after migration: tasks, projects, recurrence, My Day associations, events, reminders, habits, diary entries, focus records, insights, settings, sync outbox, sync row versions, tombstones, device pairing and any other persisted feature tables. Include `sqlite_sequence`, schema objects and trigger definitions.

### 13.6 Existing tests to adapt

- `test/data_layer_test.dart`
- `test/database_backup_test.dart`
- `test/my_day_test.dart`
- `test/schema_remediation_test.dart`
- `test/startup_checks_test.dart`

Keep in-memory Drift tests for business logic. Add a native encrypted-database integration suite and a source-level/test guard that prevents unkeyed direct SQLite opens from reappearing in production code.

---

## 14. Implementation roadmap

| Phase | Scope | Exit criteria |
|---|---|---|
| E0 — Compatibility and cipher gate | Choose Option A or B; prove SQLite3MC + Drift integration, key setup, release packaging, WAL, wrong-key, conversion, rekey, temp store, cipher-profile persistence, Android/Windows OS backup behavior. | All E0 matrix tests pass on real release artifacts; dependency path and cipher profile are pinned; no production migration yet. |
| E1 — Key infrastructure | Key store, key service, metadata, internal anchor, recovery bundle, envelope AAD, Windows non-roaming key storage. | Key lifecycle, recovery, clean-device and key-loss tests pass; no key material leaks. |
| E2 — Encrypted connection | Connection factory, encrypted startup for new databases, audit all direct SQLite access, encryption-aware pre-upgrade backup. | New DB encrypted; existing DB never opened as plaintext; every production path uses the factory. |
| E3 — Existing DB migration | Journal, consistent snapshot, sidecars, temp conversion, verification, atomic replacement, rollback/resume, legacy Documents handling. | Schema-16 plaintext migration passes failure injection and full parity/checksum tests. |
| E4 — Backup/recovery/UI | Logical v3 backups, transactional backup creation, two recovery models, sync rebase, recovery UI, security settings. | Backup/recovery matrix passes on Windows and Android; clean-device restore works. |
| E5 — Release hardening | Android backup rules, Windows roaming fix, release packaging, diagnostics, cleanup policy. | Cloud restore/device transfer/roaming tests pass; release candidates pass full regression. |

**Gate:** Do not start E1/E3 production work until E0 passes and the backup/recovery protocol (including the two-credential model and sync rebase) is revised. Keep production migration disabled until the crash-atomic journal and plaintext-artifact policies are fully implemented.

---

## 15. Release acceptance criteria

- New installations create an encrypted database by default.
- Existing plaintext installations migrate without loss and recover after interruption.
- The live database cannot be read by a normal unkeyed SQLite connection.
- The DEK exists only in platform-backed secure storage and optional passphrase-wrapped recovery material.
- Missing keys never trigger silent database recreation or plaintext fallback.
- Every production database connection, backup, maintenance and migration path is encryption-aware.
- Logical backups are authenticated/encrypted and validated by read-back; automatic backups never silently fall back to plaintext after encryption.
- Android cloud backup/device transfer cannot produce an encrypted database without its key; explicit logical export works.
- Windows roaming/new-user scenarios reach recovery and do not delete the only key.
- A verified recovery bundle or logical backup can restore data on a clean device.
- Sync restore creates a new identity/epoch and does not resurrect deletions or lose pending changes.
- Migration verifies full per-table parity/checksums and preserves sidecars/triggers/sequence state.
- All retained plaintext copies are enumerated, labeled and cleaned up with consent.
- Diagnostics contain useful error codes/stages but never key material or passphrases.

---

## 16. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Native library/build incompatibility | E0 Option A/B decision; pin source/checksum; test actual release artifacts on both platforms; no system SQLite fallback. |
| Hook snippet used with incompatible versions | Treat it as illustrative; remove it from executable build config until the dependency upgrade is complete. |
| Key loss or secure-store reset | Recovery bundle; versioned key slots; no auto-delete; Windows non-roaming key store; never auto-generate a replacement key for an existing DB. |
| Windows roaming/DPAPI failure | Move sensitive state to `%LOCALAPPDATA%`; dedicated key store; test new-machine/roaming restore. |
| Android OS restore without key | Exclude DB/sidecars/metadata from backup/device transfer; explicit export; test both paths. |
| Plaintext backup left behind | Full inventory; labeling; retention/cleanup; expand `deleteUnencryptedBackups()`; warn about SSD/flash limits. |
| Crash during conversion | Durable journal; consistent snapshot; sidecar handling; temp+rename; stage-by-stage recovery; keep original until verified. |
| Direct SQLite access bypasses key | Central factory; code audit; regression guard; encryption-aware pre-upgrade backup. |
| Restore corrupts current data | Validate temp restore first; recovery backup; atomic replacement; quarantine old DB/key. |
| `VACUUM INTO`/rekey produces plaintext or changes profile | E0 test; keyed verification; never assume inheritance; prefer a verified conversion path. |
| Temp files spill plaintext | SQLite3MC 2.6+ temp encryption; `temp_store=MEMORY`; test large sorts/migrations; app-private temp cleanup. |
| Encryption creates false sense of security | Explain at-rest-only protection; retain app lock and OS security; document unencrypted exports/backups. |

---

## 17. Engineering decisions to lock before implementation

- Option A (coordinated upgrade) or Option B (custom SQLite3MC) with exact versions, source/checksum and build flags.
- Exact cipher profile: scheme, raw/passphrase mode, key syntax, PRAGMA order, page size, KDF/HMAC settings, temp store and memory security.
- Exact key-store implementation on Windows (non-roaming, no auto-delete) and Android (Keystore behavior under backup/reinstall/device transfer).
- Recovery envelope/bundle format, KDF and benchmarked parameters; whether the bundle wraps the backup credential.
- Migration journal location, atomic replacement primitive, sidecar policy and cleanup policy per platform.
- Windows database location (`%LOCALAPPDATA%` vs roaming) and migration path for existing installs.
- Android backup policy (`allowBackup=false` vs explicit exclusions) and exact storage-domain paths.
- Logical backup v3 manifest/checksum format and sync rebase policy.
- Whether recovery is mandatory or strongly encouraged before migration; the recommended UX is to require a verified recovery bundle or encrypted logical backup, or obtain explicit informed consent about irreversible key loss.

---

## 18. Final recommendation

Implement this in gated phases, starting with E0. The most important engineering rule is to treat encryption as a **database lifecycle and recovery project**, not a cipher flag added to the SQLite connection. The dependency route, key lifecycle, plaintext conversion, direct SQLite callers, startup failure behavior, backup/recovery credentials, Android OS backup and Windows roaming are all part of the security boundary.

Do not ship until the encrypted database can be created, reopened, migrated, backed up, restored and recovered reliably on both Windows and Android release builds, including a clean-device logical restore and a raw-database recovery.

**Recommended immediate next step:** build the E0 spike using one explicit dependency path (prefer the coordinated upgrade if the team can absorb it; otherwise the custom SQLite3MC build), freeze the cipher profile, and demonstrate create → write → close → reopen → wrong-key rejection → integrity check → schema-16 conversion → rekey/rotation → temp-store check on Windows and Android. In parallel, revise the backup/recovery protocol and the Windows/Android key-storage design before any user database is migrated.

---

## Appendix A — Cipher profile registry template

```json
{
  "profileId": "locus-sqlcipher4-raw-v1",
  "status": "candidate-until-E0",
  "library": "sqlite3mc",
  "libraryVersion": "<fill in E0>",
  "sourceChecksum": "<fill in E0>",
  "cipher": "sqlcipher",
  "legacy": 4,
  "keyMode": "raw-256",
  "keyEncoding": "hex-64",
  "keyPragma": "PRAGMA key = \"x'<64 hex chars>'\"",
  "passphrasePragma": "PRAGMA key = '<passphrase>'",
  "pragmaOrder": [
    "PRAGMA cipher = 'sqlcipher'",
    "PRAGMA legacy = 4",
    "PRAGMA page_size = 4096",
    "PRAGMA key = \"x'<64 hex chars>'\""
  ],
  "pageSize": 4096,
  "kdf": { "algorithm": "SHA512", "iterations": 256000, "appliesTo": "passphrase-only" },
  "hmac": { "algorithm": "SHA512", "enabled": true },
  "plaintextHeaderSize": 0,
  "journalMode": "WAL",
  "tempStore": "MEMORY",
  "memorySecurity": "FILL",
  "verificationQuery": "SELECT count(*) FROM sqlite_master",
  "extensionCheck": "PRAGMA cipher"
}
```

The concrete values must be replaced with E0 results. Do not treat this template as a verified configuration.

## Appendix B — External metadata template

```json
{
  "formatVersion": 2,
  "databaseId": "db-<uuid>",
  "activeKeyId": "key-0001",
  "keyGeneration": 1,
  "cipherProfileId": "locus-sqlcipher4-raw-v1",
  "encryptionEnabled": true,
  "databaseFile": "locus_planner.db",
  "createdAt": "...",
  "lastOpenedAt": "..."
}
```

## Appendix C — Internal identity anchor

```sql
CREATE TABLE IF NOT EXISTS db_security_identity (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  database_id TEXT NOT NULL,
  key_id TEXT NOT NULL,
  key_generation INTEGER NOT NULL,
  cipher_profile_id TEXT NOT NULL,
  format_version INTEGER NOT NULL,
  created_at TEXT NOT NULL
);
```

## Appendix D — Recovery bundle template

```json
{
  "format": "locus.db.recovery",
  "formatVersion": 2,
  "databaseId": "db-<uuid>",
  "keyId": "key-0001",
  "keyGeneration": 1,
  "cipherProfileId": "locus-sqlcipher4-raw-v1",
  "createdAt": "...",
  "entries": [
    {
      "purpose": "database-dek",
      "kdf": { "algorithm": "PBKDF2-HMAC-SHA256", "iterations": 600000, "salt": "<base64>", "passphraseNormalization": "NFC" },
      "cipher": "AES-256-GCM",
      "nonce": "<base64>",
      "ciphertext": "<base64>",
      "tag": "<base64>",
      "aad": "locus.db.recovery|2|database-dek|db-<uuid>|key-0001|1|locus-sqlcipher4-raw-v1"
    }
  ]
}
```

If a backup credential is wrapped, add a second entry with `purpose: "backup-credential"` and its own salt/nonce/AAD. Never reuse the DEK entry’s nonce or salt.

## Appendix E — Selected references

- SQLite3MultipleCiphers: key handling, `PRAGMA key`/`hexkey`/`rekey`, cipher configuration and temporary-file encryption (utelle.github.io/SQLite3MultipleCiphers).
- Drift encryption guide: SQLite3MC build hooks for Drift 2.32+/`sqlite3` 3.x, `NativeDatabase.createInBackground(..., setup:)`, existing-database conversion and SQLCipher compatibility (`PRAGMA cipher='sqlcipher'`, `PRAGMA legacy=4`).
- Project files cited in §2 and the review disposition.
