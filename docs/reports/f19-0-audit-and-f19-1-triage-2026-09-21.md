# F19.0 audit and F19.1 triage — 2026-09-21

## F19.0
(a) **Lovable is 8 screen changes behind.** Cowork's five are confirmed. Three more were never even written
as prompts, only as one-liners in reports: the "queued" Send now status (f17-send-spacing report), the
connection-conflict view (f17-4 report), the company_archived refusal label (f18-8 report).
(b) Lovable MCP: REACHABLE from this session (project ready, agentFinished true, SHA 09bd77f9f798…) and
REACHABLE from a sub-agent (read tools verified). The three-day gap was not a reachability fault. It was
mine: I wrote prompts into report files and called that delivery.
(c) TEST_MODE on send-approved-draft = **false** (live). Read without risk: a call naming an already-Sent
row returns `not_sendable` plus `test_mode` at the first check, before any gate or launch code. Not changed.
(d) outreach_log d5b74aaa…: NOT a lost prospect send. It was the F7 controlled InMail test to Brad's own
profile (contact ref TEST-BRAD-INMAIL). audit_log shows created 08:34:23, send_completed 08:35:15, deleted
08:38:00 on 8 Sep; migration_audit phase `controlled_send_cleanup` logs `test_row_deleted` and
`test_contact_deleted` at 08:38:00. No migration removed it; a logged manual cleanup did.
(e) Intact. Moeller P703: Initial message, LinkedIn DM, Sent/sent, run id present, sent 10 Sep 11:40:41,
651 chars; contact awaiting_reply / In conversation. Fischer P365: Chaser 1, InMail, Sent/sent, run id
present, 9 Sep 12:57:28; contact exhausted / Contacted (InMail cap 1), correct.
(f) cr_accepted_at reads 12 (152 Accepted with no date). Migration 121 written as ALREADY APPLIED, committed,
not run. Flag: the stamp trigger from 120 will re-stamp the next 'Already connected' -> 'Accepted' relabel.

### Deviations from the brief's measured state
- "126 contacts with a chase_state and zero sent messages": **already repaired on 20 Sep (migration 116).**
  The four chase states now read 0. 49 contacts still hold a state with no sent message: 48 cooldown (set
  by the 4 Sep migration from Oliver's dates) and 1 replied (Thakooree, inbound only). Both are legitimate.
  F19.5 (b) (d) (e) were delivered as F18.1; see f18-checkpoint-1 report. Only (a) and (c) remain, in Lovable.
- Approved-unsent is **23**, not 21. Two approvals since 20 Sep. Nothing superseded by me.
- Refusals today: company_not_deep_researched 1533, thread_text_missing 210, pending_ruling 45,
  group_sibling_engaged 9, company_archived 6, promise_of_quiet 3, dnc_or_opted_out 0. This is the F19
  baseline. (+4 and +6 since 20 Sep are the 06:15 runs.)

## JWT path, verified from DEPLOYED source, function by function
send-approved-draft v17 yes · ai-edit-draft v9 yes (byte-identical to repo, sign-off fix live) ·
generate-draft-from-context v41 yes (still carries the Oli nickname: fix not live until F19.4) ·
capture-and-classify-reply v25 yes · enrich-company-websites v15 yes · parse-companies-query v5 yes ·
**generate-daily-insight v17 NO**: its Lovable caller keeps its secret.

## F19.1(a) TRIAGE — written before anything was fired
| # | Prompt | Verdict | Why, from the current Lovable source (commit 09bd77f) |
|---|---|---|---|
| 1 | F17.1 security swap | NEEDS REWRITE | Still needed: 8 identical copies in 7 files, two module-level. Rewrite because the auth middleware does not expose the token (handlers must re-read the request header), and the daily-insight caller must keep its secret |
| 2 | F16.3 Today replies | STILL VALID | `RepliesNeedingAnswer.tsx` splits on `source`, collapses non-live rows behind `migratedOpen=false`, and the header badge counts live rows only |
| 3 | F17.3 Approve UI | NEEDS REWRITE | Clause 1 mostly done already (Approve is disabled while pending; "Approve anyway" in the lint dialog is not). Clause 2 STILL NEEDED (`revisionSnapshot.ts` reads last+1). Clause 3 ALREADY TRUE (a revision is written only when the body differs): dropped. Clause 4: the real double-write is the textarea's silent save-on-blur racing the Approve click, two concurrent updates |
| 4 | F18.5 Improvement Log tab | NEEDS REWRITE | Drafted with table definitions in it. Rewritten to outcomes. Tab does not exist yet |
| 5 | F17 B2 "chaser N of M" | NEEDS REWRITE | **My diagnosis was wrong, the remedy stands.** M is one global `team_settings.chaser_cap`, not "the channel of earlier touches"; N is the digit parsed out of the touch_type label, never clamped. The header chip (`cadence.ts`) is already computed from sent rows and clamped. Merged with F19.5(c), fired once |
| 6 | "Queued" Send now status | STILL VALID, now a LIVE BUG | `useSendDraft.ts` treats every status except sent / capacity_exceeded as failure. Since spacing went live on 18 Sep a queued send shows "Not sent: queued" and is never polled. Folded into F19.3(e) |
| 7 | Connection-conflict view | SUPERSEDED | Folded into the F19.9 Needs review screen |
| 8 | company_archived label | STILL VALID | Folded into F19.9(d) |
Nothing is CONTRADICTED by later work. Item 5 is flagged because the brief's F19.5(c) wording repeats my
wrong diagnosis; the prompt fired describes the outcome, which is unaffected.
Other facts that change prompts: the Outreach category list already has a `replies` key
(`src/lib/outreachCategories.ts`), so F19.6(b) is a change to an existing category, not a new one. Thread
selects are display-only: no thread content is sent to any Edge Function, so F19.5(a)'s Lovable half is
about display and counters, not model context. List screens already paginate with counts.

## Lovable log (appended as each message ships)

### 1. F19.1(c) security swap — SHIPPED TO LOVABLE, RENDER NOT VERIFIED — STOPPED HERE
- Plan Mode first (1 credit, no code): Lovable's plan matched the brief exactly (six files, new server-only
  helper `src/lib/queries/edgeAuth.server.ts`, both module-level consts deleted, insights-daily untouched,
  no database change). Plan commit e6f9c2160580 (adds only .lovable/plan.md). Approved and implemented.
