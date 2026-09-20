# F18.3 / F18.9(c): "Pier Send Callback" branch audit + Make verification

Date: 2026-09-20 (read-only investigation; nothing in Make, PhantomBuster or Supabase was changed, no Edge Function was called).
Sources: Make scenario 9714524 blueprint + execution log, Make organisation record 1721244, local source
`supabase/functions/send-approved-callback/index.ts` and `supabase/functions/send-approved-draft/index.ts`, read-only SQL on project `qzfrcfzeiagziqjnfarw`.
Secrets: the blueprint's HTTP module carries a hardcoded `Authorization: Bearer <redacted>` header. The value is not reproduced here.

## Conclusion

**Not every branch writes a terminal status.** The scenario has no branches at all (no router, no filter, no error handler), so the only path that reaches Supabase is the happy path. These paths end with the outreach_log row left at `Scheduled`:

1. Make-side: the HTTP module fails to build its body ("not valid JSON") - no request is sent.
2. Make-side: the function answers 4xx/5xx - the execution errors, there is no error handler, incomplete executions are off, so the bundle is discarded with no retry.
3. Function: `orphan` (no row with that `phantom_run_id`) - returns HTTP 200, writes nothing, Make records success.
4. Function: 400 `missing_required_fields` (no containerId), 400 `invalid_json`, 401, 405, 500 `server_misconfigured`, 500 `internal_error` (DB read or update failed) - no write.
5. Upstream of Make: PhantomBuster never posts the webhook (agent killed / timed out / webhook not set on the agent). Nothing sweeps stale `Scheduled` rows: no pg_cron job, DB function or Edge Function does it (only `send-approved-draft` writes `Scheduled`; `fn_chase_candidates` and `fn_cold_inmail_candidates` only read it).

Current exposure is nil: there are 0 rows at `Scheduled` today (Sent 876, Cancelled 162, Draft 115). The gap is structural, not a live stuck row.

## Part 1 - Scenario 9714524 "Pier Send Callback"

| Item | Value |
|---|---|
| Team / org | 586107 / 1721244 (Nailed IT AI, eu2) |
| Trigger | Custom webhook (hook 4336205, "Pier Send Callback Webhook"), instant |
| Scheduling | `immediately`, max 100 runs/min |
| Active | Yes (`isActive` true, not paused, not invalid), DLQ count 0 |
| Last edit | 2026-09-15 11:28:51Z (two edits that day, no execution since) |
| Scenario settings | sequential false, `dlq` (store incomplete executions) **false**, `dataloss` false, maxErrors 3, autoCommit true |

### Flow (whole blueprint)

| # | Module | What it does |
|---|---|---|
| 2 | `gateway:CustomWebHook` | Receives PhantomBuster's completion POST. maxResults 1. |
| 3 | `http:MakeRequest` v4 | POST to `.../functions/v1/send-approved-callback`, header `Authorization: Bearer <redacted>`, JSON-string body, `stopOnHttpError` true, `parseResponse` true. |

Body template sent to the function:

```
{ "containerId": "{{2.containerId}}", "agentId": "{{2.agentId}}",
  "exitCode": {{ifempty(2.exitCode; "-1")}}, "exitMessage": "{{2.exitMessage}}",
  "resultObject": {{ifempty(2.resultObject; "null")}} }
```

Make sends no status/outcome field of its own. The function decides Sent vs Cancelled from `exitCode` and `resultObject`.

### Branch-by-branch

| Route | Trigger | Filter | Supabase write | Can end with no write? |
|---|---|---|---|---|
| Single linear route 2 -> 3 | Any POST to the webhook | None | Module 3 -> `send-approved-callback` | Yes, see below |
| Routers | none exist | - | - | - |
| Fallback routes | none exist | - | - | - |
| Error handlers (ignore/commit/resume/break) | none exist | - | - | - |

So nothing is dropped by a filter and no exit code goes unmatched by a router, because neither exists. The ways this single route ends without a terminal write:

