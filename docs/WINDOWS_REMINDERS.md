# Windows scheduled reminders (1.7 Phase 1–2)

## Implemented

### Native toast bridge

`windows/runner/windows_toast_channel.cpp` is a C++/WinRT library built with
exceptions enabled (`_HAS_EXCEPTIONS=1`), separate from the Flutter runner's
`_HAS_EXCEPTIONS=0` settings. The runner registers `locus/windows_toasts`.

Methods:

- `schedule(list)` — removes an existing toast with the same 16-character id,
  then adds a `ScheduledToastNotification`.
- `cancelAllExcept(ids)` — removes scheduled toasts not in the desired set.
- `listScheduled()` — returns scheduled ids.
- `setBadge(count)` — currently returns `false`; taskbar badge is Phase 5.

Toasts use `ToastGeneric` XML, `activationType="protocol"`, and launch URIs
such as `locus://open?kind=task&id=...`.

`fireAtEpochMs` is signed Unix milliseconds. The bridge converts with
`winrt::clock::from_time_t(0) + milliseconds{unixMs}` and rejects instants
outside 1970-01-01..9999-12-31 before conversion.

### Activation and snooze

- `--background` starts hidden in the tray.
- A cold-start or single-instance `locus://open?kind=task|event&id=...` is held
  while the app is locked, then opens the exact editor.
- `locus://snooze?id=...&min=...` reschedules the same reminder id and records
  `snoozed_from`; a later refresh keeps the snooze.

### App identity

- `SetCurrentProcessExplicitAppUserModelID("LocusPlanner.Desktop")`.
- Installer `AppUserModelID` on the Start-menu and desktop shortcuts.
- `locus://` protocol registered under `Software\Classes\locus`.

### Schema v24

`platform_reminder_state` is device-local, unsynced and excluded from backups.
`PlatformReminderStore` upserts desired reminders, removes stale rows, lists
missed rows and marks them delivered.

### Reconcile service

`WindowsReminderService`:

- plans the next 30 days, capped at 1,000 reminders;
- assigns `base32(SHA256(kind|entity|fireAt))[0..16]` ids;
- reconciles the desired set against the OS-scheduled set;
- watches events and to-do rows, replans at local midnight, on edits and on
  sync-applied rows;
- honors `notifications.hide_titles`;
- sets `NotificationService.platformSchedulerActive` so the in-app timer does
  not double-show a Windows toast;
- exposes `takeMissed()` for missed-reminder recovery.

`ReminderPlanner`/`PlannedReminder` moved to `lib/core/reminders/` so Windows
and mobile share them.

## Still required for the full 1.7

- Taskbar badge, jump list, Mini Today, pin guidance (native presence layer).
- Verify toast delivery with the installed AUMID shortcut across sleep,
  hibernate and reboot, including the signed installer.
- Record installed-artifact evidence for notification taps and Snooze.

Tests: `test/windows_reminder_test.dart` covers stable ids, reconcile,
hide-titles and missed rows. The Windows release build and bundle gate pass.
