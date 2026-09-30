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

## Task 2a — BUILT AS A FLAG (Brad's amendment); NOT a gate; Task 2b CANCELLED
EVIDENCE: migration 150 (schema_migrations 20260930152444). fn_evaluate_gates md5 18099d27… unchanged and does not
mention company_already_approached.
- CONFIRMED by reading fn_group_siblings_engaged / fn_company_group_pairs: siblings are LINKED companies only (R1 exact
  parent_group, R2 parent_group names the sibling's domain, R3 parent_group names the sibling; engaged = Monday deal,
  opportunity_status Contacted/Active Lead/Partner, or a contact Contacted/In conversation/Meeting booked). Same
  company_id colleagues are not considered.
- RE-MEASURED (real first approaches, touch_type Initial message/Other, sent_at_actual NOT NULL, London day):
  **39 company-days, 96 people** (brief: 45 / 109). Worst: The Very Group 5, Rebuy 5, then mySWOOOP, Save Group, Forza
  Refurbished, bol.com 3 each. Counting real phantom CRs as well gives 79 company-days / 231 people, which may be how
  the brief's figure was reached.
- ENUM TRAP: the brief's 'Cold InMail' is NOT a touch_type value (values: Initial message | Connection request | Chase |
  Reply | Event follow-up | Introduction | Meeting confirmation | Other | Chaser 1-3 | Follow up). A cold InMail is
  'Initial message' on channel 'LinkedIn inMail'. The function uses ('Initial message','Other').
- mobileup: NEITHER mobileup contact (Beat, Elias) exists in Supabase, nor does Manuel at Jacob. Their InMails (28 and 30
  Jul) predate sent_at_actual, so the flag cannot see July-era history at all.
- BUILT: fn_company_already_approached(p_team_id, p_contact_id, p_requested) -> (flagged, colleague, approached_at,
  colleague_contact_id); the brief's 'blocked' column is named 'flagged' because nothing is refused. Chasers and replies
  never flag. v_draft_company_flags gives the flag + flag_text ("A colleague at this company, X, was approached on
  <date> and has not replied.") for every open draft. The card display is Lovable work (Task 4 message).
- REFUSAL COUNTS (before; unchanged because nothing is wired), 1,023 live contacts, channel LinkedIn DM:
  chaser: PASS 727, group_sibling_engaged 70, contact_parked 67, dnc_or_opted_out 67, pending_ruling 41,
  thread_text_missing 23, promise_of_quiet 17, contact_replied 9, allowance_exhausted 2.
  initial_message: PASS 761, group_sibling_engaged 70, contact_parked 67, dnc_or_opted_out 67, pending_ruling 41,
  promise_of_quiet 17.
- DRY RUN: open drafts 108 pending_review + 18 approved (brief: 107 + 18). FLAGGED: **24 pending + 5 approved = 29 drafts
  at 13 companies.**
  Approved (5): Luca Sansone and Daniele Voltolina (Comet; colleague Massimo Cillerai 25 Aug); Anthony O'Dea (GreenIT
  Ireland; Greg Kielek 28 Jul); Sanmeet Singh Kochhar (HMD; Anssi Rönnemaa 22 Sep); **Philipp Lohmar (Tchibo; Davit
  Gniech 28 Jul)**.
  Pending (24): Marcel Masek (0815); Nathalie D (AfB; Mike Reif); Caroline Prick, Luuc Mannaerts, Fiona Vanderbroeck
  (bol.com; Maite Zubiaurre); Sami Amarir, Ilias Moutani (DBC ELECTRONICS; Selim Salah); Rowan Westerduin (Fixje);
  Jean-Francois Baril, Csilla Bors, Duc Anh Nguyen P654 AND P921 (HMD, a duplicate contact); Konstantinos Stamatopoulos,
  Marta Gutiérrez Ràfales, Alexander Klinger, Janette Keller, Sebastian Koch, Henry Braun, Alexander T. Rauchut
  (MediaMarkt Saturn; Chris Stapelfeldt 10 Aug); Jean-Christophe Haimb (Pearl; Sandra Wursthorn); Frank Schuster, Monika
  Maciejewska (T-Mobile; Ronit Avzardel); Markus Lawrenz, Johannes Häner (topi; Leonard Coen 2 Sep).
