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
- The same Drift schema and database migration code are used on Android; data is stored in the app's application-support directory.
- The Android bearer token is stored using `flutter_secure_storage`; host and sync cursors are stored in `SharedPreferences`.
- Sync is manual, not background or automatic. Conflicts are resolved per row by version (`updated_at`), newest edit wins, with deletes as versioned tombstones; see docs/PHASE_2_LAN_SYNC.md. Diary entries also have a unique date, so when two entries claim one date the one with the lowest ID is kept on both devices and the other entry's text is merged into it.
- The LAN protocol uses HTTPS with a self-signed desktop certificate that the phone pins when it pairs. Use it only on a trusted private Wi-Fi network anyway; do not use public/guest Wi-Fi or expose port 43821 to the internet. A phone paired before this change must pair again. **Forget pairing on this phone** clears local credentials only; revoke the device in desktop Settings to invalidate its server-side token.
- `test/mobile_sync_client_test.dart` runs the real Android client against a real desktop server over loopback, covering pairing, first sync, two-way edits, conflicts, pruning and resync.
