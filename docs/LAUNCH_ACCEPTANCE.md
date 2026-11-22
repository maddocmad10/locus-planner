# Launch acceptance evidence (schema release)

Record evidence from the **installed candidate**, not a debug or mocked run.
Attach the files/links named below to the release record.

## Distribution record

| Field | Value |
| --- | --- |
| Version / build | 1.6.1+6 candidate |
| Commit / tag | |
| Windows installer | path, SHA-256, signer subject, signature status |
| Android AAB / splits | path, SHA-256, signer, Play test-track version |
| Target SDK / build tools | |
| Private symbols | location |
| Support email / privacy URL | actual non-placeholder `LOCUS_SUPPORT_EMAIL` / HTTPS `LOCUS_PRIVACY_URL` |
| Approver / date | |

## A — Fresh launch and pairing

- [ ] Install the signed Windows artifact from the registered shortcut and the
      Play test-track build on a physical phone.
- [ ] Pair on a private LAN, restart both ends, change the desktop LAN address,
      reconnect, and make one two-way edit.
- [ ] Today shows “Saved on this device”, pending count and a last-clean sync
      time. Evidence: screenshots and sync log.

## B — Conflicting edits and replay

- [ ] Run the two-device edit-vs-delete case in both directions.
- [ ] Run the three-device relay: snapshot, phone A due-date change, desktop
      title change, relay to phone B, then sync all three twice.
- [ ] Interrupt one upload and one download; reject one row in each direction;
      restart, inspect the retained repair, retry and confirm resolution.
- [ ] Compare final values, writers, deletion states and attachment hashes.

## C — Reminder delivery and navigation

- [ ] Schedule one task and one event, quit Locus, observe each once.
- [ ] Open the intended item from the notification after a cold start and from
      an already-running locked instance.
- [ ] Repeat after sleep/wake, Snooze, an edit from Android and disabling
      reminders. Confirm the install-time UTC millisecond mapping (no 1601
      offset) and the missed-reminder inbox.

## D — Device loss and restore

- [ ] Restore a fresh encrypted database and a legacy-upgrade backup on a second
      installation. Open a diary entry, a nested task and an attached file;
      compare the file digest.
- [ ] Re-pair a phone holding pending edits and record how deletions and pending
      changes were reconciled.

## E — First use, accessibility and backup

- [ ] New encrypted install shows “Set up backups” with Later; Later leaves the
      dashboard action; setting it up writes a verified first copy.
- [ ] Windows keyboard-only focus and activation; Android large text and
      TalkBack labels on the widget Open/Add actions and share result.
- [ ] Airplane-mode local save still succeeds and Today distinguishes offline,
      transferring, partial and clean states.

## F — Distribution and feature releases

- [ ] Signed Windows executable and installer verify with the expected publisher;
      hashes were computed after signing.
- [ ] Android AAB/splits pass the bundle gate, 16 KB ELF alignment and
      `zipalign -c -P 16 -v 4`; encrypted open/pair/sync/reminder pass on a 16 KB
      environment and a conventional 4 KB device.
- [ ] §7: attach feed refresh/move/cancel/EXDATE/timezone fixture output.
- [ ] §8: attach 300-row Todoist import, rerun and modified-export preview output.
- [ ] §9: attach leap year, last-Friday, missing-fifth-weekday, DST and legacy
      weekly recurrence output.

## G — Schema 30 remediation runs

Record pass / fail / unverified for the exact candidate below.

| Run | Evidence |
| --- | --- |
| Upgrade in either order | Fixed phone on 1.6.0+5 against the candidate desktop, then reverse; repeat with the schema-29 candidate. Pair, edit one item each way, drop a reply, restart and sync twice. Compare contents, ids, repair counts and last clean exchange. |
| Recovery and isolation | Positive deletion horizon; recover a task plus attachment, restart and reconnect twice. One fresh id, same bytes. Interrupt initial capture. Re-pair to a different dataset and confirm the old decision cannot modify it. |
| Partial sync and offline completion | Child before parent in both directions. Missing receipt, unknown result and capped pull must read Partial or Needs attention until accounted. Complete the Kolkata/UTC task offline; exactly one completion and the same next slot on both devices. |
| Backup and migration | Populated v28 and v29 fixtures with pending edits, repairs, reminders, deletion markers, diary and attachment bytes. Upgrade, compare counts/ids/digests, restore from the independent encrypted copy on a clean install, open the file. |
| Platform workflows | Windows partial-acceptance reminders, closed-app OS delivery, unlock navigation. Android transient share failure and restart, widget refresh failure, day rollover, direct capture, large text and TalkBack. |
| Calendar and import | Truncated refresh keeps the existing meeting; valid empty removes it. 304 freshness and coverage extension, monthly boundaries and skips, stable Today reads. Replay modified CSV imports and an older-peer recurrence edit. |
| Signed artifacts | Clean checkout with the canonical Android script; inspect AAB and splits, native load-segment and packaging alignment. Encrypted open/sync on 4 KB and 16 KB. Signed Windows installer, publisher, support address and live privacy URL. |

