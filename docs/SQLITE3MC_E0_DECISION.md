# SQLite3MultipleCiphers (E0) decision record

**Status:** runtime integration passed on Windows and Android emulator; the
production migration gate is still closed.
**Applies to:** Phase B of the database reliability, native encryption and
recovery schema (v1.0).
**Decision:** Track B — custom native integration, retaining the locked Drift
and `sqlite3` versions.

## Selected dependency set

| Package | Version | Note |
|---|---|---|
| `drift` | 2.31.0 | Unchanged. |
| `sqlite3` | 2.9.4 | Unchanged; explicit `FfiSqlite3` bindings are created for the cipher library. |
| `sqlite3_flutter_libs` | 0.5.42 | Kept for the stock SQLite path when encryption is disabled. |
| SQLite3MultipleCiphers | 2.6.1 | Built on SQLite 3.54.0. |

Track B was selected because it avoids an unplanned Drift/code-generation
upgrade while still producing a genuinely encrypted database. No dependency
version was changed for Phase B.

## Native library and packaging

### Windows

- File: `third_party/sqlite3mc/windows/sqlite3mc_x64.dll`
- Upstream archive: `sqlite3mc-2.6.1-sqlite-3.54.0-win64.zip`
- Archive SHA-256:
  `0183b85d2abc9e3418abd92736cb71355b2bc933f6cda6b56f91653e6628cd74`
- DLL SHA-256:
  `683927db7e16cca301c5f2a236830de28c26b47f01d948f6abf2f0d60776ce4d`
- Packaging: `windows/CMakeLists.txt` installs the DLL next to the runner
  executable. The loader also accepts `LOCUS_SQLITE3MC_DLL` and a development
  checkout path for tests.

### Android

- Files: `third_party/sqlite3mc/android/<abi>/libsqliteX.so`
- Upstream archive: `sqlite3mc-2.6.1-sqlite-3.54.0-android.aar`
- Archive SHA-256:
  `4f157b7f845afbe5ee03731adc12b074fb95cc12cf4ca28113739ca43b55e80b`
- ABIs: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`
- Packaging: `android/app/build.gradle.kts` adds
  `third_party/sqlite3mc/android` as a `jniLibs` source directory. The release
  APK contains `lib/<abi>/libsqliteX.so` next to the stock
  `lib/<abi>/libsqlite3.so`.
- The library keeps its upstream SONAME/name (`libsqliteX.so`), so it cannot be
  confused with the system or `sqlite3_flutter_libs` library.

Licenses: `third_party/sqlite3mc/LICENSE` and `LICENSE.spdx` (SQLite3MC is MIT).

## Loading and isolation

`lib/core/security/sqlite3mc.dart` performs the integration:

- `Sqlite3mcLoader.ensureConfigured()` installs the platform `DynamicLibrary`
  loader before the first SQLite access in an isolate.
- Drift's background isolate receives the same setup through
  `NativeDatabase.createInBackground(..., isolateSetup: ...)`.
- `SqliteRuntime` creates an explicit `FfiSqlite3` instance backed by the
  verified library. This is deliberate: `package:sqlite3` caches one global
  library per isolate, so relying on being the first consumer would make the
  security layer order-dependent.
- Encryption-disabled builds never configure the loader and keep the stock
  library.

## Key application and cipher profile

Profile: `locus-sqlcipher4-raw-v1` (frozen; changing it requires a tested
migration or rotation).

| Setting | Value |
|---|---|
| Cipher | `sqlcipher` |
| Key mode | Raw 256-bit key, no passphrase KDF |
| Key literal | `x'<64 lowercase hex characters>'` |
| Compatibility | `PRAGMA legacy = 4` (SQLCipher v4 parameter set) |
| Page size | 4096 |
| Temporary storage | `PRAGMA temp_store = MEMORY` |
| Memory cleaning | `PRAGMA memory_security = FILL` |
| Verification read | `SELECT count(*) FROM sqlite_master` after `PRAGMA key` |

Exact PRAGMA order (outside a transaction):

1. `PRAGMA cipher = 'sqlcipher'`
2. `PRAGMA legacy = 4`
3. `PRAGMA page_size = 4096`
4. `PRAGMA temp_store = MEMORY`
5. `PRAGMA memory_security = FILL`
6. `PRAGMA key = "x'<hex>'"`

Rotation uses `PRAGMA rekey = "x'<hex>'"` on a connection that already has the
old key and profile active. A passphrase is never passed to SQLite3MC; the
32-byte DEK is used directly. This distinguishes a raw key from a passphrase
that happens to have 32 characters.

## Runtime verification

When live encryption is enabled, every process performs this before opening the
database:

1. Load the bundled library and read `sqlite3mc_version()`; reject anything
   older than 2.6.1.
2. Confirm that `PRAGMA cipher` is supported.
3. Run a complete encrypted round trip in a temporary directory:
   create with a random DEK, verify the file header is not plaintext, reopen
   with the correct DEK, confirm rows, reject a wrong DEK, and confirm
   `temp_store = MEMORY` and page size 4096.
4. Fail startup with `ENCRYPTION_EXTENSION_UNAVAILABLE` on any failure.

Evidence:

- Windows development DLL and the DLL copied into
  `build/windows/x64/runner/Release/` both pass
  `dart run tool/sqlite3mc_e0.dart` with
  `runtimeVersion = SQLite3 Multiple Ciphers 2.6.1`,
  `encryptedHeader = true`, `wrongKeyRejected = true`,
  `tempStore = 2`, `pageSize = 4096`.
- `flutter build windows --release` succeeds and the bundle contains
  `sqlite3mc_x64.dll`.
- `flutter build apk --release` succeeds and the APK contains
  `lib/arm64-v8a/libsqliteX.so`, `lib/armeabi-v7a/libsqliteX.so` and
  `lib/x86_64/libsqliteX.so`.
- `flutter test integration_test/sqlite3mc_e0_test.dart -d emulator-5554`
  passes on the `Medium_Phone_API_37.0` emulator (x86_64), proving the same
  round trip on Android.

## Migration safety switch

Live encryption and automatic conversion are separate switches:

| Environment | Meaning |
|---|---|
| `LOCUS_DB_ENCRYPTION=1` | Load and verify SQLite3MC; encrypted databases may be opened. |
| `LOCUS_DB_MIGRATION=1` | Allow a recognized plaintext database to be converted at startup. |

Without `LOCUS_DB_MIGRATION`, a plaintext database is left byte-identical and
startup fails closed with a recovery message. This keeps production data
untouched until the release gates pass.

## Known limitations / evidence still required

- Android verification used an emulator, not a physical release device.
- Schema-16 conversion and DEK rotation have end-to-end automated tests on
  Windows, but not yet on an Android device.
- Large sorts, index builds, imports and exports were not separately exercised
  on Android. `temp_store = MEMORY` is configured and asserted, but SQLite3MC
  temporary-file encryption has not been independently proven.
- Old recovery material can be identified as stale
  (`RecoveryBundle.isCurrentFor`), but the Phase C UI and envelope persistence
  that present a new envelope after rotation do not exist yet.
- Production migration remains disabled until all Phase B and Phase C gates in
  the schema pass on release artifacts.
