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
- A timeline/Gantt view is not implemented. Saved views are implemented by the
  Phase 2 planning work below.

## Phase 2 — professional planning (schema 17)

The implementation is additive on top of schema 16. A single migration creates
the five new tables and the nullable estimate column; every existing row, id,
feature and sync cursor is preserved.

### Unified calendar

- `lib/features/calendar/` adds a stable, appended navigation page
  (`NavPage.calendar = 10`), reachable from the rail, `Ctrl+Alt+C` and the
  command palette. Existing indices 0–9 are unchanged.
- The calendar is a projection of events plus `task_schedule_blocks`; it is not
  a second event store. Recurring events reuse the same recurrence engine as
  My Day, including exception dates.
- Dragging or editing a block only changes that block. It never rewrites
  `todo_items.start_date`/`due_date`, My Day membership or a project checklist
  task. Every move, resize and delete offers Undo.
- Blocks are validated (exactly one parent, 5 minutes to 24 hours, at most two
  calendar days, controlled `work`/`focus`/`buffer` kinds) both in the
  repository and again during backup restore.
- Conflicts are shown as an advisory marker. Overlaps are never blocked or
  silently rescheduled.

### Capacity and working hours

- `planning_preferences`, per-weekday `working_hours` and optional
  `working_breaks` define a local planning profile. Merely opening the calendar
  uses in-memory defaults and writes nothing; only an explicit save creates sync
  traffic.
- `lib/core/planning/capacity_service.dart` is pure and deterministic: working
  intervals minus breaks, timed busy events, a per-block transition buffer and
  planned effort.
- Planned effort is `bookedMinutes + unblocked My Day estimates`; a task is
  counted once, and an actual block always wins over the estimate fallback.
- Overcommitment is informational. `remaining`, `overcommittedBy` and
  `utilization` are derived from the same numbers so the side panel and the
  weekly review cannot disagree.
- Estimates can be stored on a personal to-do through
  `todo_items.estimated_minutes`; they are never treated as a booking.

### Saved views

- `saved_filters` stores a versioned JSON definition, never SQL. The parser in
  `lib/core/planning/saved_filter.dart` accepts only allowlisted fields and
  operators, bounds depth/clause/list/string sizes and compiles to a fixed WHERE
  template with every user value bound as a `?` parameter.
- Named date ranges (`today`, `thisWeek`, `overdue`, …) are resolved when the
  view runs, so saving a view never freezes a timestamp.
- LIKE search escapes `%`, `_` and the escape character. A definition from a
  newer build is kept and reported, never dropped or executed.
- Saved view names are unique per scope (case-insensitive). The editor offers
  the built-in smart views, sorting and pinning.

### Sync and backup

- The new entities travel through the existing outbox triggers and
  `SyncChangeApplier`; no sync protocol change is needed. Because these tables
  already use `updated_at` as business data, their sync version travels as
  `sync_updated_at`, exactly like daily plans.
- Snapshot order places task blocks after both parent task kinds.
  `SyncChangeApplier` also marks dependent streams updated when a deleted to-do
  or project task cascades away its blocks.
- An older peer skips the new entity types it does not know instead of failing
  the batch.
- Backup format v3 exports and restores `task_schedule_blocks`, `saved_filters`,
  `planning_preferences`, `working_hours`, `working_breaks` and
  `estimated_minutes`. Restore re-validates every definition, parent link and
  interval; a backup without these sections still restores normally.

### Tests

`test/phase2_saved_filter_test.dart`, `test/phase2_capacity_test.dart`,
`test/phase2_repository_test.dart`,
`test/phase2_calendar_projection_test.dart`,
`test/phase2_backup_sync_test.dart` and `test/phase2_navigation_test.dart`
cover the parser/compiler, capacity arithmetic, repositories and Undo,
projection/conflicts, backup and sync compatibility, and navigation wiring.
The generated v17 Drift fixture also verifies the `16 → 17` migration.

## Phase 3 — advanced project management (schemas 18 and 19)

Phase 3 extends the existing project checklist instead of duplicating the task
system. The suggested v20/v21 numbers in the source schema were rebased onto the
current mainline: workflow fields arrive in **v18**, dependencies in **v19**.
Existing task ids, project ids and the `completed` flag are retained.

### Statuses and Kanban

- `tasks` gains `status_key`, `start_date`, `due_date`, `estimated_minutes` and
  `priority`. Migration 18 backfills `status_key` from `completed` and leaves
  every id untouched.
- The status vocabulary is deliberately closed: `backlog`, `todo`,
  `in_progress`, `waiting`, `done`. Per-project `project_statuses` rows store the
  display name, bounded colour token, order and default/done metadata. New
  projects receive deterministic status row ids; migration 18 seeds every
  existing project.
- `completed` is never written independently of `status_key`. Repository
  methods update both atomically, and inbound sync normalises an old peer's
  `completed` flag into the matching status (or ignores a stale flag).
- The project sheet now has List, Kanban and Timeline views. List and Kanban
  read the same `tasks` stream. Cards can be dragged between the five columns;
  the drop updates status, completion and sort order in one transaction.
- Status names, colours and order can be customised. Arbitrary colour strings
  are rejected; only the bounded palette is accepted by the repository, backup
  restore and sync.

### Milestones

- `project_milestones` stores project-level checkpoints: title, optional
  description/target date, `completed_at` and position.
- Create, edit, complete and delete are supported, with Undo. Project deletion
  cascades milestones and the project Undo restores them.

### Dependencies and timeline

