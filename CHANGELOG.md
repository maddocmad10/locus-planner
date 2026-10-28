# Changelog

All notable changes to Locus Planner are recorded here.

## [Unreleased]

- Android: event reminders. An event with a reminder now notifies you on the phone before it starts, even when Locus is closed, whether you created it on the phone or it arrived from the desktop by sync. The quick-capture sheet can set the event's start time and a reminder (at start, 5, 10, 15, 30 or 60 minutes before), Today marks events that have one, and the Sync tab has an Event reminders switch with shortcuts to Android's notification and exact-alarm settings. Reminders use native Android alarms (no new Flutter dependency), are re-armed after a reboot or app update, and follow the desktop's rule that a reminder more than 15 minutes late is skipped. The phone plans the next 30 days of reminders (including repeats of recurring events) each time events change or the app is opened. The manifest adds `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` and `RECEIVE_BOOT_COMPLETED`.
- Sync reliability: changes to the list of paired phones (a phone acknowledging, a pairing, a revoke) now run one at a time on the desktop. Before, two overlapping changes could undo each other, so a freshly paired phone could vanish or a revoked one could reappear.
- Security: the desktop's TLS private key is now kept in the operating system's protected storage (flutter_secure_storage) instead of in the database file. A key an earlier version left in the database is moved there the first time sync starts, so paired phones stay paired and the fingerprint does not change. If protected storage is unavailable the key stays in the database so sync still works. The desktop also no longer sends the cause of an internal error to the network.
- Android: the phone now syncs by itself when the app is opened or returns to the foreground (at most once a minute; failures are silent, and the Sync tab still reports them when you sync by hand). If the desktop does not answer, for example after the router gave it a new address, the phone asks the local network for the desktop with the certificate it paired with, saves the new address and retries. This uses a small UDP broadcast on port 43822 that only reveals the desktop's address and public fingerprint; the connection itself is still pinned to the certificate and needs the bearer token.
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
