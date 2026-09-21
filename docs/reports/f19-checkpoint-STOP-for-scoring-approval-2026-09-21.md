# F19 checkpoint — STOPPED at F19.7(b) for Brad's approval — 2026-09-21

Nothing was sent, approved, queued or dispatched. No Make scenario and no PhantomBuster agent was edited.

## THE NUMBER THAT MATTERS
Lovable latest_commit_sha BEFORE 09bd77f9f798… AFTER **69c437725fc5104b2a01f19c5ae487c9d59ec009**.
**It advanced 10 commits:** 2 Plan Mode plan files and 8 changes.
| # | Change | Lovable SHA | Rendered in Chrome | Proven in use |
|---|---|---|---|---|
| 1 | F19.1(c) security swap (Plan Mode first) | 7dc76a45 | yes | **YES: `jwt_authorized` on generate-draft-from-context at 11:51 and 12:14 UTC, Regenerate pressed in the preview by a signed-in user** |
| 2 | F19.1(d) Today shows every reply, migrated badge | ed21cc6a | yes, 22 rows | yes |
| 3 | F19.1(e) Approve UI: one write, one toast, DB-assigned revision number | 639e4f4a | yes | no: needs a real Approve |
| 4 | F19.1(f) Improvement Log tab (Plan Mode first) | 1dbc501a | yes, "109 items, 8 done" | **YES: Brad ticked two items in it; activity recorded** |
| 5 | F19.5(c)+B2 chaser N of M, unsent marker | 8ed5393a | editor renders; new label not yet re-read | no |
| 6 | F19.3(e) send queue strip + "queued" status | d7bd342c | yes, "Send queue empty" | no: needs a queued send |
| 7 | correction: Release button id is a whole number | 69c43772 | n/a | no |
**NOT PUBLISHED.** All of it is in the Lovable project and its preview. Oliver works in the published app.
Someone must press Publish. I did not: it is a public deployment and Brad's to press.
Zero hex literals remain in Lovable source EXCEPT one, deliberately, in insights-daily.functions.ts, because
generate-daily-insight is still v17 and takes the secret only (its deploy was refused on 18 Sep).
SECRET: Lovable echoed the literal into its reply, so it is in this session's transcript. Rotate
INTERNAL_APP_SECRET; the pg_cron jobs, the Make blueprint and that one Lovable file need the new value.
The literal is 64 hex characters, not 48; the repo's bearer test is widened to 40-128.

## Still to fire at Lovable (none started)
F19.6(b) five categories with Replies split in two (cause found: empty categories are hidden; details in the
F19.6 report) · F19.9(a) Needs review screen (the review_queue table has 9 rows and NO screen: a defect) ·
F19.9(b) cr_accepted_at on the contact record · company_archived label (the map in today.functions.ts lacks
it, so it renders as raw text) · F19.7(c)(e) score on Outreach, the companies list and the company record ·
F19.8 companies-without-contacts list.

## Database and functions
Migrations applied today, each its own commit: 122 callback-gated queue, 122b its fix, 123 improvement log
housekeeping, 124 drainer + housekeeping cron. 121 is a record only (Cowork's correction), never run.
Deployed: generate-draft-from-context v41 -> **v42**, send-approved-callback v15 -> **v16**,
send-approved-draft v17 -> **v18**. HELD, being ported: chase-engine v11 and update-contact-on-cr-accepted
v19 (live code the repo lacked; result appended to the F19.6 report). generate-daily-insight: STILL v17.
Live proof the new drafter is running: a Regenerate at 12:14 UTC was refused as `company_archived`, not as
an opt-out.

## STOP: F19.7(b) needs Brad's approval. Full proposals in
docs/reports/f19-7-f19-8-scoring-and-dach-dry-run-2026-09-21.md
- Score storage, recommended: an append-only company_score table with a current-score view. Each component
  holds nullable points plus an assessed flag; total, assessed denominator, percentage and the text
  "77 of 100 assessed" are generated, so an unassessed component CANNOT be stored as zero. Sort: coverage
  tier first (denominator 60 or more), then percentage of assessed. devices_per_month never sorts.
- Contacts raise the score, recommended: a SEPARATE reachability figure beside the score, used as a
  tie-break inside 10-point bands. It is the only option that leaves the score and its denominator untouched.
- DACH dry run (no writes): 3 exact-domain matches (Ackermann, getgoods.com, toredo), 22 fuzzy for the review
  queue, 48 new, 0 rejected; 70 of 70 volume rows carry a rung (50 at E4). All three known false pairs land
  in review, none would merge. The group guard catches getgoods.com (Conrad, in Monday) and Ackermann (Otto).
  13 sourced and 3 skip decisions found. The board's score_0_100 is ALREADY a percentage of assessed.
  Lead_and_ICP_Brief.md in the repo has no section 8.1(g).
F19.8 waits on F19.7. F19.7(d): the impact of replacing priority on the six functions is in that report.

## Verification
phantom_run_id 2 · Scheduled 0 · Ready 0 · send_queue 0 · parked callbacks 0 · cr_accepted_at 12 ·
approved-unsent 23 (was 23 at the start of F19; the brief's 21 was stale; nothing superseded by me).
Regression views, all 0: chase state without a sent message, unsent chaser without a sent message on its
channel, queue row launched too long.
Refusals by reason_code, start of F19 -> now: company_not_deep_researched 1533 -> 1534 (+1, a reply
Generate pressed in the preview at 11:51) · company_archived 6 -> 7 (+1, the Regenerate at 12:14) ·
thread_text_missing 210 · pending_ruling 45 · group_sibling_engaged 9 · promise_of_quiet 3 ·
dnc_or_opted_out 0. Both changes are a person pressing a button in the preview, not this batch. The consent
layer (fn_evaluate_gates) was not modified today.
NOT re-verified today: the three Make watchers and Make operations (last read 20 Sep: all on schedule,
6,938 operations left, reset 25 Sep). Not verifiable by me: Oliver's and Jack's experience of the new tab.

## Flags raised, not fixed
- 6 of 57 migrated "Reply" rows are OLIVER'S OWN messages (Plater, Ginat, Ruoppa, Torsting, P076, P136),
  which is why the Plater reply draft is wrong and why 4 contacts sit falsely at 'replied'.
- 1,534 deep-research refusals cover only 55 contacts: something re-requests the same refused contacts.
- The stamp trigger from migration 120 will re-stamp the next 'Already connected' -> 'Accepted' relabel.
- Today still shows "Promotion rate 5433%" (F16.8) and "Connection requests 0/30" (F17.8, should be 20).
- The heartbeat strip on Today did not show "Watchers alive" when I looked; I did not investigate.

## One line per item
F19.0 done · F19.1 (c)(d)(e)(f) shipped, (g) folded into later tasks · F19.2 reported, callback made
idempotent, change is Brad's in the PhantomBuster UI · F19.3 live except the chase of a real send ·
F19.4 3 of 5 deployed, 2 being ported, daily-insight still v17 · F19.5 (b)(d)(e) were done on 20 Sep,
(c) shipped, (a) found to be display-only · F19.6 sweep written not live, Plater proven with a fault, r7
AMBER · F19.7 STOPPED for approval · F19.8 dry run only · F19.9 queue table exists, no screen ·
F19.10 done (i096 ticked, i108-i112 logged) · F19.11 not started.
i092 state repaired, counters fixed in Lovable · i096 closed · i070/i082 permanent fix shipped and proven ·
i067 fix now live in the drafter · i094, i100, i071 open · i105, i003 waiting on F19.7 · i107 parked.
