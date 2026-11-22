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

### Presence layer (Phase 5)

- Native taskbar badge: `setBadge` draws a 16×16 overlay icon with the open
  due/overdue task count and clears it at zero. It uses `ITaskbarList3` and the
  top-level runner window handle.
- Jump list: `updateJumpList` writes Start-menu-style links under
  `%LOCALAPPDATA%\Locus\JumpList` and commits them with
  `ICustomDestinationList`. Entries are Open Locus, Quick capture, New task and
  Mini Today; the last three launch `locus://` URIs so single-instance
  forwarding works.
- Mini Today: the tray and jump list switch the main window into a compact
  380×520, always-on-top, non-resizable view. It shows today’s next events and
  due tasks, with Add, Open full planner and normal app-lock behaviour. Leaving
  the mode restores the previous bounds without saving the compact geometry.
- Pin guidance: a dismissible Today card and a Settings action open Windows’
  apps list and explain the supported right-click → Pin to taskbar/Start route.
  Windows has no supported programmatic pin verb.

## Still required for the full 1.7

- Verify toast delivery with the installed AUMID shortcut across sleep,
  hibernate and reboot, including the signed installer.
- Record installed-artifact evidence for notification taps, Snooze, badge
  refresh after sync/completion, jump-list activation and Mini Today restore.


Tests: `test/windows_reminder_test.dart` covers stable ids, reconcile,
hide-titles, badge counts, snooze and missed rows;
`test/windows_presence_test.dart` covers the badge/jump-list channel contract.
The Windows release build and bundle gate pass.

## Occurrence ownership (1.6.1)

Every reminder slot now uses the same canonical occurrence identity
(`kind:entity@occurrenceStartMs`) in the planner, platform state, inbox,
snooze stores, OS schedule, cancellation and fallback timer. The stable Windows
id is derived from that identity.

Startup calls one serialized reconciliation that drains coalesced passes and
returns the confirmed OS ids before repositories arm fallbacks. Repositories
only arm non-confirmed occurrences and cancel by occurrence, not by entity
alone. `listScheduled` distinguishes an enumeration failure (`null`) from an
empty schedule, so a native error cannot create duplicate fallbacks.
`platform_reminder_state` records the owner (`os`/`app`/`unknown`) and a
degraded flag; Today shows "needs app running" for app-owned rows. Confirmed
toasts are acknowledged before the missed-reminder sweep, and the toast XML
includes a `Snooze 10 min` protocol action.
