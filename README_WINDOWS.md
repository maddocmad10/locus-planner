# Locus Windows — Setup Guide

## 1. Enable Windows desktop

```powershell
flutter config --enable-windows-desktop
flutter doctor -v   # ensure the Windows toolchain is green
```

## 2. Install dependencies

```powershell
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

## 3. Run on Windows

```powershell
flutter run -d windows
```

## 4. Build the release .exe

```powershell
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/locus_planner.exe` plus its `data` folder.

## 5. Build the installer

For end-user distribution, use the tagged Windows Release workflow. It builds a ZIP and an Inno Setup installer, runs a process-level smoke test, and publishes SHA-256 checksums. Do not run `flutter pub add msix` on a consumer machine; installer configuration is maintained in `installer/LocusPlanner.iss`.

To build the installer locally, first build the Windows release and stage the complete `build/windows/x64/runner/Release` directory into `dist/LocusPlanner`, then compile `installer/LocusPlanner.iss` with Inno Setup 6. Set `LOCUS_VERSION` to the version you are packaging.

## 6. Android companion app

The Android project is already part of this repository; no `flutter create` is needed.

```powershell
flutter config --enable-android
flutter run -d <device-id>          # development
flutter build apk --release         # signed APK, see docs/ANDROID_RELEASE.md
```

Pair it with the desktop from Locus **Settings → Device Sync (LAN)** and the phone's **Sync** tab. Both devices must be on the same trusted private Wi-Fi network. See [`docs/PHASE_3_ANDROID_MVP.md`](docs/PHASE_3_ANDROID_MVP.md) for pairing, reminders, permissions and limits.

## 7. Updates and SmartScreen

Locus has no automatic updater yet. To update, install a newer build over the existing one; the local database and settings are kept. The installer is currently unsigned, so Windows SmartScreen may warn on first launch. [`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) explains the signing options and a manual update check.

## 8. Sharing the source

Hand out source archives made with `git archive` (or GitHub's source download), not a ZIP of the working folder. `.gitattributes` marks build output, `android/local.properties` and similar machine-specific files as `export-ignore`, so they stay out of the archive.
