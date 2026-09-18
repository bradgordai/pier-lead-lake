# F17 continued: R1-R3, H1-H3, i067, B1, B2 — 2026-09-18

## R1 Migration 107 APPLIED
46 synthetic CR rows Sent -> Cancelled, each logged whole in touch_merge_log. **CR funnel (Sent connection
requests): 443 before, 397 after R1, 396 after R2** (one of the 62 merged empties was a CR: Gandon/Largo).
Note for F16.7: the card's "442 vs 443" puzzle is now moot; the true figure is 396.

## R2 F17.2(b) merge RUN (migration 112)
62 empty rows merged into their 62 bodied keepers. No deletes. Empty row: send_status Cancelled,
duplicate_of = keeper. Keeper inherits thread_id, thread_url, sent_at_actual, subject_line where it lacked
them (external_key deliberately not moved). 124 before/after rows in touch_merge_log
(`empty_row_merged_into_keeper`, `keeper_inherited_from_empty_row`). Sent rows in the database 984 -> 876.
To reverse any one: restore send_status and duplicate_of from its `before` JSON.

## R3 Migration 109 (drainer cron) is NOT APPLIED and must not be
Brad's decision: it launches real sends unattended, which breaks the rule that nothing sends without
Oliver. The file is now `migrations/109_DO_NOT_APPLY_send_queue_drain_cron.sql` with a warning header, and
the reconcile script treats it as held. **Consequence while it is unapplied:** the spacing rule still
holds, and a send that arrives early is queued (send_status Ready, response `queued` + `send_after`), but
nothing launches it. It goes when someone presses Send now again after `send_after`. With 21 approved
drafts that means roughly one press every 3-5 minutes, not a bulk action.

## H1 Migrations home: /migrations
The 7 files in supabase/migrations/ were moved with git mv; the directory is gone. `supabase migration
list` CANNOT reconcile and never could: the CLI on this machine is not logged in, and every migration has
been applied through the MCP, which records timestamp versions, not the NNN_ prefixes. Names are the
stable key. `scripts/check_migrations_reconcile.py` compares /migrations to schema_migrations by name.
Compared by hand today (114 files, 115 applied):
- applied, no file of that name: `weekly_dq_snapshot_cron` (its file is 032_weekly_dq_snapshot_cron),
  `pier_pipeline_team_scoping`, and `38c0d2fc-492e-4661-818a-142c9cdfd583` (applied from Lovable, no file).
- file, not applied under that name: 032_weekly_dq_snapshot_cron (see above), 095_f15_1_staging_sn_export,
  109 (held deliberately).
- duplicate 103: both are applied and both have files. Resolved by KEEPING both names. Renaming either
  file would break the only key that reconciles. They are idempotent and ordered by applied time.
Not done: recovering the SQL of the two file-less migrations from schema_migrations.statements.

## H2 One line for Brad
Approve one deploy of `generate-daily-insight` (v17 -> v18): the only executable change is the auth line,
which adds the team-member JWT path beside the secret; the rest is two comment lines. Source is committed.

## H3 Audit noise: MARKED, not deleted (migration 113)
2,115 audit_log rows from my three bulk writes today (1,141 + 812 + the flip/merge writes) now read source
`system_backfill_f17` and their summary starts "[F17 bulk migration write, not a human action]". Filter
`source <> 'system_backfill_f17'` to read human activity. Audit history is never removed.

## i067 Sign-off — the measured cause was incomplete. The CODE told the model to sign "Oli".
generate-draft-from-context held `NICKNAMES = { oliver: "Oli" }`. Every prompt said "Sign off: Oli", and
`ensureSignOff` appended "Oli" if the model left it off. ai-edit-draft had the same map. A voice-layer
rule alone would have been overruled by the prompt. Layer 4 looked like the source only because it is the
one layer that says otherwise.
(a) Rule added to voice layer 1 `pier_rules` (every draft), version now "v2.0 (24 Jul 2026) + sign-off rule
18 Sep 2026". Code: nickname map emptied; sender is "Oliver", or "Oli" ONLY if that contact has a prior
Sent message ending "Oli"; ai-edit keeps whatever sign-off the draft already has. Deploy status below.
NOT done: the separate voice agent / pier_ea_documents copy was not updated.
(b) Drafts fixed (migration 114): **58 drafts across 56 contacts** changed Oli -> Oliver (46 pending_review,
12 rejected). Brad measured 57 across 55; the difference is one draft created by this morning's 06:15 run.
**The ONE that keeps "Oli": Sanmeet Singh Kochhar, HMD (P651)**, pending_review. None of the approved
drafts signed Oli, none touched. Each change logged before/after in touch_merge_log.
(c) Sign-off only: a single end-anchored regex on the final word. No draft regenerated, lint not re-run.

## B1 The 137-row gap: THE TILE IS RIGHT, the database count was wrong
Predicate, inferred from the arithmetic (I did not read the Lovable source for it): the tile excludes rows
whose draft_status is superseded or rejected. 984 Sent rows, of which **136 superseded + 2 rejected = 138**,
gives 846; Pelzer's row made 847. Oliver has NOT been reading an undercount.
The defect is in the data: 138 rows are `send_status = Sent` AND `draft_status = superseded/rejected`, a
state trigger trg_superseded_is_not_sent exists to prevent. They are history twins retired in F14/F15 by
draft_status only. **Every server-side guard that reads `send_status = 'Sent'` alone still counts them**:
the DM/CR/InMail capacity checks in send-approved-draft, the routing matrix's `realOn`, fn_evaluate_gates.
After today's changes: database Sent 876, of which 738 carry draft_status `sent`; the tile should now read
about 738. NOT FIXED: moving the 138 to Cancelled (same pattern as 107). It needs Brad's yes because it is
another visible-number-neutral but guard-visible change.

## B2 "chaser 3 of 2" — paste into Lovable
> Do not pause for a plan. In the outreach card footer that renders "chaser N of M": (1) take M from the
> cap for THE DRAFT'S OWN `channel` (LinkedIn DM 3, LinkedIn inMail 2, from the chase rules), not from the
> channel of the contact's earlier touches. Today a DM Chaser 3 for a contact whose history is InMail shows
> "of 2". (2) compute N as 1 + the number of that contact's rows on the same channel where
> `send_status = 'Sent'`, `draft_status` is not superseded/rejected, `duplicate_of is null`,
> `observed_or_inferred <> 'inferred'` and touch_type starts with "Chaser". Do not derive N from the
> touch_type label. (3) if N > M render "over cap, should not exist" in red instead of "N of M".

## Deploy status
(appended when the agent reports)

## Not in scope here
i001 Oliver's login: an account issue, Brad is checking with him. i094: prepared, only Oliver can re-verify
in Sales Navigator (list: docs/reports/f17-4-oliver-connection-recheck-list-2026-09-18.md). i071's research
agent is Oliver's to start.