- **A. Body is not valid JSON, module 3 throws before sending.** `exitMessage` and `containerId` are spliced into a quoted string with no escaping; a double quote, backslash or newline in PhantomBuster's `exitMessage` breaks the body. `resultObject` is spliced raw: fine when it arrives as a JSON string or is empty (-> `null`), broken if Make ever delivers it as a parsed collection. This has happened: executions 2026-08-26 10:54, 10:55, 11:11 and 11:26 (the last one an automatic, real webhook) failed with "The provided JSON body content is not valid JSON." Failed phantom runs are the most likely to carry awkward `exitMessage` text, which is exactly when a Cancelled write is needed.
- **B. Function returns non-2xx.** `stopOnHttpError` true turns 400/401/500 into a scenario error. With no error handler and `dlq` false, the execution is not stored for retry; the bundle is gone. Repeated errors (maxErrors 3) can also get the scenario deactivated by Make, after which webhooks queue unprocessed.
- **C. Missing containerId.** Template yields `"containerId": ""`; function returns 400 (-> B). No row could be identified anyway.
- **D. Empty exitCode.** Handled: `ifempty` sends -1, function writes Cancelled. Terminal.
- **E. Function returns 200 `orphan`.** Make shows success; nothing was written (see function path 7).
- **F. Webhook never arrives.** Not a scenario branch, but the same outcome, and nothing else closes the row.

### Function code paths (`send-approved-callback/index.ts`, local source)

| # | Condition | HTTP | send_status result |
|---|---|---|---|
| 1 | Method not POST | 405 | unchanged (Scheduled) |
| 2 | `PIER_TEAM_ID` unset | 500 | unchanged |
| 3 | Not authorised (no Bearer, no valid `?auth=`) | 401 | unchanged |
| 4 | Body not parseable JSON | 400 `invalid_json` | unchanged |
| 5 | No run id in `containerId` / `container_id` / `phantom_run_id` / `runId` / `id` | 400 `missing_required_fields` | unchanged |
| 6 | Row lookup errors | 500 `internal_error` | unchanged |
| 7 | No row for (team_id, phantom_run_id) - unknown run id | **200** `orphan` | **unchanged, silently** (console log only, no audit_log row) |
| 8 | `exitCode` not finite or != 0 (includes -1, "", text) | 200 `send_failed` | **Cancelled**, send_error = exitMessage; InMail charge reversed; audit `send_failed` |
| 9 | exitCode 0 and resultObject normalises to `[]` (null, "", "null", unparseable string, non-array object) | 200 `send_skipped` | **Cancelled**, send_error `phantom_skipped_duplicate_or_empty`; draft_status left approved; audit `send_skipped` |
| 10 | exitCode 0 and non-empty array | 200 `send_completed` | **Sent**, draft_status sent, sent_at_actual now; then `fn_apply_send_effects` (failure logged, Sent stands) |
| 11 | The UPDATE in 8/9/10 errors | 500 `internal_error` | unchanged |

Notes on the function:
- Once a row is found, every exit/result combination is terminal (8, 9 or 10). There is no unrecognised-status hole: anything that is not "0 + populated array" becomes Cancelled. A real send whose resultObject arrives as a non-array object would be Cancelled (false negative) rather than left open.
- The lookup does not filter on `send_status`. A duplicate or replayed callback re-applies the write to a row already Sent/Cancelled (it can flip Sent -> Cancelled or the reverse, and re-runs `fn_apply_send_effects`). Not a "left at Scheduled" issue, but relevant if anyone replays Make executions.
- Orphan risk is real by construction: `send-approved-draft` writes `send_status='Scheduled'` and `phantom_run_id` in one UPDATE *after* the PhantomBuster launch returns (index.ts line ~320). If that UPDATE fails, or a 4-second no-op run reports back before it lands, the callback is an orphan and the row stays as it was.
- This is the local source; the deployed version was not fetched or compared.

### Last 10 executions of 9714524 (UTC)

