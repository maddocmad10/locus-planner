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

## Operational items that need credentials or store access

### A.2 — Windows code signing

Requires an OV/EV certificate and CI secrets. The repository already documents
the signing process in `docs/DISTRIBUTION.md`; no private key or certificate is
committed. This cannot be completed from source alone.

### A.4 — Play Store and exact alarms

Requires Play Console access, the exact-alarm declaration, a hosted privacy
policy and closed testing on real devices. The app already keeps reminders
local; the declaration and listing must be completed by the release owner.

## Not implemented yet

- **B.2** recurrence editing on Android and local background sync.
- **B.3** Android home-screen widgets and reminder-status messaging beyond the
  existing Sync-tab controls.
- **B.4** Kanban/timeline project views. Global search across events, tasks,
  habits, projects, diary and focus sessions already exists in the command
  palette.
- Phase C raw/logical recovery, which gates production database migration.

## Verification

- `flutter analyze --fatal-infos`
- `flutter test`
- `flutter build windows --release`
- `flutter build apk --release`
- Natural-language parser and onboarding tests run fully offline.
