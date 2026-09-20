# F18 checkpoint 1 — STOPPED for Brad at F18.3 — 2026-09-20

Nothing sent, nothing approved, no phantom launched, no Make scenario or PhantomBuster agent edited.

## 0. The two functions whose deploy agent stopped
| Function | Live | Intended | Verdict |
|---|---|---|---|
| generate-draft-from-context | v41, ezbr 974e8dc8… (identical to the 18 Sep spacing deploy) | sign-off fix (no "Oli" nickname) | **NOT LIVE.** This is why new drafts kept signing "Oli" after 114 and Cowork needed 115. It will keep happening each 06:15 run until deployed |
| ai-edit-draft | v9, new hash b1c55860… | sign-off fix | Deployed by the agent before it stopped. Content NOT yet verified byte-for-byte against the repo |
Migration 115 (Cowork) recorded as a file from schema_migrations and committed, not re-applied.

## F18.1 i092 — THE MEASURED CAUSE IS DIFFERENT FROM THE BRIEF
**The drafter does not count drafts as sent.** Its context is already built from Sent rows and Replies only
(`allPrev` filter in generate-draft-from-context), and the routing matrix counts Sent rows only.
**What advanced the 126:** one inline `execute_sql` in the 4 Sep migration session (transcript ed6ff042,
entry 651, 16:15:32 UTC, landing in audit_log at 16:15:34). Its `ob` CTE took
`max(touch_date) filter (where touch_type='Connection request') last_cr` from SENT rows and folded it into
`last_out`; the statement `update cs set state = case … when chasers = 0 then 'awaiting_reply'` then marked
every contact with a sent CONNECTION REQUEST and no message as awaiting a reply. It was never a file, which
is why nothing in the repo shows it. It was mine. All 126 have a Sent CR and zero sent messages.
Oliver's symptom ("three drafts, now a closing chaser") is the second half: 15 contacts got system-made
InMail Chaser 1 rows on 3-4 Sep off that state (P003 P007 P038 P041 P042 P054 P055 P056 P057 P059 P060 P062
P084 P551 P554). **All are already Cancelled/superseded** (the F15.3 repair). None is at Draft or Approved,
so (d) had nothing to supersede.
- (b) Dry run, rolled back: 126 targets; fn_chase_candidates 18→18, fn_cold_inmail_candidates 108→108,
  fn_first_message_candidates 43→43, fn_chase_exhausted 0→0, fn_send_ready_contacts 100→100, all arrays
  identical; fn_evaluate_gates outcomes identical. **Zero newly eligible.** Then applied (migration 116):
  126 contacts → chase_state none, chase_next_due_at null, each logged before/after in migration_audit
  (phase f18_1_chase_state_repair; refs listed there). Includes P673 de Groot: only his state flag changed,
  his held draft was not touched.
- (e) Regression views, both read 0: v_regress_chase_state_without_sent_message,
  v_regress_chaser_without_sent_initial (corrected in 117: 21 of its first 22 hits were Oliver's own SENT
  hand-history chasers whose opener was on another channel).
- (a)(c) Lovable: NOT done. Prompt still owed for getOutreachThreadFn / contactOutreachFn and the counters.

## F18.2 Reply sweep
Migration 117: `review_queue` (the single F18.9(b) queue), `fn_reply_candidates`, team_settings.reply_sweep_per_run=5.
The 14 replied contacts today: 9 held in the review queue (2 answered by hand: Mian, Destailleur; 5 company
promoted to Monday: Brunner, Torsting, Ruoppa, Ginat, Serres; 2 where a sent Follow up shares the reply's
date so order is unknowable: van Vuurde, Stiemert). 5 are sweep candidates; **only ONE passes the gates:
Alejandro Plater, A1, replied 11 May (132 days ago).** The other four stop at company_not_deep_researched
(reply_ignores_research_gate is off). The brief's "eight pass every gate" is not what the data shows.
Route 5 is written into chase-engine (local source). **NOT deployed, (c) NOT proven, r7 stays RED.**

## F18.3 STOP — the Make side can leave a send with no terminal status
Full branch report: docs/reports/f18-3-make-callback-branches-2026-09-20.md. Scenario 9714524 has no
branches at all: webhook → one HTTP POST. A row stays at Scheduled when: the JSON body fails to build
(exitMessage spliced in unescaped; errored 4 times on 26 Aug); the function returns 4xx/5xx
(stopOnHttpError on, incomplete executions off: bundle discarded, no retry); an unknown phantom_run_id
(function returns 200 "orphan", writes nothing; the run id is saved only AFTER launch, so a fast callback can
race it); or PhantomBuster never calls back. Once the row is found every outcome is terminal.
**fn_claim_send_slot is unchanged.** With a callback-gated queue, each of those paths costs the full
10-minute timeout. Brad's call: accept that, or fix the race first (save phantom_run_id before launch is
impossible; the fix is for the callback to retry an orphan, or for the sender to pre-register the row).
(d) Verified from the code: with an empty queue a first send launches immediately (claim inserts
not_before = now, returns launch_now true). 109 stays unapplied.
Flag: the scenario blueprint hardcodes a Bearer token (a fourth static-bearer location, not in F17.1's list).

## Running in the background when this was written
F18.5 improvement log import (118); F16.4 + F16.5 (119, 120). Their reports land in docs/reports/.

## Verification
phantom_run_id 2. Scheduled 0. Approved-unsent 21, nothing superseded by me. Watchers: all three active,
4-hourly, no gaps or errors in 48 h (12-13 runs each). Make: 23,062 of 30,000 used, 6,938 left, resets
25 Sep; ~875/day leaves ~2,700 spare.
Refusals by reason_code, start of batch → now: group_sibling_engaged 9→9, promise_of_quiet 3→3,
pending_ruling 45→45, company_not_deep_researched 1529→1529, dnc_or_opted_out 6→6 (F16.4 in flight),
thread_text_missing 204→204. No change caused by 116 or 117.

## Not started
F18.4, F18.6, F18.7, F16.6-F16.12, F18.9 UI prompts, the F18.9(j) table. Out of scope as instructed:
i107, i001, the five held wrong-channel drafts, the four duplicate Initial messages.

## i-number status
i092 cause located and state repaired; Lovable half owed. i067 drafter fix NOT live (deploy owed).
i096/i053/i094/i100 unchanged since F17. i105, i003, i071, i048: not started.