- **Lovable commit 7dc76a45f957db65a1e588ada58423596911cf47.** SHA before 09bd77f9. Lovable reports
  typecheck and build clean, and exactly ONE literal left, in insights-daily.functions.ts, as instructed
  (generate-daily-insight v17 still takes the secret only).
- NOT VERIFIED: the rendered screens and that AI edit / Regenerate / Send now / enrichment / query parser
  still authenticate. The preview redirects to the app's sign-in page. Chrome has Brad's credentials
  autofilled; signing in on his behalf is not something I may do. **Per F19.A(i) nothing further was fired.**
  The first proof will be `jwt_authorized` in the Edge Function logs when Brad or Oliver presses Regenerate
  or AI edit in the preview.
- NOT PUBLISHED. The change is in the Lovable project and its preview. Whether the published app Oliver
  uses picks it up without a Publish/Update click was not established. I did not publish.
- SECRET EXPOSURE, MINE TO REPORT: Lovable's own search command echoed the literal into its reply, so the
  value is now in this session's transcript. It was already in Lovable's git history. Rotate
  INTERNAL_APP_SECRET after the swap is verified. The three pg_cron jobs and the Make blueprint carry a
  literal too and will need the new value. The value is 64 hex characters, not 48: every earlier report
  that said "48-hex" was wrong, and tests/no_static_bearer_test.py would have MISSED it. Test widened to
  40-128 hex today.
- RLS audit (F19.A(e)): not needed, Lovable touched no schema; its activity shows file edits only.

**Update after Brad signed in to the preview:** Today renders on 7dc76a45 with no console errors. Edge
Function auth by user token is still UNPROVEN: no `jwt_authorized` event in the function logs in the last
24 h, because nobody has pressed an action button yet, and Chrome here is read-only so I will not press one.

