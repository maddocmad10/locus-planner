# Phase 3 — Android MVP

This patch adds a touch-first Android shell over the existing Drift database, with Today/agenda, tasks, diary, quick capture, pairing, and manual sync. The desktop shell remains the default on Windows.

## Generate Android project files

The supplied project zip does not contain an `android/` directory. From the project root, with Flutter 3.44 or later installed, run:

```sh
flutter create --platforms=android --org com.example.locusplanner .
```

Keep the existing `lib/` and `pubspec.yaml` files when prompted. In `android/app/src/main/AndroidManifest.xml`, add this permission directly under the `<manifest>` element and outside `<application>`:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

Because the current desktop sync API is plain HTTP, add `android:usesCleartextTraffic="true"` to the `<application ...>` element in that same manifest. This is required on modern Android for the LAN HTTP connection; it also means the app must only be used on a trusted private network until the protocol is upgraded to HTTPS.

Then run:

```sh
flutter pub get
dart format lib/main.dart lib/core/services/lan_sync_server.dart lib/features/mobile
flutter analyze
flutter test
flutter build apk --debug
```

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
- Sync is manual, not background or automatic. Conflict resolution is last-applied-write-wins for rows; diary entries also have a unique date, so an incoming entry replaces another row for the same date.
- The existing LAN protocol uses plain HTTP. Use only a trusted private Wi-Fi network; do not use public/guest Wi-Fi or expose port 43821 to the internet. **Forget pairing on this phone** clears local credentials only; revoke the device in desktop Settings to invalidate its server-side token.
- The zip has no generated Android Gradle project and this environment does not have Flutter/Dart installed, so the patch has not been compiled or test-run here. Run the commands above and resolve any environment-specific Android/Gradle setup issues before release.
