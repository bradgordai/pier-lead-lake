# F19.2, F19.3 and the deep-research gate (addendum 4) — 2026-09-21

Nothing was sent. No Make scenario and no PhantomBuster agent was edited; both were read only.

## F19.2 Cut Make out of the callback loop — REPORT ONLY, Brad makes the change in the PhantomBuster UI
(a) Current value, identical on all three agents (read 21 Sep): `notifications.webhook` =
`https://hook.eu2.make.com/<hook token>` (the path IS the Make hook token; masked). launchType manual,
maxParallelism 1, lastEndType finished. Mail-on-error notifications are on; they stay.

| Agent | Name | Change `notifications.webhook` to |
|---|---|---|
| 5691059901018698 | Pier LinkedIn Message Sender | `https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/send-approved-callback?auth=<INBOUND_WEBHOOK_SECRET>` |
| 7500783933729451 | Pier LinkedIn Auto Connect | same URL |
| 8651232052097344 | Pier Sales Navigator Message Sender | same URL |
The secret goes in by hand from the Supabase function secrets; it is never written into this repo. A secret
in a URL is weaker than a header (it lands in PhantomBuster's config and any proxy log); it is what the
function header documents because PhantomBuster's webhook field takes a bare URL. Rotate it with the rest.
(b) PAYLOAD SHAPE. The function reads containerId (also container_id, phantom_run_id, runId, id), exitCode,
exitMessage (also lastEndType) and resultObject. The Make blueprint maps `{{2.containerId}}`,
`{{2.agentId}}`, `{{2.exitCode}}`, `{{2.exitMessage}}`, `{{2.resultObject}}` straight off the webhook
bundle, so PhantomBuster's NATIVE field names are those same names. Two differences, both already handled:
native resultObject arrives as a JSON STRING (toArray parses strings), and native exitCode is a number
(Number() takes either). **`pick` needed no change.** NOT VERIFIED against PhantomBuster's own docs: the
webhook doc page returned 404 to me. The function already logs `callback_shape` (the key list) on every
call, so the first direct callback proves or disproves this in one log line. Residual risk, unchanged from
today: a real send whose resultObject is a JSON object rather than an array is treated as skipped.
(c) IDEMPOTENCY. **It was NOT idempotent.** Verified against the code: a second callback for an already-Sent
row re-wrote sent_at_actual, re-ran fn_apply_send_effects and logged a second send_completed; and if the
second payload lacked a populated resultObject it would have turned a real send into Cancelled and
refunded its InMail credit. With Make left on as a fallback that double callback is the normal case, not an
edge case. FIXED in send-approved-callback: a row already at Sent or Cancelled returns `already_terminal`
and nothing is written. Leave Make 9714524 ACTIVE until one real send has completed by the direct path.
Also still true from F18.3: the Make blueprint splices exitMessage in unescaped and discards the bundle on
any non-2xx. Going direct removes both.

## F19.3 The queue — callback-driven with a dead-man's switch
Migrations 122 and 122b applied. Function source committed; deploy result at the foot.
(a) In-flight now means: a send_queue row at `launched` on that agent whose outreach_log row is not yet Sent
or Cancelled. The 180-second window is gone as the gate.
(b) **The instruction could not be followed as written.** phantom_run_id IS the containerId that
PhantomBuster's launch call returns; it does not exist before the launch. The race is closed from both
other sides instead: (1) the callback, on finding no row, looks again every 2 s for 8 s; (2) if there is
still no row it PARKS the payload in `send_callback_orphans`; (3) the dispatcher, the moment it has written
phantom_run_id, looks for a parked callback for that container and replays it through the callback
function, so there is still exactly one place that decides Sent or Cancelled. The queue is also now held
from BEFORE the launch call rather than after it returns.
(c) An orphan is logged at error level as `orphan_callback_parked` and kept as a row. Nothing is dropped.
A parked callback that is never claimed means a container ran that this system did not launch.
(d) 10 minutes at `launched` with no terminal state marks the row `stuck` and releases the queue. It runs
on every claim and every drain.
(f) Randomised 180-300 s spacing stays on top, measured from the last launch or confirmed outcome.
(h) CONFIRMED against the code and by test: a first send with an empty queue launches immediately.
(i) `v_regress_send_queue_launched_too_long` must read 0. It reads 0.
Rolled-back test, all in one transaction: 1 first send, empty queue -> launches, wait 0 s. 2 second while
the first is in flight -> queued; pressed again -> still queued, no error; drainer finds nothing. 3 just
after the callback -> still held, 237 s of spacing. 4 six minutes after the callback -> launches.
5 launched 11 minutes ago with no callback -> regression view 1, housekeeping marks it stuck, view back to
0, the next send launches.
**A bug of mine, caught by that test and fixed the same hour (122b):** in 122 the name `not_before` was
both a column and the function's output column, so pressing Send now a second time on a queued send raised
"column reference is ambiguous". It was live for about ten minutes; the queue was empty throughout.
(e) Oliver's Release button: `fn_release_send_queue` and the view `v_send_queue_status` exist. The Today
strip itself is a Lovable change and is NOT yet fired.
(g) Migration 109 (the drainer cron): NOT yet applied. It goes in after the functions are confirmed
deployed, as 123, with a once-a-minute housekeeping call so a stuck send is marked even when nobody is
pressing anything.

## Addendum 4: the deep-research gate. REPORT ONLY, nothing changed
- WHO REFUSES: `fn_evaluate_gates`, one branch (migration 092 line 100): company missing or research_stage
  not 'Deep research done' -> `company_not_deep_researched`. It is the ONLY database object that mentions
  the code. Replies skip it only when team_settings.reply_ignores_research_gate is on (it is off).
- BEFORE OR AFTER GENERATION: BEFORE. generate-draft-from-context calls the gate at line 391 and returns
  the refusal at about line 414; the model call is at line 671. No tokens are spent on a refused draft.
  chase-engine also calls the gate itself before it calls the drafter, and send-approved-draft calls it
  again at send time.
- WHAT ELSE READS THE CODE: nothing in the database. In code: chase-engine's per-section refusal maps and
  the drafter's response. In Lovable: wherever refusal reasons are listed (the contact's last 20 refusals,
  the "blocked: company not deep researched" line on Today).
- SCALE: 1,534 refusals all time, but only **55 contacts at 42 companies**. 1,486 are initial_message,
  46 chaser, 2 reply. 1,480 carry no source, which means they were written by the drafter being called
  directly, about 27 times per contact: something re-requests the same refused contacts over and over.
  FLAG, not fixed.
- WHAT A CHANGE WOULD TOUCH. "Generate, flag in red, let Oliver decide" needs: (1) the branch in
  fn_evaluate_gates to stop refusing draft requests; (2) the drafter to stamp the draft, as it already
  does for replies (`researchNote`, written into draft_narrative and the first guardrail); (3) A DECISION
  ABOUT SEND TIME: send-approved-draft re-runs the same gate, so an approved red-flagged draft would be
  refused at launch unless the send path exempts a draft Oliver has approved. That is the real design
  question; (4) two candidate functions pre-filter on research stage and would hide those contacts from
  the cron regardless (fn_cold_inmail_candidates requires 'Deep research done'); (5) cost: 650 active
  companies are not deep researched (421 Untouched, 228 Light triage, 1 Outdated) against 131 that are.
  Today's candidate sets are 103 cold InMail, 45 first message, 18 chasers; removing the gate does not
  change those sets, it changes how many of them get a draft instead of a refusal, each costing a model call.

## Deploy results
(appended when the deploy agent reports)