### 2. F19.1(d) Today replies — SHIPPED AND RENDERED
Lovable commit **ed21cc6a7db5244dfa61302250556fd8221571dc** (before: 7dc76a45). One component changed,
`RepliesNeedingAnswer.tsx`. Verified in Chrome (preview, Brad's admin scope): ONE list, header count 22,
"migrated" badge on the non-live rows, no "Migrated history" toggle, longest waiting first (Jensen 138 d,
Brunner 137, Torsting 136, Popescu 133, Plater 133 …). Before: 2 shown, 20 collapsed. The preview lags a
commit by about a minute; the first two reloads still showed the old build.
Not verifiable from SQL: the view is owner-scoped and returns 0 to the service role, so the count was read
off the screen, not the database.
FLAGS, not fixed: (1) Morten Jensen's row shows Oliver's OWN message as the reply text ("…All the best,
Oliver"): an outbound logged as a Reply. (2) The list is 22, not the 6 the F16.3 report measured on 15 Sep;
most of the extra rows sit at companies promoted to Monday, which F19.6 routes to the review queue.

### CHECKPOINT F19.1(h)
Shipped and rendered: (c) security swap 7dc76a45, (d) Today replies ed21cc6a. Lovable has advanced 3 commits
(plan file, swap, replies). Left in the backlog: (e) Approve UI, (f) Improvement Log tab, then the chaser
footer (merged into F19.5c), the queued-send status (F19.3e), company_archived label and the conflict view
(F19.9). Total 8, not more than 8, so continuing.

### 3. F19.1(e) Approve UI — SHIPPED, RENDERED, BEHAVIOUR NOT EXERCISED
Lovable commit **639e4f4a7a75e1b07246a4d2fc1110929bb0a359** (before: ed21cc6a). Files: `revisionSnapshot.ts`
(revision_number left out of the insert; the unchanged-text skip kept) and `DraftEditor.tsx` (Approve,
Reject, Save and Send now wait for any in-flight silent save; one write per click; all four buttons plus
"Approve anyway" disabled while busy; exactly one toast per click). Clause 3 of the old prompt was dropped
as already true. Database side is compatible: the BEFORE INSERT trigger from migration 110 fills
revision_number before the NOT NULL check. Verified in Chrome: Outreach and a DM chaser draft pane render,
no console errors. NOT verified: the Approve click itself, because I may not approve anything.

### 4. F19.1(f) Improvement Log tab — SHIPPED AND RENDERED
Plan Mode first. Plan commit 902722d1. One correction made before approval: Lovable proposed 50 rows with
"Load more", which would orphan nested items across pages; changed to ranged pages of 200 against an exact
count, grouped over the full set. **Lovable commit 1dbc501a79bd6455a9d8bf5a8734b59d7b9c9729** (before:
639e4f4a). New route /improvements, 9 new files, one sidebar entry after Insights.
Verified in Chrome: header reads "109 items, 8 done"; Build wave 0 (4) and Build wave 1 (24) groups; nested
children under i031; priority/owner/category/status filters, search, Show hidden, Expand/Collapse all, Add
item; Activity panel shows the 2 imported entries; contact chips on i100 and i094. No console errors.
F19.A(e) audit: Lovable used read-only queries only. pg_policies on the three tables are unchanged from
F18.5 (team read; insert/update gated on fn_improvement_log_can_edit; no delete on improvements; no anon
grants). Latest migration is still 120. Counts unchanged: 109 / 34 / 2.
Realtime: the three tables are NOT in supabase_realtime. Lovable did not report missing events, so no
follow-up migration was applied; two people editing at once will need a refresh to see each other.
NOT verified: a write by Oliver, and Jack's read-only experience (needs their sessions).
The send_message call for this build timed out on my side after the message was accepted; it was NOT
re-sent; the result was read back with get_message.

### NOT PUBLISHED
Every Lovable change above is in the project and its PREVIEW. Lovable ends each build with "Publish your
app". Oliver works in the published app, so none of this reaches him until someone presses Publish. I have
not published: it is a public deployment and the token-auth change has not yet been proven by a real call.
Lovable has advanced 6 commits today (09bd77f9 -> 1dbc501a): 2 plan files and 4 changes.

### 5. F19.5(c) + F17 B2 "chaser N of M", fired ONCE — SHIPPED, RENDERED, NEW LABEL NOT YET SEEN
Schema re-read first (addendum 1). It corrected the brief a third time: **inmail_chaser_cap is 1, not 2**
(dm_chaser_cap 3, email_chaser_cap exists, legacy chaser_cap 2). The footer's "of 2" was the legacy single
cap, not a channel mix-up. **Lovable commit 8ed5393a09292ccdd0a0f8e37764974f728327a9** (before: 1dbc501a).
Files: drafts.functions.ts, DraftEditor.tsx. M = the cap for the draft's own channel; N = 1 + chasers
already SENT on that channel (Sent, not superseded/rejected, duplicate_of empty, not inferred); over cap
renders red "over cap, should not exist"; header chip and footer now share one calculation; unsent rows in
the thread carry an "unsent" marker (F19.9c). Verified in Chrome: the draft editor renders (Marvin in 't
Groen, DM Chaser 3, signs "Oliver"). The chip still showed the OLD wording at that moment, consistent with
the preview's 1-2 minute rebuild lag; to be re-read on the next pass. NOT verified: a contact over cap.

### 6. F19.3(e) send queue strip on Today + "queued" Send now status — SHIPPED, CORRECTION IN FLIGHT
**Lovable commit d7bd342c90d3106d1292c147a0732a6d3014e493** (before: 8ed5393a). New
`SendQueueStrip.tsx` under the heartbeat strip reading v_send_queue_status (Sending now / Queued, expandable
/ Sent today / Stuck in red with a Release queue button and the line "Frees the queue. Check LinkedIn
before resending."), 30 s refresh. Send now: "queued" is now a calm success toast with the time and
position and is watched without the 4 minute give-up; "refused" shows reason_human; the DM-limit wording is
only used for DMs. This closes the live bug from 18 Sep where a queued send read "Not sent: queued".
DEFECT I FOUND BY READING LOVABLE'S CODE: it validated the queue id as a UUID; send_queue.id is a whole
number, so Release would always have failed. One correction message sent (not a retry of the build).
