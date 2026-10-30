# Dependency upgrades

Locus deliberately pins the versions in `pubspec.yaml` to a set that is known to
work together on Windows and Android. Several of them are now more than one major
version behind; this page records the decision, the reason, and a staged plan so
the upgrades are not forgotten or attempted blindly.

## Current state

| Package | Pin | Notes |
| --- | --- | --- |
| `flutter_riverpod` | `^2.6.1` | Riverpod 3 changes provider lifecycle and code generation. |
| `fl_chart` | `^0.68.0` | 1.x changes chart configuration and axis APIs. |
| `window_manager` | `^0.3.8` | 0.4.x changes window options and is paired with `screen_retriever`. |
| `mobile_scanner` | `^6.0.0` | 7.x changes the camera/controller API; the pairing scanner is small but must be retested on a phone. |
| `flutter_secure_storage` | `^9.2.4` | 10.x changes platform storage options; this package holds the desktop TLS private key and the Android bearer token. |
| `sqlite3_flutter_libs` | `^0.5.24` | 0.5.x is marked end-of-life on pub (`0.6.0+eol`). |
| `sqlite3` / `drift` | `^2.x` / `^2.20.0` | Drift 2.20 expects SQLite 2.x. The native bundling package cannot be upgraded on its own without checking ABI compatibility. |

## Decision for this release

No major dependency migration is part of the Android MVP/polish patch. These
upgrades touch persistence, windowing, chart rendering, camera permissions and
provider lifetimes; each needs its own change set, a device test pass and a
rollback path. Bundling them here would make a sync/UI fix patch much harder to
review and to revert. The pins stay as they are for now.

`sqlite3_flutter_libs` is the one EOL warning to watch. The correct fix is to
upgrade `drift`, `sqlite3` and `sqlite3_flutter_libs` together, not only the
bundling package, because the bundled native library must match the Dart FFI
bindings used by Drift. Until then, the existing pinned combination remains the
tested path on Windows and Android.

## Staged plan

1. **Low risk, same major:** `package_info_plus`, `intl`, `uuid`, `crypto`,
   `path`, `path_provider`, `shared_preferences`. Upgrade, run the full suite,
   build Windows and Android.
2. **`flutter_secure_storage` 9 → 10:** migrate the TLS key and bearer token,
   verify Windows protected storage and Android Keystore, and confirm that a
   failed migration still leaves sync usable (the key stays in the database as
   the existing fallback).
3. **`mobile_scanner` 6 → 7:** rework `pair_scanner_page.dart`, then test the
   permission-denied, no-camera and manual-entry paths on a real phone.
4. **`window_manager` 0.3 → 0.4 + matching `screen_retriever`:** recheck window
   bounds, minimize-to-tray, reveal-from-second-instance and the startup error
   screen.
5. **`fl_chart` 0.68 → 1.x:** rewrite the Insights charts, then compare each
   chart against the current screenshots/data.
6. **`flutter_riverpod` 2 → 3:** migrate provider overrides and lifecycle
   behaviour, then run the provider/refresh/widget tests.
7. **SQLite:** upgrade `drift`, `drift_dev`, `sqlite3` and
   `sqlite3_flutter_libs` together; regenerate Drift code, test every migration
   from an old database backup, and verify the Windows `sqlite3.dll` packaging.

## Per-upgrade checklist

```powershell
git switch -c chore/upgrade-<package>
flutter pub outdated
flutter pub upgrade <package>
dart run build_runner build --delete-conflicting-outputs   # if schema/codegen changed
dart format lib test
flutter analyze --fatal-infos
flutter test
flutter build windows --release
flutter build apk --release
```

Also verify on a real device: pairing, sync, reminders, tray/window behaviour and
diary import. Update this page and `CHANGELOG.md` in the same change.

## Why not `pub upgrade --major-versions`?

That command can rewrite the lockfile to a combination that no release has been
tested with. Because Locus stores user data locally and ships a custom SQLite
build, an untested major upgrade is a data-risk change, not a routine chore. Do
one package at a time and keep the previous tag available for rollback.
