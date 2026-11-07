# Changelog

All notable changes to Locus Planner are recorded here.

## [1.5.0] - unreleased

- Rich notes: to-dos gain `notes_format` and events gain
  `description_format` (schema v21). Existing rows stay `plain`; `md1` adds a
  small safe Markdown subset rendered in an Edit/Preview `NotesField` on Windows
  and Android. Raw HTML is never interpreted.
- Local attachments: file and image attachments on to-dos and events, stored
  encrypted on this device only. Metadata syncs through the existing outbox and
  logical backup; blob bytes do not. Add, view, delete and Undo work on both
  platforms.
- Attachment storage: content-addressed AES-256-GCM blobs in 64 KiB chunks,
  HMAC file names for deduplication, a device-local key in the OS credential
  store, 7-day orphan grace, a 25 MB per-file cap, 20 per item, and a 1 GB soft
  quota warning.
- Attachment safety: names sanitized, MIME sniffed from magic bytes,
  executables/scripts refused, images decoded in a worker isolate with a
  50-megapixel cap, EXIF stripped by default and a 256 px thumbnail generated.
  Settings > Security > Attachments includes a Keep original images switch.
- Backup format 4 adds attachment metadata with `attachments_included: false`
  and never carries blob bytes. `attachment_blobs`, `attachments/` and the
  Android cloud/device-transfer copies are excluded.
- Schema v21 adds `attachments` and `attachment_blobs`, rebuilds the `events`
  and `todo_items` outbox triggers for the format columns, and adds attachment
  triggers plus `sync_row_versions` handling. Migration tests cover v16, v19 and
  v20 upgrades; every released step still upgrades in isolation.
- Blob sync over the paired LAN: desktop status advertises `attachments-v1` and
  `maxBlobBytes`; `missing`, streaming upload (hash checked before commit,
  25 MB cap, concurrent-upload limit, free-space probe) and Range downloads are
  authenticated by the existing bearer token. The phone uploads local files,
  pushes metadata, pulls metadata and downloads referenced blobs with resume,
  hash verification, thumbnail generation and a 500 MB LRU cache. Settings >
  Security > Attachments offers Auto, All and Manual download policies.
- Notes conflicts no longer silently drop one side: a losing note or event
  description is appended with the deterministic “merged from another device”
  divider, the merge is idempotent, and the merged text is republished.
- `.locusarchive` backups: a logical backup plus attachment bytes in a
  PBKDF2/AES-256-GCM chunked container. Restore verifies every hash, skips
  existing blobs, reports missing files and fails closed on a wrong passphrase,
  truncation or bit flip. Settings > Data Management can export and import it.
- Android opens attachments through a non-exported `FileProvider` limited to
  the per-session decrypted copies. Note links only open after a tap and only
  for `http`, `https`, `mailto` and `locus-att`; remote images are never loaded.
- UI: paperclip count badges on task/event rows, command-palette matches on
  attachment names, Windows drag-and-drop, phone placeholder tiles with
  Download/Keep, and plain-text projections of `md1` in list subtitles.
- ICS export says how many attachments were omitted; ICS import counts `ATTACH`
  and ignores it without fetching anything.
- Still deferred: clipboard-image paste (native plugin spike), an explicit
  alt-text column, and inline `locus-att://` rendering inside note previews.

## [1.4.0] - 2026-11-02

