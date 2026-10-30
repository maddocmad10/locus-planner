# Locus Planner

**Locus** is a local-first productivity planner built with Flutter for Windows, with an Android companion app.
It helps you manage events, projects, tasks, habits, focus sessions, and your daily diary — all offline and private. Windows and Android can sync over your own Wi-Fi.

---

## Features

### 📅 Events
- Calendar view with event markers
- Add, edit, and delete events
- Repeating events (daily, weekdays, weekly, every two weeks, monthly, yearly)
- Categories (General, Work, Personal, Health)
- Optional reminders. On Windows they work only while Locus is running; on Android they also appear when the app is closed. A reminder more than 15 minutes late is skipped
- Export events as `.ics` (compatible with Outlook, Google Calendar, Apple Calendar)

### 📁 Projects
- Create and manage projects
- Checklist items drive the completion percentage, against an editable target
- A separate progress journal for notes (it does not move the percentage)
- Visual progress bars and history charts
- Link focus sessions to projects (the link is recorded on the session, not as a fake percentage)

### ✅ To-do
- Personal to-do list, separate from a project's checklist
- Optional due dates
- Quick add, edit, and dialog support
- Mark complete / delete

### 🔥 Habits
- Create habits with custom icons
- Daily completion tracking
- Current streak + weekly target
- **12-week heatmap** (GitHub-style contribution graph)

### ⏱️ Focus Timer
- Circular progress timer
- Presets (25 / 50 / 90 min)
- Optional project linking
- Automatic session logging
- Sound notification after the session is saved
- Focus history + daily total

### 📖 Diary
- Daily journal entries
- Mood tracking
- Streak counter
- Autosaves while you type on Android, and saves explicitly on Windows

### 📊 Insights
- Live data-driven charts
- Focus time trends (last 14 days)
- Habit completion this week
- Mood trends
- Project progress overview

### 📱 Android companion
- Today agenda (including repeats of recurring events), tasks, diary, and quick capture
- Native event reminders that work while the app is closed
- Encrypted sync with the Windows app over a trusted private Wi-Fi network (LAN)

### ⚙️ Other Features
- Light / Dark / System theme
- System tray + minimize to tray
- Command Palette (`Ctrl + K`)
- Global quick capture (`Ctrl + Shift + L`) — event, to-do, or diary note even from the tray
- Full data export (JSON)
- Full data import (restore from backup)
- Completely offline & local-first

---

## Windows + Android sync

Both apps keep their own local SQLite database. Pairing uses a one-time code
(shown as a QR code in Windows **Settings → Device Sync (LAN)**) and pins the
desktop's self-signed certificate, so sync is encrypted and authenticated on
your LAN. Changes are exchanged when you tap **Sync now** on Android, and
automatically when the Android app is opened or brought back to the foreground.
There is no background sync while the phone app is closed, so open it once to
pick up desktop changes.

See [`docs/PHASE_3_ANDROID_MVP.md`](docs/PHASE_3_ANDROID_MVP.md) for pairing
steps, permissions, and limits, and [`docs/PHASE_2_LAN_SYNC.md`](docs/PHASE_2_LAN_SYNC.md)
for the protocol and conflict rules.

---

## Getting Started

### Prerequisites

- Flutter 3.44 or newer (see `environment:` in `pubspec.yaml`)
- Windows desktop enabled and the Visual Studio "Desktop development with C++" workload
- Optional, for the Android app: Android SDK/Studio and a phone or emulator

```bash
flutter config --enable-windows-desktop
flutter doctor -v
```

### Run

```bash
flutter pub get
flutter run -d windows
```

For the Android companion, enable Android and run on a connected device:

```bash
flutter config --enable-android
flutter run -d <device-id>
```

The generated Drift code (`lib/core/db/app_database.g.dart`) is intentionally not
committed. If you change a table in `app_database.dart`, regenerate it with:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Test

```bash
flutter analyze
flutter test
```

The tests use an in-memory SQLite database. On Windows, `sqlite3.dll` must be on
your `PATH` for `flutter test` to find it.

### Build a release

Windows:

```bash
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/locus_planner.exe` plus its `data` folder.
See `README_WINDOWS.md` for the Inno Setup installer, and
[`docs/DISTRIBUTION.md`](docs/DISTRIBUTION.md) for code signing, SmartScreen and
update guidance.

Android:

```bash
flutter build apk --release
```

Release signing is configured in `android/key.properties` (or `LOCUS_*`
environment variables); see [`docs/ANDROID_RELEASE.md`](docs/ANDROID_RELEASE.md).

## Your data

Locus stores everything locally in a SQLite database in the application-support
folder (`%APPDATA%\...\locus_planner.db`). Older versions kept it in
`Documents`; on first start the file is copied across and the old one is left in
place as a backup. Use **Settings → Export** for a JSON backup and **Import** to
restore it.
