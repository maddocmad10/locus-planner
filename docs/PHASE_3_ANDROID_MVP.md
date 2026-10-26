# Phase 3 — Android MVP

This patch adds a touch-first Android shell over the existing Drift database, with Today/agenda, tasks, diary, quick capture, pairing, and manual sync. The desktop shell remains the default on Windows.

## Build the Android app

The Android project is in `android/`. The manifest already declares the `INTERNET` permission and, because the desktop sync API is plain HTTP, `android:usesCleartextTraffic="true"` on the `<application>` element (the attribute is ignored anywhere else). That means the app must only be used on a trusted private network until the protocol is upgraded to HTTPS.

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
2. Enable the LAN server and note the displayed pairing code and desktop Wi-Fi IPv4 address.
3. Install the Android debug APK on a phone connected to the same trusted private Wi-Fi network.
4. Open **Sync**, enter `http://DESKTOP-IP:43821` and the one-time pairing code, then tap **Pair with desktop**.
5. Tap **Sync now**. The first sync imports a snapshot of supported desktop data, then pushes local outbox changes and pulls desktop changes. Subsequent syncs use cursors.
6. Create or edit an event, task, or today's diary on either device, tap **Sync now** on Android, and check the other device.

## Scope and safety

- The Android UI intentionally includes only Today, Tasks, Diary, Quick capture, and Sync.
- The same Drift schema and database migration code are used on Android; data is stored in the app's application-support directory.
- The Android bearer token is stored using `flutter_secure_storage`; host and sync cursors are stored in `SharedPreferences`.
- Sync is manual, not background or automatic. Conflicts are resolved per row by version (`updated_at`), newest edit wins, with deletes as versioned tombstones; see docs/PHASE_2_LAN_SYNC.md. Diary entries also have a unique date, so when two entries claim one date the one with the lowest ID is kept on both devices.
- The existing LAN protocol uses plain HTTP. Use only a trusted private Wi-Fi network; do not use public/guest Wi-Fi or expose port 43821 to the internet. **Forget pairing on this phone** clears local credentials only; revoke the device in desktop Settings to invalidate its server-side token.
- `test/mobile_sync_client_test.dart` runs the real Android client against a real desktop server over loopback, covering pairing, first sync, two-way edits, conflicts, pruning and resync.
