# Locus release checklist

## Before release
- [ ] `flutter pub get`
- [ ] `dart tool/check_encoding.dart`
- [ ] `dart run build_runner build --delete-conflicting-outputs`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] `flutter build windows --release --dart-define=LOCUS_DB_ENCRYPTION=true --obfuscate --split-debug-info=build/symbols/windows`
- [ ] `flutter build appbundle --release --dart-define=LOCUS_DB_ENCRYPTION=true --obfuscate --split-debug-info=build/symbols/android`
- [ ] `dart tool/verify_release_bundle.dart --platform=windows --path=build/windows/x64/runner/Release`
- [ ] `dart tool/verify_release_bundle.dart --platform=android --path=build/app/outputs/flutter-apk/app-release.apk`
- [ ] `dart tool/verify_release_bundle.dart --platform=android --path=build/app/outputs/bundle/release/app-release.aab`
- [ ] `dart tool/verify_release_bundle.dart --database=<fresh-profile-locus_planner.db>`
- [ ] Archive `build/symbols/windows` and `build/symbols/android` privately with the release.
- [ ] Fresh install creates an encrypted database; an existing plaintext database still opens unchanged.
- [ ] Import a recovery-key JSON from the startup error screen, confirm the key rotates and the app opens after restart.
- [ ] On the minified Android release APK, test reminders, boot re-arm, the widget, QR scan, sync and attachments.
- [ ] Export diagnostics after seeding sentinel words in a title, note, diary entry and attachment name; confirm the ZIP contains none of them.
- [ ] With live encryption enabled, create a recovery key, verify the recovery file opens with its passphrase, and confirm the Settings card warns about Windows profile loss.
- [ ] Launch the release build on a clean Windows profile.
- [ ] Verify database migration and backup/restore.
- [ ] Verify notifications after restarting the app.
- [ ] Verify tray hide/show and real exit.
- [ ] Verify keyboard navigation (`Ctrl+K`, `Ctrl+1`…`Ctrl+9`, `Ctrl+Alt+C`, `Ctrl+Alt+P`).
- [ ] Verify recurring events across a month boundary.
- [ ] Upgrade a schema-16 database to 17: all pre-existing rows remain, `todo_items.estimated_minutes` is added, the five planning tables exist, and sync triggers are rebuilt. Confirm old-peer sync still ignores the new entity types.
- [ ] Calendar planning: open Calendar from the rail, `Ctrl+Alt+C` and the command palette. Create, move, resize and delete a task block; Undo restores it. Confirm a block does not change the task's start/due date or My Day membership.
- [ ] Capacity: set working hours and a break, add a block and a My Day estimate for a task without a block. Confirm planned effort counts each task once and overcommitment is advisory (nothing is blocked or rescheduled).
- [ ] Saved views: create two views, confirm duplicate names are rejected per scope, pin/reorder one, run it, and confirm invalid/newer definitions are reported rather than executed.
- [ ] Backup: export v3, restore into a fresh database, and confirm blocks, saved views, profile, working hours/breaks and `estimated_minutes` survive. Restore an older backup without those sections.
- [ ] LAN sync: create a block and a saved view on the desktop, sync to the phone and back; delete the parent to-do on the desktop and confirm the phone loses the cascaded block.
- [ ] Verify delete + Undo for events/tasks.
- [ ] Upgrade a schema-17 database to 18 and 19: task ids and `completed` are preserved, status is backfilled from completion, every project has five status rows, and migration 19 rotates the sync epoch.
- [ ] Project Kanban: switch between List and Kanban, confirm the same tasks/completion, drag a card between two columns and confirm the status and `completed` flag agree. Rename/recolour/reorder a status and confirm it survives restart.
- [ ] Milestones: create, edit, complete and delete a milestone; Undo restores a deleted one; delete and Undo the whole project.
- [ ] Dependencies: add a finish-to-start blocker; confirm a self-edge, duplicate edge, cross-project edge and cycle are rejected with a clear message. Confirm blockers are advisory and no dates move automatically.
- [ ] Timeline: switch day/week/month zoom; confirm scheduled tasks, milestones, overdue highlighting, dependency connectors and the Unscheduled lane, and that source dates do not change.
- [ ] Phase 3 backup/sync: export/restore a project with statuses, a milestone and a dependency; restore an older backup without those sections; sync the same project to the phone and confirm order, then delete the task/project and confirm cascaded tombstones. Confirm an old peer task payload becomes `todo`/`done` from `completed`.
- [ ] Upgrade schema 19 to 20: `todo_items.is_important`/`urgency_override` and `planning_preferences.urgency_window_days` exist with neutral defaults; all existing rows survive.
- [ ] Upgrade schema 21 to 22: `attachments.alt_text` exists and is `NULL` for existing rows; edit alt text on an image, sync it, export/restore a backup and an `.locusarchive`, and confirm the text survives. An old peer still syncs the same attachment without the column.
- [ ] Attachments, Windows: paste an image with `Ctrl+V` and the **Paste image** button; confirm both import through the normal checks. Paste text only and confirm a clear "no image" message. Edit alt text and confirm it is used as the tile's accessible label.
- [ ] Attachments, Android: take a photo, paste a clipboard image and share a file/image to Locus from another app. Confirm each creates or extends the expected task, the bytes survive a restart, and a shared executable is refused.
- [ ] Mobile search: search a task title, a note, an event and an attachment display name; confirm each result opens the owning task or event.
- [ ] Automatic backups: leave the new attachment switch off and confirm the daily backup stays metadata-only; turn it on with a passphrase and confirm an encrypted `.locusarchive` is written and pruned to seven.
- [ ] Planning suggestions: open Planning from the rail, `Ctrl+Alt+P` and the command palette. Confirm each suggestion explains its reasons and proposed before/after, and nothing changes until **Apply**. Apply one and use Undo to restore it.
- [ ] Carry-forward: verify today/tomorrow/Choose date/Remove choices, and that moving a task never creates a duplicate in the same day plan.
- [ ] Eisenhower: toggle importance and urgency overrides; confirm the quadrant and reason update, and change the urgency window.
- [ ] Weekly review: compare displayed counts/denominators with raw tasks, completions, focus sessions, habit logs and milestones for the labelled range.
- [ ] Privacy: confirm Planning works with networking disabled and no external request is made.
- [ ] Quick capture: `standup tomorrow 9am`, `review every Monday`, `pay rent every month`, `write proposal #work ! tomorrow`; confirm the preview and saved date/repeat/priority/tags.
- [ ] First run on an empty profile: local-first card appears; sample data populates My Day, tasks and one event; Start blank hides the card; ICS import opens the existing Settings flow.
- [ ] Release encryption configuration (when enabled): build with `--dart-define=LOCUS_DB_ENCRYPTION=true`; verify the Windows bundle contains `sqlite3mc_x64.dll` and the APK contains `lib/<abi>/libsqliteX.so`; confirm a plaintext database is not converted unless `--dart-define=LOCUS_DB_MIGRATION=true` is also set.
- [ ] Recovery package: create a `.locusrecovery` package with attachments, confirm it is reported as verified, and verify it again from the card. Try a wrong passphrase and a truncated copy: both must fail without changing the live database.
- [ ] Raw recovery: stage a package on a clean profile, restart, and confirm the restored database opens with its original database ID/key ID and the attachment files decrypt. Confirm the previous files are in quarantine.
- [ ] Logical restore: import a JSON and an encrypted `.locusbackup` into a fresh database; confirm a new database ID/key/epoch, cleared outbox and paired clients, stored provenance, and `sync.rebase_required`. Re-pair the phone and confirm the flag clears.
- [ ] Start fresh: request it, restart, confirm the old database/metadata/journals/attachments are quarantined, the old key record still exists, and the new database has a new ID and generation. Review old artifacts and delete only after confirmation.
- [ ] Plaintext cleanup: open **Review plaintext artifacts** after an encrypted install; confirm the legacy Documents copy and any `.plaintext.bak` files are listed with size/date. Delete one after confirming, and confirm the live database cannot be selected.
- [ ] Recovery passphrase: create a managed recovery key, change its passphrase, confirm the old envelope is renamed `retired-` and the new one opens with the new passphrase. Rotate the DEK and confirm all managed envelopes are retired.
- [ ] Physical Android check: create and stage a recovery package, and confirm the next launch applies it with the staged attachment key.
- [ ] Windows tagged release: confirm `signtool verify /pa` passes for `locus_planner.exe` and the installer, or record that the build is unsigned.
- [ ] Android widget: add **Today** to the home screen, edit a local event/task, and confirm the widget refreshes without network access.
- [ ] Android recurrence: edit a recurring event (series repeat and Skip this occurrence), sync both ways, and confirm the desktop shows the same rule/exceptions.
- [ ] Android exact timing: toggle **Exact reminder timing** in Sync; confirm approximate fallback still delivers reminders and the explanation matches the toggle state.
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
- [ ] Manual security tests:
  - [ ] Type a diary entry, minimize/restore (and lock/unlock): the text is still there.
  - [ ] Hide to tray with a dialog open, restore: the PIN screen is above the dialog.
  - [ ] Android 12+: the recents card is blank and screenshots are blocked while the lock is on.
  - [ ] Open a file picker and the QR scanner, return: no PIN prompt appears.
  - [ ] Five wrong PINs, wait, kill and relaunch: the wait persists. Move the clock backwards: the wait does not shorten.
  - [ ] Tick the same habit on both devices offline, sync twice: both keep one row.
  - [ ] Upgrade the desktop with a previously paired phone: existing habits appear after one sync.
  - [ ] Plan the same day with different tasks on both devices offline, then sync twice: the plan holds all tasks.
  - [ ] Complete a recurring to-do from My Day: it shows Done today and due on its next date elsewhere.
  - [ ] Import Google, Outlook and Apple `.ics` files; check the preview report and the times. Re-import a Locus export: event count and ids do not change.
  - [ ] With automatic encryption on, an automatic/recovery backup is `.locusbackup` and contains no diary text. With the credential store unavailable, the backup fails and writes no file.
  - [ ] Restore a diary backup over a newer local entry: choose Keep both and confirm both texts survive; a recovery backup exists.
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
