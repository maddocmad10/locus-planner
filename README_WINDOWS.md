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

To create installer, use msix:
flutter pub add msix
dart run msix:create

## 5. Later - Add Android (same code)
flutter config --enable-android
flutter create --platforms=android .
# (Android is not set up yet; this is a placeholder for later.)
flutter run -d android