- `task_dependencies` stores finish-to-start edges only: one row per
  predecessor/successor pair, no self-edge, bounded lag, both tasks in the same
  project.
- The repository rejects cycles with an explicit message before insert.
  Dependencies are advisory: they display blockers and validate suggested
  dates, but never move tasks or rewrite dates automatically in Phase 3.
- The timeline is a derived, read-only projection of project tasks and
  milestones. It supports day/week/month zoom, horizontal scrolling, an
  Unscheduled lane, overdue highlighting and dependency connectors. No bar
  positions, critical path or layout coordinates are persisted.
- Date fields use local date-only semantics and the same `DayMath` helpers as
  the calendar, so DST changes cannot shift a project date.

### Sync and backup

- New synced entities: `project_status`, `project_milestone` and
  `task_dependency`; `project_task` payloads gain the workflow fields.
- Snapshot order is project → status/task → dependency. Inbound dependencies
  are checked after both endpoint tasks exist; orphan endpoints and cycles are
  rejected with a diagnostic instead of being silently dropped. An old peer's
  checklist payload still degrades to `todo`/`done`.
- Migration 19 rotates the sync epoch so an already paired phone fetches a
  fresh snapshot with the new status rows and task fields.
- Backup v3 exports/restores the three new sections. Restore validates every
  status key/colour, milestone parent and dependency endpoint, and drops
  duplicate or cyclic edges. Project deletion/restore cascade tests cover the
  new family.

### Tests

`test/phase3_repository_test.dart`, `test/phase3_backup_sync_test.dart`,
`test/phase3_timeline_test.dart`, `test/phase3_migration_test.dart` and
`test/phase3_projects_widget_test.dart` cover status/completion coupling, Kanban
and list parity, milestone Undo, dependency validation/cycles, blockers,
project cascade/Undo, backup restore, sync ordering and rejection, old-peer
degradation, the timeline projection and both sequential migrations.
The generated v18/v19 fixtures verify both migration steps.

## Phase 4 — productivity intelligence (schema 20)

Phase 4 adds a deterministic, fully local workload assistant. It is explicitly
labelled **Planning suggestions** / **Workload assistant**; there is no AI
service, network call, hosted model, analytics or external account.

### Engine boundary

- `lib/features/planning_intelligence/domain/planning_engine.dart` is pure. It
  receives an immutable `PlanningSnapshot` and returns suggestions, the
  Eisenhower matrix and the weekly review. It never reads Drift or the clock.
- `PlanningSnapshotRepository` builds the snapshot from existing local rows:
  tasks, My Day plans, project tasks, schedule blocks, events, working hours,
  breaks, dependencies, focus sessions, habits, completions and milestones.
- Identical snapshots produce identical suggestion ids, order and text.
- Every suggestion carries reason codes, input references, explicit
  before/after operations and Apply/Skip. Suggestions are transient; stale
  suggestions are rebuilt after each change rather than persisted.
- Accepted operations run in one repository transaction and offer one Undo
  action that restores every changed row. No task, due date, recurrence or
  block changes before Apply.

### Recommendation types

- **Overcommitted day** — planned effort exceeds available capacity; proposes
  moving a specific block or My Day item into a verified free window on a later
  day.
- **Carry-forward** — unfinished My Day items from earlier days; apply to today,
  choose a date, keep, or remove. Moving uses the same task row and de-duplicates
  the destination plan.
- **Deadline risk** — due-soon open tasks with no block; proposes a fitting
  calendar window, or raises priority when no window or a blocker exists.
- **Unscheduled priority** — medium/high-priority task with no date or block;
  proposes a concrete block.
- **Focus window** — contiguous free time that fits a task estimate; proposes
  one candidate per window, never books automatically.
- **Weekly review** — completed tasks, carried tasks, overdue tasks, focus time,
  habit check-ins and milestone movement, with the selected date range and
  denominators.
- **Eisenhower matrix** — importance is user-assigned; urgency is derived from
  the configurable due-date window and shown with its rule. A per-task urgency
  override and a matrix view are included.

### Capacity and double counting

- Reuses the Phase 2 capacity engine and precedence rule: an actual schedule
  block wins over a My Day estimate for the same task/day.
- Breaks, busy events and the transition buffer reduce available capacity.
- Date-only and calendar-day math reuse `DayMath`, so DST changes cannot shift a
  planning date.

### Schema, sync and backup

- Migration 20 adds `todo_items.is_important`, nullable
  `todo_items.urgency_override`, and
  `planning_preferences.urgency_window_days`.
- The fields travel in the existing todo and planning-preference sync payloads;
  older peers get safe defaults. Backup restore defaults old rows to neutral
  importance and a derived urgency.
- No `planning_suggestions` or `planning_actions` table is added: suggestions
  are recomputed from current data, and accepted changes use the existing
  in-memory UndoService. This avoids stale persisted suggestions after every
  task edit.

### Tests

`test/phase4_engine_test.dart`, `test/phase4_repository_test.dart`,
`test/phase4_backup_sync_test.dart`, `test/phase4_migration_test.dart`,
`test/phase4_navigation_test.dart`, `test/phase4_planning_page_test.dart` and
`test/phase4_privacy_test.dart` cover determinism, capacity precedence, all
suggestion types, explicit before/after values, transactional apply/Undo,
carry-forward date choices and deduplication, matrix overrides, weekly
denominators, backup/sync compatibility, the v20 migration, navigation, empty
states and the no-network boundary.

## Verification

- `flutter analyze --fatal-infos`
- `flutter test`
- `flutter build windows --release`
- `flutter build apk --release`
- Natural-language parser and onboarding tests run fully offline.
