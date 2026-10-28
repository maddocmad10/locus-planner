# Phase 3 — Android MVP

This patch adds a touch-first Android shell over the existing Drift database, with Today/agenda, tasks, diary, quick capture, pairing, and manual sync. The desktop shell remains the default on Windows.

## Build the Android app

The Android project is in `android/`. The manifest declares the `INTERNET` permission, and an optional camera feature used only to scan the pairing QR code. Sync uses HTTPS with a pinned certificate, so no cleartext traffic is enabled.

```sh
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

For the app ID, release signing and CI, see [ANDROID_RELEASE.md](ANDROID_RELEASE.md).

## Pair and sync

1. On Windows, run the desktop app and open **Settings → Device Sync (LAN)**.
2. Enable the LAN server. The pairing code, QR code, desktop Wi-Fi IPv4 address and security fingerprint are displayed.
3. Install the Android debug APK on a phone connected to the same trusted private Wi-Fi network.
4. Open **Sync** and tap **Scan QR code on desktop**, then scan the QR code shown in desktop Settings. Without a camera, enter the desktop IP address and one-time code instead and tap **Pair with entered details**. The phone then shows the certificate fingerprint; pair only if it matches the one in desktop Settings.
5. Tap **Sync now**. The first sync imports a snapshot of supported desktop data, then pushes local outbox changes and pulls desktop changes. Subsequent syncs use cursors.
6. Create or edit an event, task, or today's diary on either device, tap **Sync now** on Android, and check the other device.

## Scope and safety

- The Android UI intentionally includes only Today, Tasks, Diary, Quick capture, and Sync.
- Event reminders: see "Event reminders" below.
- The same Drift schema and database migration code are used on Android; data is stored in the app's application-support directory.
- The Android bearer token is stored using `flutter_secure_storage`; host and sync cursors are stored in `SharedPreferences`.
- Sync runs when you tap **Sync now**, and also automatically (quietly, at most once a minute) when the app is opened or returns to the foreground; there is no background sync while the app is closed. If the desktop's address changed, the phone finds it again by a UDP broadcast and retries (see docs/PHASE_2_LAN_SYNC.md, "Finding the desktop again"). Conflicts are resolved per row by version (`updated_at`), newest edit wins, with deletes as versioned tombstones; see docs/PHASE_2_LAN_SYNC.md. Diary entries also have a unique date, so when two entries claim one date the one with the lowest ID is kept on both devices and the other entry's text is merged into it.
- The LAN protocol uses HTTPS with a self-signed desktop certificate that the phone pins when it pairs. Use it only on a trusted private Wi-Fi network anyway; do not use public/guest Wi-Fi or expose port 43821 to the internet. A phone paired before this change must pair again. **Forget pairing on this phone** clears local credentials only; revoke the device in desktop Settings to invalidate its server-side token.
- `test/mobile_sync_client_test.dart` runs the real Android client against a real desktop server over loopback, covering pairing, first sync, two-way edits, conflicts, pruning and resync.

## Event reminders

Events whose **Remind me** option is on notify the phone before they start, whether the event was captured on the phone (set the start time and a reminder in **Quick capture**) or arrived from the desktop by sync. Nothing needs to be running: reminders are native Android alarms.

How it works:

- `MobileReminderService` watches the events table. Whenever it changes (an edit, or rows applied by a sync) and whenever the app is opened or resumed, it asks `ReminderPlanner` for the reminders due in the next 30 days (at most 60 per event and 300 overall, earliest first) and sends the whole list to Android over the `locus_planner/reminders` channel. The planner reuses `Recurrence.nextRemindableStart`, so recurring events follow the same rules as on the desktop.
- `Reminders.kt` stores that list and keeps **one** alarm armed for the earliest entry. When it fires, every due reminder is shown and the alarm moves to the next. Because the list is stored, `BootReceiver` re-arms everything after a reboot or an app update without starting Flutter.
- Like the desktop, a reminder that is more than 15 minutes late (for example because the phone was off) is skipped, not shown.
- The switch **Sync → Event reminders** turns phone reminders off and on. It also shows when notifications are blocked or when Android only allows approximate alarms, with shortcuts to the right system screen.

Permissions:

- `POST_NOTIFICATIONS` (Android 13+) is requested right after the user saves an event with a reminder, or from the Sync tab.
- `SCHEDULE_EXACT_ALARM` gives on-time reminders. Android 12+ lets the user withdraw it, and on Android 13+ it is off until the user allows it under *Alarms & reminders*. Without it, reminders still appear but can be a few minutes late (Doze may delay them). If you publish on Google Play, check its policy on exact alarms; `USE_EXACT_ALARM` is the alternative for calendar apps.
- `RECEIVE_BOOT_COMPLETED` re-arms the next reminder after a reboot.

Limits to know about:

- The window is 30 days. A recurring event keeps getting reminders as long as the app is opened at least once a month.
- Phone-captured events are one-off; recurrence is set on the desktop. The Today list shows an event on the day it was stored, so a repeat of a recurring event notifies but does not appear in Today yet.
- Reminders are in the phone's local time zone at the moment the app last planned them. If the time zone changes, open the app once to re-plan.
- Reminder state (`locus_reminders` shared preferences) is excluded from Android backups.

Tests: `reminder_planner_test.dart` (what gets planned), `mobile_reminder_service_test.dart` (rebuilds on change, switch, failures, bursts), `reminder_platform_test.dart` (the channel), and widget tests in `widget_test.dart`. The Kotlin side is covered by the manual checks in `RELEASE_CHECKLIST.md`.
