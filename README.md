# Locus Planner

**Locus** is a local-first productivity planner built with Flutter for Windows.  
It helps you manage events, projects, tasks, habits, focus sessions, and your daily diary — all offline and private.

---

## Features

### 📅 Events
- Calendar view with event markers
- Add, edit, and delete events
- Categories (General, Work, Personal, Health)
- Optional reminders
- Export events as `.ics` (compatible with Outlook, Google Calendar, Apple Calendar)

### 📁 Projects
- Create and manage projects
- Track progress with tasks and progress logs
- Visual progress bars and history charts
- Link focus sessions to projects

### ✅ Tasks
- Global to-do list
- Optional due dates
- Quick add + dialog support
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
- Sound notification on completion
- Focus history + daily total

### 📖 Diary
- Daily journal entries
- Mood tracking
- Streak counter

### 📊 Insights
- Live data-driven charts
- Focus time trends (last 14 days)
- Habit completion this week
- Mood trends
- Project progress overview

### ⚙️ Other Features
- Light / Dark / System theme
- System tray + minimize to tray
- Command Palette (`Ctrl + K`)
- Full data export (JSON)
- Full data import (restore from backup)
- Completely offline & local-first

---

## Getting Started

### Prerequisites

- Flutter 3.44 or newer (see `environment:` in `pubspec.yaml`)
- Windows desktop enabled and the Visual Studio "Desktop development with C++" workload

```bash
flutter config --enable-windows-desktop
flutter doctor -v
```

### Run

```bash
flutter pub get
flutter run -d windows
```

The generated Drift code (`lib/core/db/app_database.g.dart`) is committed. If you
change a table in `app_database.dart`, regenerate it with:

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

```bash
flutter build windows --release
```

Output: `build/windows/x64/runner/Release/locus_planner.exe` plus its `data` folder.
See `README_WINDOWS.md` for installer (MSIX) notes.

## Your data

Locus stores everything locally in a SQLite database in the application-support
folder (`%APPDATA%\...\locus_planner.db`). Older versions kept it in
`Documents`; on first start the file is copied across and the old one is left in
place as a backup. Use **Settings → Export** for a JSON backup and **Import** to
restore it.
