# Changelog

All notable changes to Locus Planner are recorded here.

## [Unreleased]

- Global quick-capture hotkey (Ctrl+Shift+L) opens a lightweight dialog for a new event, to-do, or diary note, even when Locus is minimized to the tray. Can be disabled in Settings.

## [1.3.0] - 2026-10-21

- Checklist completion is the only project percentage. Focus sessions no longer write a fake progress value, and the progress journal is labeled as notes. The checklist target is editable and used for completion and overdue.
- A focus session that fails to save stays on screen with the error and a retry. The completion alert plays only after the row is saved.
- Settings and the event dialog state that reminders require Locus to be running and that a reminder more than 15 minutes late is skipped.
- The habit heatmap window uses calendar-day arithmetic instead of a 24-hour duration.
- Theme and notification preferences are stored in the database, included in backups, and reapplied after import. Backup JSON records the app version.
- Personal to-dos can be edited. The rail label is To-do so it stays distinct from a project checklist.
- Recovery backup failures include the underlying error instead of a generic message.
- Hardened single-instance tests for cross-platform CI.
- Added SQLite pre-migration snapshots and startup integrity validation.
- Centralized wall-clock reads behind `AppClock` for deterministic tests.
- Added tagged Windows release packaging and executable smoke checks.
