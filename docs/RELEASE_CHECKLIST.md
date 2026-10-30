# Locus release checklist

## Before release
- [ ] `flutter pub get`
- [ ] `dart run build_runner build --delete-conflicting-outputs`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build windows --release`
- [ ] Launch the release build on a clean Windows profile.
- [ ] Verify database migration and backup/restore.
- [ ] Verify notifications after restarting the app.
- [ ] Verify tray hide/show and real exit.
- [ ] Verify keyboard navigation (`Ctrl+K`, `Ctrl+1`…`Ctrl+9`).
- [ ] Verify recurring events across a month boundary.
- [ ] Verify delete + Undo for events/tasks.
- [ ] Android MVP on a real phone:
  - [ ] A recurring event created on the desktop appears in Today on the day of a repeat (not only its first day).
  - [ ] A task can be deleted from the Tasks tab and restored from the Undo snackbar.
  - [ ] An event's title, date and time can be edited from Today; deleting it asks for confirmation (and warns for a repeating series).
  - [ ] Type in the diary and wait a second: the entry is saved without pressing **Save now**, and the status changes to **Saved at**. Background the app while typing and reopen it: the text is still there.
- [ ] Android reminders (real phone; the Kotlin side has no automated tests):
  - [ ] Capture an event 3 minutes ahead with a 1-minute reminder; close the app; the notification appears on time, and tapping it opens Locus.
  - [ ] Deny notifications: the Sync tab shows the warning, and **Allow notifications** / **Open settings** work. Allow them and confirm the warning disappears when you return.
  - [ ] Android 13+: with *Alarms & reminders* off, the Sync tab offers **Allow exact timing**; reminders still appear (possibly late) until it is on.
  - [ ] Create an event with a reminder on the desktop, sync, switch the phone to airplane mode, close the app: the reminder still appears.
  - [ ] Set a reminder 10 minutes ahead, reboot the phone, and confirm it still appears (do not open Locus after the reboot).
  - [ ] Switch **Event reminders** off in the Sync tab: no notification appears; switch it on again: they return.
  - [ ] Delete or move the event on the desktop, sync: the old reminder does not appear.
- [ ] Confirm version/build number in `pubspec.yaml`.
- [ ] Create a manual recovery backup before distributing.

## Distribution
1. Archive the generated `build/windows/x64/runner/Release` directory.
2. Include the application executable and its bundled assets/DLLs.
3. Test the archive on a machine without the Flutter SDK.
4. Keep the release archive and release notes with the Git tag.
5. For a source hand-out, use `git archive` so `.gitattributes` keeps SDK paths and build output out (see `docs/DISTRIBUTION.md`).
6. Sign the installer and executable when a signing certificate is available, and publish SHA-256 checksums next to the download (see `docs/DISTRIBUTION.md`).

## Recovery
If a release exposes a data issue:
1. Ask the user to export/create a recovery backup.
2. Preserve the backup before attempting repair.
3. Reproduce against a copy of the SQLite database.
4. Ship a migration/fix rather than editing user data manually.
