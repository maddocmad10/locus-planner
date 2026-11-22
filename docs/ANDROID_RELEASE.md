# Android release

## App ID

`applicationId` in `android/app/build.gradle.kts` is the app's identity on a phone. It is currently `com.locusplanner.app`, and the Android `namespace` and Kotlin package match it. Change the ID to one you own (for example a reversed domain name) **before the first real install**: if it changes later, Android treats the app as a different one, so there is no in-place update and the data does not carry over. If you change the ID, change the `namespace` and the Kotlin package directory to match so the manifest and plugin registration stay obvious. CI fails if the ID is still a `com.example...` template value.

## Signing

Release builds are signed with a key from either:

1. `android/key.properties` (git-ignored; copy `android/key.properties.example`), or
2. the environment variables `LOCUS_KEYSTORE_FILE`, `LOCUS_KEYSTORE_PASSWORD`, `LOCUS_KEY_ALIAS`, `LOCUS_KEY_PASSWORD`.

If neither is present, `flutter build apk --release` fails by default. A throwaway
release build for local testing or a CI build check must opt in explicitly:

```sh
flutter build apk --release -Plocus.allowDebugSigned=true
# or: LOCUS_ALLOW_DEBUG_SIGNING=true flutter build apk --release
```

An APK signed that way is only good for testing and must not be distributed.
Release builds enable R8 (`isMinifyEnabled`/`isShrinkResources`) and use
`android/app/proguard-rules.pro`. Test reminders, boot re-arm, the widget, QR
scan, sync and encryption on the minified build before release.

Create a keystore once and keep it, and its passwords, somewhere safe. Losing it means you can never publish an update to the same app:

```sh
keytool -genkeypair -v -keystore locus-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias locus-upload
```

Put `locus-upload.jks` in `android/` (it is git-ignored), fill in `android/key.properties`, then:

```sh
flutter build apk --release
```

## CI

The `build-android` job in `.github/workflows/ci.yml` builds a release APK after the tests pass and uploads it as the `locus-android-apk` artifact. With no signing secrets it sets `ORG_GRADLE_PROJECT_locus.allowDebugSigned=true` so the job can still verify that the project builds; the job summary says the APK is debug-signed. To have CI sign it with your release key, add these repository secrets:

- `LOCUS_KEYSTORE_BASE64`: the keystore, encoded with `base64 -w0 locus-upload.jks`
- `LOCUS_KEYSTORE_PASSWORD`
- `LOCUS_KEY_ALIAS`
- `LOCUS_KEY_PASSWORD`

## Gradle wrapper

`android/gradle/wrapper/gradle-wrapper.properties` must point at the public Gradle download, not a file on one machine. If your network blocks that download, point it at a local copy on your machine only and do not commit the change.

## Backups

`dataExtractionRules` and `fullBackupContent` keep sync pairing state (the secure-storage token, and the SharedPreferences cursors and pinned desktop certificate) out of Android backups and device transfers. The planner data itself can still be backed up. After restoring onto a new phone, pair again; pairing again replaces the old entry for that phone on the desktop.

## Play Store and exact alarms

## Release build shape

Tagged Android releases build an **AAB** for Play, not a universal APK:

```sh
flutter build appbundle --release \
  --dart-define=LOCUS_DB_ENCRYPTION=true \
  --obfuscate --split-debug-info=build/symbols/android
```

The APK is still built by CI as a build/smoke artifact. Release symbols are
uploaded separately and must never be attached to public artifacts. The release
gate verifies `libsqliteX.so` in both the APK and AAB for every shipped ABI.
New installs create an encrypted database; existing plaintext databases stay
plaintext in 1.5.0.

Release listing, data-safety and exact-alarm declaration steps are in
[`PLAY_STORE.md`](PLAY_STORE.md). The app declares `USE_EXACT_ALARM` for
Android 13+ and caps `SCHEDULE_EXACT_ALARM` at API 32. Users can disable exact
timing in Settings → Sync; reminders then fall back to approximate alarms.

## Share sheet, clipboard and camera

`AndroidManifest.xml` registers the main activity for `ACTION_SEND` and
`ACTION_SEND_MULTIPLE` with `mimeType="*/*"`. `MainActivity` treats the incoming
URIs as untrusted input: it copies each stream into `cacheDir/shared` with a
sanitized display name and hands only those app-private paths to Dart, where
they pass the normal attachment import checks. Unreadable items are skipped
without dropping the rest. Sharing while the app is running is delivered
through `locus_planner/share_intake`.

The same activity exposes `locus_planner/clipboard` for clipboard images.
`image_picker` provides camera capture; because the app does not declare
`CAMERA`, the capture intent is handled by the system camera app and no runtime
camera permission prompt is added. Test share intake, clipboard paste and camera
capture on a physical device before release: they have no automated coverage.

## Share retry and widget publication (1.6.1)

Share intake now records a durable row per file before importing it:
`pending`, `importing`, `retryable`, `imported`, `permanently_rejected` or
`user_discarded`. A transient read, storage or database failure keeps the
staged bytes and task, records `retry_count` and a stable reason code, and
offers Retry/Discard from the Sync surface. Native cleanup is acknowledged only
after every file has a terminal outcome; the claim is released in a finally
block and cleanup is idempotent after a crash.

Widget publication is one `publishSnapshot` channel call carrying title, body,
event/task/habit counts, generation, instant, day and the expected zone. Kotlin
validates day/zone/generation, writes the complete snapshot in one checked
`commit()`, then redraws the provider. A zone change gets one immediate retry;
overlapping updates coalesce; a failed publication keeps the last complete
snapshot and the stale-date label/Add action.
