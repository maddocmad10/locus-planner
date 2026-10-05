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
- [ ] Confirm version/build number in `pubspec.yaml`.
- [ ] Create a manual recovery backup before distributing.

## Distribution
1. Archive the generated `build/windows/x64/runner/Release` directory.
2. Include the application executable and its bundled assets/DLLs.
3. Test the archive on a machine without the Flutter SDK.
4. Keep the release archive and release notes with the Git tag.

## Recovery
If a release exposes a data issue:
1. Ask the user to export/create a recovery backup.
2. Preserve the backup before attempting repair.
3. Reproduce against a copy of the SQLite database.
4. Ship a migration/fix rather than editing user data manually.
