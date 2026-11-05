# Phase 3 — Project workspace

Phase 3 turns the project checklist into a small, local-first project workspace.
It does not add team collaboration, cloud state or a second task model.

## Schema sequence

The source schema suggested v20/v21. The current mainline was already at v17
after Phase 2, so the work was rebased to two sequential additive migrations:

| Version | Contents |
| --- | --- |
| 18 | `tasks.status_key`, `start_date`, `due_date`, `estimated_minutes`, `priority`; `project_statuses`; `project_milestones`; status backfill and per-project default seed |
| 19 | `task_dependencies`; dependency indexes; sync epoch rotation |

`completed` remains for compatibility with older clients and existing UI. The
repository is the only writer that changes status: it always updates
`status_key` and `completed` together.

## Status model

The five keys are fixed and shared by every device:

| key | default label | done |
| --- | --- | --- |
| `backlog` | Backlog | no |
| `todo` | To do | no |
| `in_progress` | In Progress | no |
| `waiting` | Waiting | no |
| `done` | Done | yes |

`project_statuses` stores display metadata per project. The row id is a UUIDv5
of `project_status:<projectId>:<statusKey>`, so two offline devices that upgrade
or create the same project converge on one row per key.

Only `ProjectStatusCatalog.colorTokens` are accepted. Backup restore and inbound
sync reject unknown keys, names outside 1–40 characters and colours outside the
palette. Arbitrary strings never reach a widget.

## Milestones

`project_milestones` is independent of `tasks`: title, optional description and
target date, optional `completed_at`, and position. A project deletion cascades
milestones; the project Undo restores them.

## Dependencies

Only finish-to-start edges are supported. The repository enforces:

- predecessor and successor exist;
- they belong to the same project;
- no self-edge and no duplicate pair;
- lag between 0 and 10080 minutes;
- no cycle, checked by graph traversal before the insert.

Dependencies display blockers and suggested-date warnings. They never move
tasks or change dates in Phase 3. Inbound sync applies the same endpoint,
same-project and cycle checks; an orphan endpoint is rejected with a diagnostic
rather than silently discarded.

## Timeline

The timeline is derived from project tasks and milestones. It draws:

- bars from `start_date` to `due_date` (one-day bars when only one date exists);
- milestone diamonds;
- finish-to-start connectors;
- overdue highlighting;
- an Unscheduled lane for tasks/milestones without dates.

Day/week/month zoom changes only pixels per day. The widget stores no layout,
critical path or bar coordinate.

## Backup and sync

- Backup v3 adds `project_statuses`, `project_milestones` and
  `task_dependencies`; task rows carry the new fields.
- Restore validates parents, status metadata, same-project edges and cycles.
- New sync entities are `project_status`, `project_milestone` and
  `task_dependency`; their version key is `sync_updated_at` because the rows
  already have business `updated_at`.
- Project snapshots sort before status/task rows, which sort before dependencies.
- Migration 19 rotates `sync.epoch` so a paired phone receives a fresh snapshot
  instead of missing rows that were seeded during migration.
- An older peer that only knows the checklist payload keeps working: a missing
  status degrades to `done` when `completed = 1`, otherwise `todo`.

## Out of scope

- arbitrary user-defined status keys;
- start-to-start, finish-to-finish or cross-project dependencies;
- dependency-driven automatic rescheduling (Phase 4, preview/accept only);
- persisted Gantt layout or critical-path computation.
