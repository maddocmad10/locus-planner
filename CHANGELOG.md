# Changelog

All notable changes to Locus Planner are recorded here.

## [Unreleased]

- Sync is now encrypted and authenticated. The desktop serves HTTPS with a self-signed certificate, and the phone pins that certificate's fingerprint when it pairs, so the bearer token and planner data can no longer be read or impersonated by other devices on the same Wi-Fi. Desktop Settings shows a pairing QR code (address, one-time code and fingerprint) and the phone scans it; without a camera the phone shows the fingerprint to compare. Cleartext HTTP is no longer enabled on Android. **Phones paired with an earlier version must pair again.**
- Pairing: a new pairing code can be generated without restarting sync, which also clears the failed-attempt lockout; codes are now eight characters; pairing again from a device that is already paired replaces its old entry instead of failing with "device already paired".
- Sync no longer discards diary text. When the desktop and the phone both wrote an entry for the same day, the two texts are merged (the second one after a "merged from another device" divider) instead of the entry with the higher ID being deleted. Both devices produce the same merged text, and merging again changes nothing.
- Android: cleartext HTTP is now enabled on `<application>` (it was on the activity, where it has no effect), the app is named Locus Planner with its own application ID, release signing uses a real keystore (key.properties or CI secrets), sync pairing state is excluded from backups, and the Gradle wrapper no longer points at a local Windows path. CI builds the release APK, and a new end-to-end test suite covers the Android sync client.
- Sync now refreshes the open screens on both desktop and phone, and re-arms or cancels desktop event reminders for events that arrive from the phone.
- Sync safety: the desktop now has a sync epoch and cursor checks, so a reset or replaced desktop makes the phone re-sync from a snapshot instead of silently missing changes. Acknowledged outbox rows are pruned on both desktop and phone.
- Sync conflict resolution: schema version 9 adds per-row versions so the newest edit wins on both devices, deletes are versioned tombstones, and concurrent edits no longer leave the desktop and phone with different data.
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
