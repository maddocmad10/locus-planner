# Locus Windows - Setup Guide

## 1. Enable Windows Desktop
flutter config --enable-windows-desktop
flutter doctor -v (ensure Windows toolchain green)

## 2. Install
flutter pub get
dart run build_runner build --delete-conflicting-outputs

## 3. Run on Windows
flutter run -d windows

## 4. Build Release .exe
flutter build windows --release
Output: build/windows/x64/runner/Release/locus_planner.exe + data folder

For end-user distribution, use the tagged Windows Release workflow. It builds a ZIP and an Inno Setup installer, runs a process-level smoke test, and publishes SHA-256 checksums. Do not run `flutter pub add msix` on a consumer machine; installer configuration is maintained in `installer/LocusPlanner.iss`.

To build the installer locally, first build the Windows release and stage the complete `build/windows/x64/runner/Release` directory into `dist/LocusPlanner`, then compile `installer/LocusPlanner.iss` with Inno Setup 6. Set `LOCUS_VERSION` to the version you are packaging.

## 5. Later - Add Android (same code)
flutter config --enable-android
flutter create --platforms=android .
# (Android is not set up yet; this is a placeholder for later.)
flutter run -d android