| # | Time | Type | Status | Ops |
|---|---|---|---|---|
| 1 | 2026-09-10 11:40:41 | auto | success | 2 |
| 2 | 2026-09-09 12:57:27 | auto | success | 2 |
| 3 | 2026-09-08 08:35:13 | auto | success | 2 |
| 4 | 2026-08-26 11:30:19 | auto | success | 2 |
| 5 | 2026-08-26 11:30:03 | auto | success | 2 |
| 6 | 2026-08-26 11:26:42 | auto | **error**: body not valid JSON | 2 |
| 7 | 2026-08-26 11:15:51 | manual (replay of #8) | success | 2 |
| 8 | 2026-08-26 11:13:54 | manual | **error**: Method Not Allowed | 2 |
| 9 | 2026-08-26 11:11:33 | manual | **error**: body not valid JSON | 2 |
| 10 | 2026-08-26 11:06:35 | manual | success (webhook only, 1 op) | 1 |

**The scenario has not executed since 2026-09-10 11:40Z (10 days).** The DB agrees: audit_log rows with source `phantombuster_callback` total 5 (send_skipped x2 on 26 Aug; send_completed x3 on 8, 9, 10 Sep), and only 2 outreach_log rows carry a `phantom_run_id` at all. The Sent rows dated 15 and 17 Sep have no `phantom_run_id`, so they were not closed by this path. Either no PhantomBuster send has been dispatched since 10 Sep, or sends are being closed another way; worth confirming which before relying on this callback.

## Part 2 - Verification

### (a) Watcher scenarios, team 586107

All three are webhook-triggered (`immediately`, max 100/min), so Make holds no schedule; the 4-hourly cadence comes from whatever posts to the hooks (not pg_cron: no cron.job command references them). Window checked: 2026-09-18 16:00Z to 2026-09-20 16:10Z.

| Scenario | ID | Active | Cadence seen | Runs in 48h | Errors | Gaps |
|---|---|---|---|---|---|---|
| Pier Sales Nav Watcher | 9589633 | yes | every 4h at :01 | 13 | 0 | none |
| Pier Connection Watcher | 9590745 | yes (DLQ count 1) | every 4h at :04 | 12 | 0 | none |
| Pier Inbox Watcher | 9704543 | yes (DLQ count 1) | every 4h at :30 | 12 | 0 | none |

Run times (UTC):
- Sales Nav: 18 Sep 16:01, 20:01; 19 Sep 00:01, 04:01, 08:01, 12:01, 16:01, 20:01; 20 Sep 00:01, 04:01, 08:01 (8 ops, real work), 12:01, 16:01. All success, 1 op each otherwise.
- Connection: 18 Sep 19:04, 23:04; 19 Sep 03:04, 07:04, 11:04, 15:04, 19:04, 23:04; 20 Sep 03:04, 07:04, 11:04, 15:04. All success, 62 ops each. Next due 19:04.
- Inbox: 18 Sep 19:30, 23:30; 19 Sep 03:30, 07:30, 11:30, 15:30, 19:30, 23:30; 20 Sep 03:30, 07:30, 11:30, 15:30. All success, 82 ops each. Next due 19:30.

Just outside the window, for context:
- **Outage 17 Sep ~04:00Z to 18 Sep 08:06Z (~28h)** on all three: last runs 17 Sep 03:04 / 03:30 / 04:01, then a burst at 18 Sep 08:05:59-08:06:00 (Sales Nav 7 runs, Connection 7, Inbox 7) - queued webhooks draining at once. The burst alone cost about 1,020 operations. Normal cadence resumed at 11:04 / 11:30 / 12:01.
- Warnings (status 2, 2 ops, ended early): Connection Watcher 16 Sep 15:04, Inbox Watcher 15 Sep 15:29. Each has one item sitting in its incomplete-executions queue (DLQ count 1).
- An earlier similar burst: 14 Sep 18:22 (Connection 13+ runs, Inbox 13+ runs in one second).

### (b) Make operations

The API does expose it (organisation record):

| Item | Value |
|---|---|
| Plan | Pro |
| Licence allowance | 20,000 ops / month |
| Top-up (operationsExt) | 10,000 |
| Total available | 30,000 |
| Used this period | **23,062** |
| Remaining | **6,938** |
| Period | 2026-08-25 11:16Z to reset **2026-09-25 11:16Z** |
| Auto-purchase | off |

Up 2,037 from the 21,025 recorded on 18 Sep. Steady burn is about 875/day (Connection 62 x 6 + Inbox 82 x 6 + Sales Nav ~10). About 4.8 days to reset -> roughly 4,200 more, leaving ~2,700 headroom, provided there is no further queue-drain burst (each stalled 4h slot costs ~145 ops when it drains).

## Suggested follow-ups (not done here)

1. Add a stale-Scheduled sweeper (e.g. rows at `Scheduled` for > N minutes -> check PhantomBuster container or mark Cancelled with a reason). This closes paths A-F in one place.
2. In Make: build the body with a data structure / `toString` + escaping instead of raw string splicing; add an error handler on module 3 and enable incomplete executions so failures retry rather than vanish.
3. In the function: write an audit_log row on `orphan`, and consider guarding the UPDATE with `send_status = 'Scheduled'` so replays cannot flip a terminal row.
4. Move the hardcoded Bearer in module 3 into a Make connection/keychain.
5. Confirm why the callback has not fired since 10 Sep.
