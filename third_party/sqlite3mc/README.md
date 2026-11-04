# SQLite3MultipleCiphers

Vendored native libraries for live database encryption (Phase B).

- Upstream: https://github.com/utelle/SQLite3MultipleCiphers
- Version: 2.6.1 (SQLite 3.54.0)
- License: MIT (see `LICENSE`)

## Contents

| Path | Source |
|---|---|
| `windows/sqlite3mc_x64.dll` | `sqlite3mc-2.6.1-sqlite-3.54.0-win64.zip` → `dll/sqlite3mc_x64.dll` |
| `android/<abi>/libsqliteX.so` | `sqlite3mc-2.6.1-sqlite-3.54.0-android.aar` → `jni/<abi>/libsqliteX.so` |

ABIs: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`.

Archive SHA-256:

```text
0183b85d2abc9e3418abd92736cb71355b2bc933f6cda6b56f91653e6628cd74  sqlite3mc-2.6.1-sqlite-3.54.0-win64.zip
4f157b7f845afbe5ee03731adc12b074fb95cc12cf4ca28113739ca43b55e80b  sqlite3mc-2.6.1-sqlite-3.54.0-android.aar
```

Library SHA-256:

```text
683927db7e16cca301c5f2a236830de28c26b47f01d948f6abf2f0d60776ce4d  windows/sqlite3mc_x64.dll
15359c385d78094c8c59235562bee134c3b0424497244d3a2e3b854b1340dcf9  android/arm64-v8a/libsqliteX.so
e4c1afd30491dee770bc736ee4be27507760be49a0a70f16990c74c33a585820  android/armeabi-v7a/libsqliteX.so
69bf00aa5026309344498500b7077ffc81353ac4898d939ad3e163d76601098a  android/x86/libsqliteX.so
170c2e56c7b106b6c8e173ad4ec0e0665307cd62ecfbb0d722a5ac87f01573fb  android/x86_64/libsqliteX.so
```

## Updating

1. Download the release archives from the upstream GitHub releases page and
   verify them against `SHA256SUMS`.
2. Replace the DLL and the per-ABI `.so` files.
3. Update the hashes above and in `docs/SQLITE3MC_E0_DECISION.md`.
4. Run `dart run tool/sqlite3mc_e0.dart` on Windows and
   `flutter test integration_test/sqlite3mc_e0_test.dart -d <device>` on Android.
5. Never change the cipher profile (`locus-sqlcipher4-raw-v1`) without a tested
   migration or rekey operation.

The Android library keeps its upstream name `libsqliteX.so`. It is loaded
explicitly by `lib/core/security/sqlite3mc.dart` and does not replace the stock
`libsqlite3.so` used when encryption is disabled.
