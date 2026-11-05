# Phase 4 — Local planning intelligence

Phase 4 is a deterministic workload assistant built from data that already lives
in Locus. It is not a hosted AI feature. There is no network call, model,
analytics endpoint, account or remote processing path.

## Surfaces

- `PlanningPage` is appended as `NavPage.planning = 11`, with a rail entry,
  `Ctrl+Alt+P`, and a command-palette entry.
- Tabs: **Suggestions**, **Eisenhower**, **Weekly review**.
- The page label is "Planning suggestions"; the subtitle says
  "Local workload assistant · no cloud, no AI service".

## Pure engine

`lib/features/planning_intelligence/domain/planning_engine.dart` receives an
immutable `PlanningSnapshot` and returns a `PlanningResult`. It has no Drift,
Flutter, network or clock dependency.

The snapshot contains:

- open/completed personal and project tasks, with priority, dates, estimate,
  importance and urgency override;
- per-day working hours, breaks, busy event intervals and schedule blocks;
- My Day plan items for the current horizon and the previous seven days;
- project finish-to-start dependencies;
- the Phase 2 planning profile (buffer, default slot, urgency window);
- weekly review source aggregates.

Identical snapshots and `now` values produce identical suggestions, ids and
ordering.

## Suggestion contract

Each `PlanningSuggestion` has:

- `id`, `type`, `title`, `explanation`;
- `reasons` (`code` + human-readable message);
- `references` (task/block/plan-item ids and labels);
- `operations`, each carrying explicit before/after values;
- `targetDate` and `actionable`.

Operations are applied only by `PlanningRepository.applySuggestion`. It runs one
database transaction and then offers one Undo action that restores every row.
If any operation is stale or invalid, the transaction rolls back and the UI
reports that the suggestion is no longer applicable.

Suggestions are **not persisted**. They are recomputed after each data change,
so a stale suggestion cannot survive a task edit. No `planning_suggestions` or
`planning_actions` table is added; accepted changes use the existing in-memory
`UndoService`, which already models a short-lived revert journal.

## Capacity rule

The engine reuses `CapacityService` from Phase 2:

```
available = working minutes - breaks - busy events - transition buffer
planned   = schedule-block durations + unblocked My Day estimates
```

A task with both a block and a My Day estimate is counted once. The block wins.
A My Day estimate is a fallback only when no block exists for that task/day.

## Suggestion rules

| Type | Trigger | Proposal |
| --- | --- | --- |
| Overcommitted day | Planned > available (or threshold) | Move a block or My Day item to a verified free window on a later day |
| Carry-forward | Incomplete item from a previous day's My Day | Move to today, choose a date, keep, or remove |
| Deadline risk | Due within seven days, no block, estimate needs capacity or a dependency is unfinished | Create a fitting block, or raise priority |
| Unscheduled priority | Priority ≥ medium, no date or block | Create a fitting block |
| Focus window | Contiguous free time fits an estimate | Create a block only after Apply |
| Weekly review | Local metrics exist | Open a read-only review; no mutation |
| Eisenhower | Open personal tasks | Derived urgency + user-assigned importance |

Dependencies inform blockers and deadline explanations. Phase 4 still never
auto-reschedules a task; every date/block change goes through Apply.

## Eisenhower matrix

- Importance is stored on `todo_items.is_important`; it is never inferred from
  priority.
- Urgency is derived from the due date against
  `planning_preferences.urgency_window_days` (1–30, default 3).
- `todo_items.urgency_override` pins a task to urgent/not urgent. The reason is
  shown as either "Manually marked…" or "Due in N day(s); window is N day(s)".
- Quadrants: Do first, Schedule, Delegate/Waiting, Eliminate/Review.
- Project checklist tasks keep their Phase 3 priority but do not enter the
  matrix until a project importance field exists.

## Weekly review

The repository computes exact local aggregates for the selected range:

- `todo_completions` in range, with both occurrence count and distinct tasks;
- project tasks completed and due in range;
- carried My Day items from the previous seven days;
- currently overdue open tasks;
- focus sessions and minutes;
- completed habit check-ins / possible daily check-ins;
- milestones completed / due in range.

Missing data is displayed as zero with a denominator, never estimated. The range
is labelled explicitly. There is no performance score, ranking or inference from
incomplete data.

## Schema and compatibility

Migration 20 is additive:

- `todo_items.is_important INTEGER NOT NULL DEFAULT 0`;
- `todo_items.urgency_override INTEGER NULL`;
- `planning_preferences.urgency_window_days INTEGER NOT NULL DEFAULT 3`.

The fields are in the existing sync payloads and backups. Older peers receive
safe defaults. The migration is guarded for very old databases whose
`createTable` step already used the current table shape.

## Privacy boundary

`test/phase4_privacy_test.dart` scans `lib/features/planning_intelligence` and
`lib/core/planning` for HTTP/WebSocket/socket imports and URLs. Planner content
never leaves the device except through the existing paired LAN sync, which is
outside the planning engine.