- DEVIATION: Bianca Pfaller and Robert Karl (Drei) are NOT flagged. Nobody at Drei has a real send yet: all 6 Drei
  drafts are open (2 approved: Bianca, Robert; 4 pending). The flag looks at sends, not at open drafts queued together,
  so it fires for the rest as soon as the first Drei message goes out. A "sibling drafts also open" warning would need
  a second rule; not built.
- Oliver's two rulings (expiry, company vs group) are no longer needed; the flag is shown and he decides.

## Task 3 — STOPPED AND REPORTED: THE DATABASE IS AT FAULT (not Lovable). Nothing changed.
The brief's premise (fault in Lovable; fn_company_score_mark_dirty harmless) is wrong. Rolled-back probes on Smarando
(C962), 30 Sep:
- update usp_notes (changed value)        -> ERROR malformed array literal: "wedge"
- update research_stage (valid enum cast) -> ERROR malformed array literal: "research_stage"
- update last_refreshed = current_date     -> ERROR malformed array literal: "last_refreshed"
- no-op update (industry = industry)       -> ok
CAUSE: fn_company_score_mark_dirty (migration 137, F22B.1, written by me on 22 Sep), fired by trg_company_score_mark_dirty
AFTER UPDATE ON companies FOR EACH ROW (no column list). It declares `changed text[]` and appends with
`changed := changed || 'research_stage'`: the untyped literal makes Postgres pick array || array and parse the word as an
array literal. All six branches (research_stage, company_size, insurance, wedge=usp_notes, country, last_refreshed) fail
whenever that field actually changes. The error is raised BEFORE the company_scores UPDATE, so "company_scores has 3
rows" does not make it harmless. The 28 Sep usp_notes probe almost certainly wrote an unchanged value, so no branch ran.
i145 and i156 already describe exactly this.
IMPACT: since 22 Sep 23:20 UTC NO research field on ANY company can be changed, from Lovable or through the MCP.
PROPOSED FIX (not applied, needs Brad's word; it is a database change): cast every literal, e.g.
`changed := changed || 'wedge'::text` (or array_append(changed, 'wedge')) in all six branches, one migration, then
re-run the four probes above expecting ok. No data change is needed.
The array columns category / insurance_product_types / merged_from_refs are not involved in this error.

## Task 5 — DATABASE DONE (UI: Lovable message after Task 4)
EVIDENCE: migration 151 (schema_migrations 20260930152834).
- contacts.is_blocked boolean NOT NULL DEFAULT false, contacts.blocked_at timestamptz.
- fn_evaluate_gates: 'recipient_blocked' is an ABSOLUTE refusal placed directly after dnc_or_opted_out, above
  contact_parked and every discretionary gate. PROOF the rest is unchanged: new md5 bd344049…; the same definition with
  the new 7-line block removed hashes to 18099d27…, identical to the pre-batch function.
- refusals.reason_code check extended with 'recipient_blocked' (otherwise the drafter's refusal insert would fail).
  FINDING: the check also lists 'company_archived' (emitted by the drafter, not the gate function), so there are 13
  codes in use, not the brief's 12; 14 with the new one.
- NO BACKFILL. is_blocked = true on 0 contacts.
- VERIFY, refusal counts per reason_code, 1,023 live contacts × {chaser, initial_message}, before vs after: EVERY
  contact's code identical (0 rows changed). recipient_blocked = 0. Totals unchanged: chaser PASS 727,
  group_sibling_engaged 70, contact_parked 67, dnc 67, pending_ruling 41, thread_text_missing 23, promise_of_quiet 17,
  contact_replied 9, allowance_exhausted 2; initial_message PASS 761, group 70, parked 67, dnc 67, pending 41, quiet 17.
- SOURCE for the later backfill (NOT done): 260928_salesnav_inbox_run1/2.json, 4 threads with
  restriction=MEMBER_BLOCKED_BY_RECIPIENT, participants[] EMPTY in all 4 (identified only by the annotated 'who'
  field). In Supabase: Alexandra Asanache (P093, Lenovo) EXISTS; Beat and Elias (mobileup) and Manuel (Jacob) do NOT
  exist as contacts, so they cannot be flagged until they are created.
- TS types regenerated after 151 (is_blocked, blocked_at, v_draft_company_flags, fn_company_already_approached present).
