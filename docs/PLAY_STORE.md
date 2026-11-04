# Play Store release and exact-alarm policy

This is the operational checklist for the Android companion. Locus is
offline-only: no planner data is sent to any service, and there is no account.

## App identity and signing

- Application ID: `com.locusplanner.app` (change before the first real install
  if you own a different domain).
- Release signing: `android/key.properties` locally or the `LOCUS_*` CI secrets;
  see [`ANDROID_RELEASE.md`](ANDROID_RELEASE.md). Never commit the keystore.
- Build the store artifact with:

```bash
flutter build appbundle --release
```

- Upload `build/app/outputs/bundle/release/app-release.aab` to the Play Console.
- Use an internal/closed testing track first and confirm pairing, LAN sync and
  reminders on a real phone.

## Exact-alarm declaration

The app declares:

```xml
<uses-permission
    android:name="android.permission.SCHEDULE_EXACT_ALARM"
    android:maxSdkVersion="32" />
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
```

`USE_EXACT_ALARM` is the Play-policy declaration for Android 13+. `Locus Planner`
is a calendar, task and reminder app; reminders are a core feature, not an
optimisation. Suggested justification text for the Play Console form:

> Locus Planner is a calendar, task and habit planner. Users schedule event and
> task reminders that must fire at the selected minute even when the app is
> closed. We use exact alarms only for user-created local reminders, never for
> advertising or analytics. Reminders are scheduled entirely on-device; the app
> has no cloud push. Users can turn exact timing off in Settings → Sync, in
> which case reminders fall back to approximate alarms with an in-app
> explanation.

The app does **not** request `SCHEDULE_EXACT_ALARM` on Android 13+; it is capped
at API 32 where `USE_EXACT_ALARM` does not exist.

## Data safety and privacy policy

The privacy policy must state all of the following and must be hosted at a
public HTTPS URL before submitting:

- Planner content (events, tasks, projects, habits, diary, focus sessions,
  settings) is stored only in the local SQLite database on the device.
- There is no cloud account, no cloud sync, no third-party analytics and no
  crash reporting containing content.
- LAN sync uses a self-signed TLS connection with certificate pinning and only
  talks to the paired desktop on the local network.
- Backups and ICS files are user-initiated local file operations.
- Database encryption keys, pairing tokens and recovery material stay in the
  OS-protected store or are exported only by the user.
- Optional update checks, if ever added, fetch version metadata only.

Data safety form: no user data is collected or shared by the app with third
parties. Declare local data handling accurately; do not claim network
transmission that does not exist.

## Store listing

- Emphasise local-first, offline, no account, Windows + Android LAN pairing.
- State that Windows is the primary editing surface and the Android app is a
  capable daily companion.
- Do not promise cloud sync or calendar-provider sync; bidirectional calendar
  sync is explicitly out of scope.

## Permissions

| Permission | Rationale |
|---|---|
| `INTERNET` | LAN sync with the paired desktop only. |
| `POST_NOTIFICATIONS` | User-visible event and task reminders. |
| `USE_EXACT_ALARM` | On-time local reminders for calendar/task events. |
| `SCHEDULE_EXACT_ALARM` (≤ API 32) | Same feature on Android 12/12L. |
| `RECEIVE_BOOT_COMPLETED` | Re-arm stored reminders after a reboot. |
| Camera (optional) | QR pairing only; manual pairing works without it. |

## Pre-launch checks

- [ ] AAB signed with the upload key and uploaded.
- [ ] Exact-alarm declaration submitted with the text above.
- [ ] Privacy policy published and linked in the listing.
- [ ] Home-screen widget added and verified to refresh after an event/task edit.
- [ ] **Exact reminder timing** switch verified on and off; approximate fallback still fires.
- [ ] Recurring event edited and one occurrence skipped on the phone; both devices agree after sync.
- [ ] Closed testing on a physical phone: create/edit/delete a repeating event,
      sync both ways on the LAN, toggle exact timing, reboot and confirm a
      reminder, and use airplane mode to confirm local operation.
- [ ] Data safety form completed consistently with the policy.
- [ ] Version code/name in `pubspec.yaml` incremented.
