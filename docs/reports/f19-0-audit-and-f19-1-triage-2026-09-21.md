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
