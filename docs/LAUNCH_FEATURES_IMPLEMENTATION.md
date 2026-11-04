# Launch and next-wave implementation status

Source: `Locus_Planner_Implementation_Schema.docx` (v1.4.0 baseline).
The offline-only rules are accepted without exception: no planner data leaves
the device, no cloud account is required, and LAN sync remains the only
multi-device mechanism.

## Delivered in code

### A.1 — release encryption configuration (groundwork)

- `lib/core/config/build_config.dart` adds compile-time switches:
  - `--dart-define=LOCUS_DB_ENCRYPTION=true` loads the bundled SQLite3MC
    runtime and opens encrypted databases.
  - `--dart-define=LOCUS_DB_MIGRATION=true` additionally allows an existing
    recognized plaintext database to be converted at startup.
- The switches are separate. A build can enable encryption for new databases
  without silently converting existing data. Without the migration switch the
  original file is left byte-identical and startup fails closed.
- Environment variables remain supported for desktop development.
- Release build instructions are in `README.md`, and the release checklist now
  covers the bundled native libraries.
- Defaults remain off. Production migration still waits for the Phase C
  recovery gate recorded in `docs/SQLITE3MC_E0_DECISION.md`.

Not yet code-complete for A.1: an in-app conversion prompt and end-to-end
encrypted backup/restore with passphrase recovery. Those depend on Phase C and
should not be simulated.

### A.2 — Windows code signing

- The tagged Windows workflow signs `locus_planner.exe` and the Inno Setup
  installer when `WINDOWS_CERTIFICATE_BASE64` and
  `WINDOWS_CERTIFICATE_PASSWORD` are configured.
- Every signature is timestamped and then verified with
  `signtool verify /pa`; the job summary states whether the artifacts were
  signed. Unsigned builds are explicitly marked as not for public distribution.
- The private key never enters the repository or logs.

The remaining step is operational: obtain an OV/EV certificate and add the two
protected repository secrets.

### A.3 — first-run / empty state

- `lib/features/onboarding/` adds a local-first welcome card with three actions:
  - **Create sample data** seeds one event, three tasks (one planned on today's
    My Day) and one habit, entirely on-device.
  - **Import .ics** routes to the existing Settings import flow.
  - **Start blank** records the completion marker.
- The card is shown only when the completion marker is absent and the event,
  task, project, habit and diary tables are empty. Existing installations never
  see it.
- iOS/Android-specific empty-state entry points and direct mobile card parity
  are still open.

### A.4 — Play Store distribution and exact alarms

- Android declares `USE_EXACT_ALARM` for API 33+ and caps
  `SCHEDULE_EXACT_ALARM` at API 32, matching Play's calendar/reminder policy.
- Settings → Sync now has an **Exact reminder timing** switch. Turning it off
  makes reminders approximate; when the OS restricts exact alarms the switch is
  disabled and the existing explanation is shown.
- The reminder card explains exact vs approximate timing and the 30-day planning
  window, and distinguishes Android native alarms from the Windows
  app-must-be-running model.
- `docs/PLAY_STORE.md` contains the exact-alarm justification text, permissions
  table, data-safety and privacy-policy requirements, and the closed-testing
  checklist.

Store submission and the certificate remain operational tasks.

### B.1 — natural-language quick add

- `lib/core/services/natural_language_quick_add.dart` parses, entirely offline:
  - today/tomorrow/day after tomorrow/next week/next Monday/Monday/in N days or
    weeks;
  - 9am, 9:30 pm, 14:00, at 9, at 14:30, noon, midnight;
  - daily, weekdays, weekly, every other week, every 2 weeks, every Monday,
    monthly and yearly repeats;
  - high/medium/low priority (`!!!`, `!!`, `!`, `p1`/`p2`/`p3`, words);
  - `#tag` and `@project` hints.
- The desktop quick-capture dialog, the mobile quick-capture sheet and the
  command palette all expose it.
- A confirmation preview shows the parsed date/time, repeat, priority, tags and
  project before saving. The title is editable in the same field.
- Unsupported phrases stay in the title; there is no remote NLP call.
- Tests: `test/natural_language_quick_add_test.dart` plus mobile widget tests
  for event and recurring-task creation.

### B.2 — mobile parity (partial)

- The Android event editor now edits the recurrence rule (none, daily, weekdays,
  weekly, every 2 weeks, monthly, yearly) and can skip a single occurrence via
  `recurrence_exceptions`. Changes to a repeating event apply to the series and
  the dialog says so.
- Past occurrences and past days are visually muted in Today.
- Existing mobile behavior already supports habit toggles, task reminders and
  My Day actions.
- Background LAN sync still runs on app open/resume (the existing
  one-minute-throttled auto-sync). A true WorkManager/background service that
  syncs while the app is not running is not implemented.

### B.3 — Android widget and reminder messaging

- Added a home-screen widget (`TodayWidgetProvider`) with an XML layout and
  `home_widget` data bridge. It shows the next events, due tasks and remaining
  habits for today.
- Flutter refreshes the snapshot on app start, resume, sync and database stream
  changes (debounced); it never performs network I/O.
- The reminder card now explains exact vs approximate timing, the 30-day
  planning window and the Windows/Android difference, and exposes the exact
  timing switch.
- `flutter build apk --release` includes the widget receiver and resources.

### B.4 — search and project views

- Global search across events, tasks, habits, projects, diary and focus sessions
  already existed in the command palette.
- The project checklist now has a **Board view** toggle: To do / Done columns,
  tap to toggle completion, with the same underlying data as the list view.
- A timeline/Gantt view and saved filters are not implemented.

## Verification

- `flutter analyze --fatal-infos`
- `flutter test`
- `flutter build windows --release`
- `flutter build apk --release`
- Natural-language parser and onboarding tests run fully offline.