- My Day: a desktop daily-planning workspace and a matching phone section. Tasks are planned per local calendar day without duplicating the task row, with manual ordering, an optional estimate, workload totals, an end-of-day review, and a start-page setting.
- My Day sync: daily plans and plan items now sync with `sync_updated_at` as the version key. Plan/item ids are deterministic UUIDv5 values, and a same-day plan clash moves the losing plan's tasks to the winner instead of deleting them.
- To-do metadata: priority, tags, recurrence, notes, start date, due date, subtasks, project link and an exact reminder time, all included in backups and sync.
- Habit sync: habits and habit logs are writable on the phone. Same-day log clashes converge on the lowest id; schema migration 14 rotates the sync epoch so a previously paired phone receives pre-existing habits.
- App lock: the shell stays mounted under the PIN overlay, dialogs and routes cannot cover the lock, the app can wait before re-locking, Android hides the recents thumbnail, PIN attempts are throttled, and PBKDF2 runs off the UI thread.
- Encrypted backups: one `.locusbackup`/`.locusdiary` envelope with NFC-normalized passphrases, encrypted automatic backups, fail-closed credential-store handling, and a preview/choice diary restore (Keep mine, Replace, Keep both) that never silently loses local text.
- ICS import/export: quoted parameters, IANA and Windows timezones, UNTIL/COUNT, EXDATE, all-day events, modified occurrences, idempotent re-import, a preview dialog, and Undo. Export writes UNTIL, EXDATE and VALUE=DATE.
- Phone agenda: free previous/next day navigation with a date picker and Today button, an Upcoming list, quick capture on the viewed day, and past-day My Day editing rules. Habit toggles for future days are disabled; habits can be edited and deleted on the phone.
- Task reminders on Android: task `reminder_at` values now become native alarms, with a separate Task reminders switch, distinct alarm ids from events, and a tap that opens the Tasks tab. Late task reminders on the desktop go to the missed-reminders inbox with Mark done, Snooze and Dismiss.
- Recurring to-dos keep completion history (`todo_completions`). The task editor shows the count and recent completions; My Day shows "Done today"; undo removes the latest completion and restores the previous due date.
- Schema migrations 14 to 16 add the sync epoch rotation, event recurrence columns and completion history. Upgrade tests now use drift schema dumps for versions 9, 12, 13 and 16.
- Smaller hardening: shared secret-entry prompt with show/hide, reminder re-arming only for changed to-dos, My Day duplicate-day import protection, and generated-code notes in the README.

- Windows reminders are no longer lost when Locus is fully closed. On launch, the desktop compares reminder times with the last recorded session and lists anything that came due in between on Today, including repeats of recurring events. Missed reminders can be snoozed for 10 minutes or 1 hour, or dismissed; pending snoozes survive a restart. A reminder that becomes more than 15 minutes late while the app is running (for example after the laptop slept) is added to the same list instead of being silently skipped.
- Settings has a **Start Locus when Windows starts** switch. It registers the installed executable under the current user's `Run` key, so reminders and quick capture work after sign-in without needing administrator rights or a startup shortcut.
- Android: Today now expands recurring events, so a repeat appears on the day it happens instead of only on the day the series was created. Repeats are labelled and marked with a repeat icon.
- Android: tasks can be deleted from the Tasks tab, with Undo; events can have their title, date and time edited, or be deleted, from Today. For a repeating event the edit applies to the whole series and the dialog says so.
- Android: the diary autosaves while you type (debounced) and when the app goes to the background, with a status line instead of a mandatory **Save** step. Empty entries are not created just because the field was focused.
- Android: the global Flutter/PlatformDispatcher error handlers are installed before the Android startup branch, so Android runtime errors now reach `locus_error.log` as desktop errors already did.
- Build: the Android `namespace` is now `com.locusplanner.app`, matching `applicationId` and the Kotlin package. This is a source-only change; the installed app ID and user data are unchanged.
- Packaging: `android/build/reports/...` is no longer tracked, `android/.gitignore` covers Gradle/Kotlin output, and the new `.gitattributes` marks build output and `android/local.properties` as `export-ignore` so shared source archives stay clean.
- Docs: README and README_WINDOWS now describe the Android companion and LAN sync; PHASE_1 no longer asks for a patch that is already applied; PHASE_2 no longer says sync is manual or that Android has no reminders. New `docs/DEPENDENCIES.md` records the deliberately staged dependency upgrades (including `sqlite3_flutter_libs` EOL), and `docs/DISTRIBUTION.md` covers signing, SmartScreen and the manual update path.

- Sync reliability: the initial snapshot now resumes from an opaque `nextAfter` token that names the last row already sent, instead of from a positional offset. Deleting a row that was transferred earlier in the snapshot no longer shifts the remaining rows and silently skips one. Older phones keep using `offset`, and a newer phone falls back to it against an older desktop.
- Sync storage: the outbox is now pruned at desktop startup even when LAN sync has never been switched on, so it can no longer grow without bound or keep deleted diary text indefinitely. With no paired phone it is cleared; with paired phones it keeps their acknowledged rows and drops anything older than 60 days. An unpaired phone clears its own outbox at startup, while paired phones and phones that must pair again keep theirs.
- Android: the Sync tab no longer says sync uses plain HTTP. It now states that sync is encrypted with HTTPS and pins the desktop certificate.
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
