# SQLite3MultipleCiphers (E0) decision record

**Status:** open — not passed.
**Applies to:** Phase B of the database reliability, native encryption and
recovery schema (v1.0).
**Decision owner:** project maintainer.
**Production gate:** `LOCUS_DB_ENCRYPTION` must stay unset or `0` until this
record is marked passed.

## Context

Phase A (reliability) is implemented. The Dart-side architecture can already
create a key, write an identity anchor, journal a conversion and verify parity,
but the native cipher is still missing.

The locked dependency set is:

| Package | Locked version | Relevance |
|---|---|---|
| `drift` | 2.31.0 | No build hook for a cipher library. |
| `sqlite3` | 2.9.4 | Loads the platform SQLite library. |
| `sqlite3_flutter_libs` | 0.5.42 | Bundles stock SQLite, not SQLite3MC. |

`SqliteCipherRuntime.applyKey` runs `PRAGMA key` followed by
`SELECT count(*) FROM sqlite_master`. With the stock library the pragma is
ignored and the file remains plaintext, so the layer deliberately treats the
probe as unavailable and maps it to
`ENCRYPTION_EXTENSION_UNAVAILABLE`. No plaintext fallback is permitted.

## Decision

- Keep live encryption disabled in release builds.
- Do not ship a partial cipher: an unproven native path must not claim that
  data is encrypted.
- Do not convert production databases automatically.
- Do not weaken the startup classifier while the cipher is unavailable.

## Evidence required before this record can be marked passed

E0 must be executed on real Windows and Android release artifacts, not mocks:

1. **Library identity** — concrete SQLite3MC version, DLL/SO name, ABI and
   checksum recorded in the build.
2. **Raw-key round-trip** — create, reopen and verify a database with the
   selected `locus-sqlcipher4-raw-v1` profile.
3. **Wrong key** — opening with a different DEK fails before any application
   query.
4. **Temp storage** — large sorts, index creation, schema migration, import,
   export and spill queries do not write plaintext temporary files.
5. **Sidecars** — WAL/SHM/journal handling after conversion and crash.
6. **Interrupted conversion** — kill the process at each journal stage and prove
   deterministic resume/rollback with the original preserved.
7. **Rotation** — rekey to a new DEK, verify parity, activate the new generation
   and keep the old material until recovery is updated.
8. **Android storage** — same-filesystem replacement, flush and cleanup on
   adopted/internal storage.
9. **Recovery** — clean-device unwrap of the recovery envelope with the correct
   passphrase and rejection with a wrong one.

## Consequence of leaving this open

Schema-16 plaintext databases continue to be used. Protection against database
tampering and accidental cross-installation adoption comes from Phase A
(identity anchor, classification, atomic replacement, journals, parity), not
from at-rest encryption. Backup encryption and the backup passphrase are
independent of E0 and remain available.
