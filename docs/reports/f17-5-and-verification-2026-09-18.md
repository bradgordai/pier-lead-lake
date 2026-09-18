# F17.5 (hand-written row, i100) and verification V1-V5

2026-09-18. Read-only: SELECTs, log reads, Make list/get only. Nothing written to the database, no Edge Function called, no scenario run. All checks taken between 10:50 and 10:57 UTC (11:50-11:57 BST).

**Timing caveat.** The brief asks for watcher runs "since 11:04 UTC". At the time of the checks it was 10:57 UTC, so 11:04 UTC had not happened yet. If 11:04 **BST** (10:04 UTC) was meant, the answer is the same: no watcher has run since 08:06 UTC.

---

## Part A

### V1. Edge Function calls from the app since 10:00 UTC

`function_edge_logs` (the request log with status codes) holds **no request at all after 09:28:51 UTC**. So by that log, since 10:00 UTC: **0 calls, 0 x 200, 0 x 401, 0 other**, for all six functions.

But `function_logs` (the functions' own console output) shows one execution the request log has not recorded:

| Time (UTC) | Function | Evidence | Auth |
|---|---|---|---|
| 10:27:37-10:27:46 | generate-draft-from-context (deployed v40) | `sender_resolved` Oli, `regenerate_superseded`, `sentinel_call` succeeded, `draft_created` lint 100 | No auth event logged. `authorize.ts` logs nothing when the **scoped secret** matches, so this was a scoped-secret call, not a JWT. |

It completed and created a draft, so it returned 200 in practice, but the status code and caller network are not in the logs yet (the request log seemed to lag; re-check later). It was a regenerate (it superseded an older touch for contact `b97c3cc9`), which is an app-style action, but I cannot prove the caller was Lovable.

Just before the window, for context:

| Time (UTC) | Function | Status | Caller network | Auth event |
|---|---|---|---|---|
| 09:28:43-09:28:51 | ai-edit-draft (v8) | **200** | Cloudflare, Inc. | **`deprecated_secret_used`** (MAKE_SHARED_SECRET) |

Auth events across the whole of today: `jwt_authorized` **0**, `jwt_rejected` **0**, `jwt_not_team_member` 0, `deprecated_secret_used` **1** (the 09:28 ai-edit-draft call). No 401 on any function today.

Conclusion: **no call from the app has yet gone through the new JWT path.** The one in-window call used the scoped secret; the one just before used the deprecated shared secret. send-approved-draft, capture-and-classify-reply (since 08:06), parse-companies-query and enrich-company-websites: no calls attempted since 10:00 UTC.

All-day request log by function, for reference (all 200): capture-and-classify-reply 140 (08:06:00-08:06:06, Make), update-contact-on-cr-accepted 210 (08:06, Make), upsert-contact-from-sales-nav 2 (08:06, Make), generate-draft-from-context 15 (06:15-08:06, cron/EF-to-EF), chase-engine 1 (06:16), generate-daily-insight 1 (08:00), ai-edit-draft 1 (09:28).

### V2. outreach_log counts (10:50 and again 10:56 UTC)

| Check | Value | Expected |
|---|---|---|
| `phantom_run_id` not null | **2** | 2 |
| `send_status = 'Scheduled'` | **0** | 0 |
| `send_status = 'Ready'` | **0** | - |
| `draft_status='approved'` and `send_status in ('Draft','Ready')` | **21** | 22 then 21 |
| rows in `send_queue` | **0** | - |

21 is fully explained by Peretti. Alexander Peretti had three open Chaser 3 drafts; two were set to `superseded` / `Cancelled` with reason `duplicate_open_draft` at **10:27:58 UTC (11:27 BST, not 11:40)**: `c3983be2` (created 18 Sep 06:15) and `2fbeb042` (15 Sep). `1943fccd` (17 Sep) remains `approved` / `Draft`. One of the two superseded rows was the approved one, hence 22 to 21.

### V3. Make watcher scenarios

All three are webhook-triggered ("immediately"), not clock-scheduled in Make. Their rhythm comes from PhantomBuster posting to the hook every four hours.

| Scenario | Id | Active | Normal slots (UTC) | Executions today | Genuine run since the flush? |
|---|---|---|---|---|---|
| Pier Sales Nav Watcher | 9589633 | yes | 00/04/08/12/16/20 :01 | 7, all between 08:05:59.789 and 08:06:00.033, all success | **No.** Next slot 12:01 UTC |
| Pier Connection Watcher | 9590745 | yes (1 incomplete execution in its DLQ) | 03/07/11/15/19/23 :04 | 7, all between 08:05:59.818 and 08:06:00.054, all success, 62 ops each | **No.** Next slot 11:04 UTC |
| Pier Inbox Watcher | 9704543 | yes (1 incomplete execution in its DLQ) | 03/07/11/15/19/23 :30 | 7, all between 08:05:59.863 and 08:06:00.098, all success, 82 ops each | **No.** Next slot 11:30 UTC |

Before today the last runs were 17 Sep 04:01 (Sales Nav), 03:04 (Connection), 03:30 (Inbox). Exactly seven four-hour slots were missed per scenario, and seven executions per scenario fired within 300 ms of each other at 08:06 UTC: that is the queue flushing, not a scheduled run. **No watcher has had a genuine execution since.** The flush cost about 7x62 + 7x82 + 12 = 1,020 operations.

The `from` filter on `executions_list` was ignored by the API (it returned the full history), so the statement rests on reading the newest entries of each list.

### V4. Make operations

From `organizations_get` (org 1721244, "Nailed IT AI", Pro):

- Plan allowance 20,000 + top-up (`operationsExt`) 10,000 = **30,000**
- Used this period: **21,025**
- Remaining (`unusedOperations`): **8,975**
- Period: 25 Aug 11:16 UTC to **25 Sep 11:16 UTC**; auto-purchase off.

At the normal rate (Connection 62 x 6 + Inbox 82 x 6 + Sales Nav about 10/day = about 875 ops/day) the seven days to reset need about 6,100. That fits in 8,975, with roughly 2,800 spare. Another flush of queued runs would eat into that.

### V5. Not verified, and why

1. **Status code and caller of the 10:27 UTC generate-draft-from-context call.** Present in `function_logs`, absent from `function_edge_logs` when checked.
2. **Whether any call came from the Lovable app specifically.** The function request log carries no user agent, origin or referer. Only the caller's network (Cloudflare for the 09:28 call) is visible. The auth events are the reliable signal, and there are no JWT events.
3. **A genuine watcher run after the flush.** None had happened by 10:57 UTC. 11:04 UTC (Connection), 11:30 (Inbox) and 12:01 (Sales Nav) are the first chances.
4. **What the two DLQ (incomplete) executions are.** Not opened; listing them needs a different tool and they are outside the brief.
5. **That production capture-and-classify-reply matches the local file.** The local header says v22; I did not pull the deployed source. Part B (e) is reasoned from the local file.
6. **Whether the Inbox Scraper can see a Sales Navigator InMail thread at all.** See (e).
7. **Whether Pelzer's InMail actually cost a credit** (Open Profile InMails are free). Only Oliver or LinkedIn can say.

---

## Part B. F17.5, the hand-written row (i100)

Row `51a5f9cb-c7f9-4f8a-b8bd-0d3bae6908ff`, created 17 Sep 15:15:24 UTC, audit source `manual`. Contact Frank Pelzer `27f4e026-5026-48e2-9125-882deb924266` (P858), Vodafone Germany (C307, Deep research done), connection_status `Not connected`.

Compared with `69f0ae51` (Medion, InMail Chaser 1, `phantom_run_id` set, sent 9 Sep through the system) and with fill rates over all 819 Sent non-reply rows.

### (a) Column by column

| Column | Pelzer | Normal system-sent row | Does a reader depend on it? |
|---|---|---|---|
| team_id | set | set | yes (every gate and candidate query). Fine |
| contact_id / company_id / contact_ref | all set (P858) | set | yes. Fine |
| channel | `LinkedIn inMail` | same | yes: `fn_chase_candidates` counts per channel; ledger function checks it. Fine |
| touch_type | `Initial message` | `Chaser 1` | yes. Fine |
| send_status / draft_status | `Sent` / `sent` | same | yes. Fine |
| sent_at_actual | 2026-09-17 14:00:00+00 (round figure, hand-entered) | exact callback time | yes: `fn_apply_send_effects` refuses without it; `v_sent_touches.sent_on` and `fn_chase_candidates` prefer it over touch_date. Fine |
| touch_date | 2026-09-17 | set | yes: the inbox sync's same-day match uses it. Fine |
| sent_body / message_body | both set, 397 chars, identical | both set | yes: `fn_evaluate_gates` `thread_text_missing`, drafter no-repetition, inbox sync dedupe. Fine |
| subject_line | set | set | display only |
| sent_by | `Oliver` | NULL on the phantom row; set on 781 of 819 | display only |
| **created_by** | **NULL** | `Oliver Muller` (set on only 12 of 819) | no reader found. Cosmetic |
| **external_key** | **NULL** | NULL on the phantom row too; set on 10 of 819 (inbox-filed rows) | yes, the inbox sync's first dedupe check. See (e) |
| **thread_id** | NULL | NULL on all 819 Sent rows | none in practice |
| thread_url | set, but to a **Sales Navigator lead URL** (`/sales/lead/...`), not a conversation URL | NULL | inbox sync's secondary match compares it with the scraped thread URL; this value will never equal one, and the sync overwrites it when it matches on text. Harmless but wrong content |
| **phantom_run_id** | NULL | set | no gate reads it; `v_sent_touches` exposes it. Correctly NULL for a hand send |
| **observed_or_inferred** | **`observed`** | `observed` | It was NULL when Oliver wrote the row; today's F17 backfill (10:24:49 UTC, source `system_backfill_f17`) stamped it `observed`. The check constraint already allows `recorded_by_hand`, which is the honest value. No gate reads it yet; it is a provenance label |
| touch_id | `cc-20260917-P858-inmail-01` | `T295` (774 rows are `T<n>`; 45 use prefixes such as `inbox-`, `cr-`, `chase-exhausted-`) | only uniqueness matters (unique constraint). Not the `hand-<YYYYMMDD>-<ref>` format; leave it, nothing parses it |
| draft_language | `DE` | NULL | drafter language resolution reads prior messages. Better than normal |
| outcome / next_action / next_action_date | `Awaiting reply` / text / 2026-09-24 | legacy text | not read by the chase engine |
| migrated_at / legacy_source / migrated_legacy | NULL / NULL / false | set (migrated row) | correct for a new row |
| lint_score, path, pre_lint_pass, voice_stack_versions, draft_narrative | NULL | NULL on nearly all Sent rows | none |

**On the row itself nothing a gate, view or the chase engine depends on is missing.** The gaps are: `observed_or_inferred` should be `recorded_by_hand`, `created_by` is empty, and `thread_url` holds the wrong kind of URL. The real gaps are outside the row: the contact's chase fields (b) and the ledger (d).

### (b) Is the day-seven follow-up scheduled off 17 Sep?

Contact now:

| Field | Now | Should be |
|---|---|---|
| chase_state | `none` | `awaiting_reply` |
| chase_last_outbound_at | NULL | 2026-09-17 |
| chase_next_due_at | NULL | 2026-09-24 |
| chase_scheduled_for | NULL | NULL (unchanged) |
| last_contacted | 2026-09-17 | 2026-09-17 (Oliver set this by hand at 15:15:26) |
| outreach_status | `Contacted` | `Contacted` (set by hand) |
| chaser_count | 0 | 0 |

**`fn_apply_send_effects` was never run for this row.** There is no `send_effects` line in `audit_log` for it; the only entries are the manual create and today's backfill. It is normally called by send-approved-callback, which a hand send never reaches.

Does that stop the chaser? **No.** The chase engine does not read `chase_next_due_at`. `fn_chase_candidates` works from `outreach_log`: last Sent non-CR message on the contact's route channel, plus `chase_interval_days` (7). Pelzer is not in the candidate list today and will enter it on **24 Sep** (17 + 7), so the 06:15 UTC chase run on 24 Sep should draft his chaser. I ran `fn_evaluate_gates(..., 'LinkedIn inMail', 'chaser')` (read-only): **no refusal**. `fn_cold_inmail_candidates` correctly excludes him because a Sent message exists, so he will not be sent a second opener.

What the missing call costs is the display: the contact card and anything reading `chase_state` / `chase_next_due_at` shows "none / no date" until the engine drafts the chaser and sets `chaser_drafted`.

`fn_apply_send_effects` is **safe to call by hand**: it touches only this row's `touch_type`/`touch_date`, the contact's chase fields, and one audit line; no HTTP, no ledger, idempotent. EXECUTE is granted to `postgres` and `service_role` only, so it works from the SQL editor, not from the app. Suggested fix for Pelzer (not executed): `select public.fn_apply_send_effects('51a5f9cb-c7f9-4f8a-b8bd-0d3bae6908ff','manual-send');`

### (c) Sequence position of the next draft

`fn_chase_candidates` counts Sent rows on `LinkedIn inMail` for the contact: 1 message (the initial), 0 chasers. He is `Not connected`, so route `cr_not_accepted`, channel `LinkedIn inMail`. The next draft is **chaser_number 1, cap 1, `is_final = true`**: the one and only InMail chaser. It is drafted as `Chase` and renumbered to `Chaser 1` by `fn_apply_send_effects` when sent. After that, `allowance_exhausted`. If he accepts a connection request first, the route flips to DM with a cap of 3 and the DM count starts at 0.

### (d) InMail credit

**No charge exists.** `inmail_credit_ledger` has three rows in total: opening balance 95 (27 Aug), manual adjust +34 to 129 (3 Sep), and one `send` -1 to **128** (9 Sep, the Medion row). Nothing references `51a5f9cb`, nothing is dated 17 Sep. Latest `balance_after` = **128**; it should be 127 if the InMail cost a credit.

`fn_ledger_inmail_send(<row id>)` does the charge and is idempotent (one `send` row per outreach_log id; it also returns NULL for non-InMail rows). Its note text is hard-coded as "InMail dispatched via send-approved-draft". Not executed.

### (e) Will the next sync duplicate it?

Source read: `supabase/functions/capture-and-classify-reply/index.ts` (local, v22), function `fileOwnMessage`. It is the only function that inserts Sent message rows from outside the send path. (upsert-contact-from-sales-nav inserts Connection request rows only; chase-engine inserts `Other`-channel "chase exhausted" markers only.)

The order of checks when the inbox shows a message from Oliver:

1. `external_key` = sha256(threadUrl | lastMessageDate | body). If a row has that key, duplicate. Pelzer's row has no key, so this misses. The key cannot be produced by hand.
2. **Same-day text match:** rows for the same `contact_id`, `touch_type <> 'Reply'`, `touch_date` = the message's **UTC date**; a row matches if the **first 40 characters of `sent_body`** (falling back to reply_content, then message_body), with whitespace collapsed and lower-cased, equal the first 40 characters of the scraped message. On a match it does **not** insert: it writes `external_key` and `thread_url` onto the existing row.
3. Otherwise it inserts a new row: `touch_id = inbox-<uuid>`, channel hard-coded **`LinkedIn DM`**, touch_type `Follow up` (a prior Sent row exists), and sets `last_contacted`.

Pelzer's row: `touch_date` 2026-09-17, which is the UTC date of a 14:00 UTC send; `sent_body` starts "Hallo Frank, ihr verkauft zusammen mit der Recommerce Group". **If the scraped text starts with those same 40 characters, the row is matched and no second row is inserted.** I expect a match, provided Oliver pasted the text rather than retyping it and the scraper does not put the subject line in front of the body.

If it did not match, the damage would be a second Sent row on the **wrong channel** (LinkedIn DM). For a not-connected contact the chase route reads InMail rows only, so the chaser date would not move, but the thread would show the message twice and "prior touches" would be overstated.

Evidence so far: the 08:06 UTC flush pushed 140 inbox messages through the function and neither matched nor duplicated Pelzer (his `external_key` is still NULL, no new `inbox-` row since 15 Sep, nothing in `unmatched_replies`). So the scraper has not surfaced that thread at all. It reads the 20 newest threads of the normal LinkedIn inbox; an InMail sent from Sales Navigator may never appear there. That is unverified, and it is the better outcome.

**The single field that prevents a duplicate is `sent_body`: the exact text as sent**, with `touch_date` equal to the UTC date of the send. Both are already right on Pelzer's row, so nothing needs filling to protect it. `external_key` is not something Oliver can fill.

One weakness to note for later: `fn_apply_send_effects` rewrites `touch_date` to the **London** date, while the sync compares the **UTC** date. A send between 23:00 and 24:00 UTC in summer would land on different days and slip past the same-day match. Rare at Oliver's working hours.

### (f) Procedure

Written to `docs/procedures/recording-a-manual-send.md`: six short steps and one SQL template (insert, then `fn_apply_send_effects`, then `fn_ledger_inmail_send` for InMails). It also tells Oliver to reject any open draft for the same person first, because inserting a Sent row does not cancel open drafts (the one-open-draft trigger only reacts to new Draft/Ready rows). Nothing in it was executed.

### Suggested repair for Pelzer (for Brad to approve; not run)

```sql
update public.outreach_log
   set observed_or_inferred = 'recorded_by_hand', created_by = 'Oliver', thread_url = null
 where id = '51a5f9cb-c7f9-4f8a-b8bd-0d3bae6908ff';
select public.fn_apply_send_effects('51a5f9cb-c7f9-4f8a-b8bd-0d3bae6908ff', 'manual-send');
select public.fn_ledger_inmail_send('51a5f9cb-c7f9-4f8a-b8bd-0d3bae6908ff');  -- only if the InMail cost a credit
```
