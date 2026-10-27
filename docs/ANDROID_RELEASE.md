# Android release

## App ID

`applicationId` in `android/app/build.gradle.kts` is the app's identity on a phone. It is currently `com.locusplanner.app`. Change it to an ID you own (for example a reversed domain name) **before the first real install**: if it changes later, Android treats the app as a different one, so there is no in-place update and the data does not carry over. The separate `namespace` is only the Kotlin package of `MainActivity` and does not have to match. CI fails if the ID is still a `com.example...` template value.

## Signing

Release builds are signed with a key from either:

1. `android/key.properties` (git-ignored; copy `android/key.properties.example`), or
2. the environment variables `LOCUS_KEYSTORE_FILE`, `LOCUS_KEYSTORE_PASSWORD`, `LOCUS_KEY_ALIAS`, `LOCUS_KEY_PASSWORD`.

If neither is present, `flutter build apk --release` still works but is signed with the debug key, so it is only good for testing. An APK signed that way must not be distributed. Set `LOCUS_REQUIRE_RELEASE_SIGNING=true` to make the build fail instead.

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

The `build-android` job in `.github/workflows/ci.yml` builds a release APK after the tests pass and uploads it as the `locus-android-apk` artifact. To have CI sign it with your release key, add these repository secrets; without them the APK is debug-signed and the job summary says so:

- `LOCUS_KEYSTORE_BASE64`: the keystore, encoded with `base64 -w0 locus-upload.jks`
- `LOCUS_KEYSTORE_PASSWORD`
- `LOCUS_KEY_ALIAS`
- `LOCUS_KEY_PASSWORD`

## Gradle wrapper

`android/gradle/wrapper/gradle-wrapper.properties` must point at the public Gradle download, not a file on one machine. If your network blocks that download, point it at a local copy on your machine only and do not commit the change.

## Backups

`dataExtractionRules` and `fullBackupContent` keep sync pairing state (the secure-storage token, and the SharedPreferences cursors and pinned desktop certificate) out of Android backups and device transfers. The planner data itself can still be backed up. After restoring onto a new phone, pair again; pairing again replaces the old entry for that phone on the desktop.
