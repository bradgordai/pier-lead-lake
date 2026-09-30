# F23 repair batch, 30 Sep 2026 (session lovable5)

Nothing was sent. No Send now, Approve, phantom launch, drainer trigger or Make run/replay. No PhantomBuster or
Make setting was changed.

## Baseline, re-measured 30 Sep (before any change) — deviations from the brief are findings
| Measure | Brief (12:35 BST) | Measured | Note |
|---|---|---|---|
| contacts | 1035 | 1035 | |
| companies | 1159 | 1159 | |
| outreach_log Sent | 1153 | **1155** | +2 |
| Sent with sent_at_actual | 706 | **708** | +2 |
| Cancelled | 197 | 197 | |
| pending_review | 107 | **110** | +3 |
| approved and unsent | 18 | 18 | |
| rows with phantom_run_id | 56 | 56 | |
| send_error 'phantom_skipped_duplicate_or_empty' | 11 | 11 | |
| send_queue | 42 done, 12 failed, 0 live | 42 done, 12 failed | |
| last real send | 29 Sep 15:52 BST | **30 Sep 10:52 UTC** | see below |
| latest migration | 148, "file committed" | 148 applied, **file untracked** | committed dbe79de, NOT re-applied |

FINDING, last send: Torsten Schimkowiak (29 Sep 14:52 UTC, run 7026838469692543) is the last PHANTOM send. Five
later rows are Follow up / InMail marked Sent with sent_by='Oliver' and NO phantom_run_id: P1007 Leonardo Ramirez
Peña (29 Sep 12:45), P781 Daniel Freudenberger (14:33), P099 Dr. Philipp Gattner (14:35), P031 Mike Reif (30 Sep
10:03), P103 Thomas Gros (10:52). They look like hand-marked sends, not dispatcher sends.

## Task 1 — DONE (cause fixed, data repaired per Brad's ruling, regression test)
EVIDENCE: migration 149 (schema_migrations 20260930151303); send-approved-callback **v17** (ezbr 69e52833), index.ts
and _shared/authorize.ts byte-identical to the repo; test tests/send_hold_reason_test.py.
DEVIATION FROM THE BRIEF (Brad's error, confirmed by him): the 11 rows were NOT approved. All 11 were already
draft_status='superseded'. WHAT SUPERSEDES THEM (reported, not fixed): trigger **trg_supersede_failed_send**
(function fn_supersede_failed_send, migration 145, F22B.9): BEFORE UPDATE OF send_status, when send_status becomes
'Cancelled' on an 'approved' row it sets draft_status='superseded' and rejection_feedback reason 'send_failed'.
The v16 skip path set Cancelled, so every skip was superseded the moment the callback ran. 10 of 11 carry reason
send_failed; Deiminger's carries non_sales_reply (F22B.5 supersede).
Also: 8 of the 11 duplicate messages already delivered later (Torsten x4, follow-up sent 29 Sep; Benjamin Köhler x3,
sent 28 Sep; Leonard Coen's Initial message, opener sent 2 Sep).
(a) CAUSE: v17's skip path (exit 0, empty resultObject) writes send_status='Draft', draft_status='pending_review'
    (never approved), hold_reason='phantom_skipped_duplicate'. Cancelled is no longer written, so
    trg_supersede_failed_send cannot fire on a skip. A repeat callback for the same run is ignored (Draft + hold_reason);
    a real send clears hold_reason.
(b) DATA, per Brad's ruling (NOT the brief's "restore all 11"): outreach_log.hold_reason added; ALL 11 tagged; ONLY the
    newest Urs Moeller Chaser 1 (e143db6f, created 24 Sep) restored; Deiminger never restored.
    BEFORE: 11 × send_status Cancelled / draft_status superseded / hold_reason null.
    AFTER: 10 × Cancelled / superseded / phantom_skipped_duplicate; 1 × Draft / pending_review / phantom_skipped_duplicate.
    ZERO of the 11 at draft_status='approved' (asserted inside the migration).
    NOTE: Urs Moeller now has TWO open Chaser 1 drafts (e143db6f restored + 3bab700a of 26 Sep, near-identical text).
    trg_one_open_draft fires on INSERT only, so the restore by UPDATE did not supersede either. Oliver should approve at
    most one.
(c) REGRESSION TEST: **tests/send_hold_reason_test.py**. It fails if send-approved-draft's accepted send_status list
    stops including the status a hold_reason row carries, if the callback's skip branch writes Cancelled or approved,
    or if it stops writing hold_reason. PASS on v17; run against the v16 source it FAILS on 3 counts (proved).
TS types regenerated after 149 (hold_reason present in Row/Insert/Update).
FLAGGED, not fixed: (1) an InMail skipped a SECOND time after being re-sent gets no second credit refund
(fn_ledger_inmail_reverse refunds once per row). (2) Brad's finding: Torsten had chase_state='replied' (soft decline 23
Sep) yet got four Follow up drafts and a real send on 29 Sep; contact_replied only fires for p_requested='chaser', so
'Follow up' (requested='reply') bypasses it.
