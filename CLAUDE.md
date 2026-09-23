# Pier Lead Lake — read this before doing anything

## 1. Who this is for
Pier Lead Lake is LIVE. Oliver Mueller is a real client who uses it every day to send real messages to
real prospects. Jack Stevens is a second user. Brad Gordon builds it. A mistake here reaches a prospect's
inbox. Every judgement call below follows from that.

## 2. Nothing sends from a build session
No Send now, no Approve, no phantom launches, no dispatch, no drainer trigger. Chrome MCP is READ ONLY.
If a task appears to need a real send to verify, STOP, say exactly what would go to whom, and wait for
Brad. The only exception ever granted was one controlled send to Brad's own LinkedIn profile, named
explicitly in the prompt that granted it.

## 3. Working rules
- PROOF NOT PROSE. A migration is done when its row is in supabase_migrations.schema_migrations AND a
  SELECT shows the data changed. A function is done when its post-deploy version is reported and the
  deployed files were byte-compared with the repo. A screen is done when it has a Lovable commit SHA, a
  Chrome render AND the published URL. "Written", "designed", "proposed", "committed" are NOT done.
- One migration and one commit per task. HALT on a half-applied migration and report what landed.
- Never run migration-applying agents in parallel (the 119 ledger collision).
- Lovable: one message at a time, Plan Mode first on anything non-trivial, poll until agentFinished,
  verify in Chrome, publish, then the next. Never two at once; no sub-agents for Lovable work.
- Publish after every verified screen. A preview commit is not delivery.
- Deploying agents diff LIVE source against the repo before deploying; the repo has drifted behind
  production more than once. Re-read the live schema before every Lovable prompt.
- Flag, do not fix, anything outside the current scope. Every gap between an earlier report and what
  you observe is itself a finding.

## 4. Output discipline
Migrations to files in /migrations then apply from the file. Reports to docs/reports/ as FILES named for
the task, never inline. Reply under 300 words. Long inline reports with heavy regex have crashed the tool
three times. Prompts arrive numbered F16, F17, ... Never inline a secret; never SELECT cron.job.command
unredacted (tests/no_static_bearer_test.py guards the repo).

## 5. The Lovable trap
The repo is NOT the Lovable codebase. Committing here does not ship a screen. The only way to change
Lovable is the Lovable MCP send_message against project fc695882-94ec-4791-8c82-8795c90c7291. Writing a
prompt to a file is not delivery. This caused a three-day gap (18-21 Sep 2026) in which Oliver worked on
a stale app while every fix sat in docs/reports. The preview lags a commit by 1-2 minutes and sits behind
the app login (Brad signs in; never sign in for him). Published app: https://pier-lead-lake.lovable.app

## 6. Lovable must not touch the database
Append verbatim to every Lovable prompt:
"Do not create, alter or drop any Supabase table, column, enum, policy, function or migration. The schema
is owned elsewhere and already exists. Read it, do not change it. If something you need appears to be
missing, stop and say so instead of creating it."
Also: paginate every list with a total count (PostgREST caps at 1,000 rows and Lovable scaffolds
select('*') with no range, so lists truncate silently); audit pg_policies after any change that could
touch RLS; read Lovable's code in its reply (it once validated a bigint id as a UUID); Lovable may echo
a secret it finds into its reply.

## 7. The enum trap
A query filtering on a value that does not exist returns zero and READS AS A PASS. Two false all-clears
so far. Confirm every literal in a predicate exists before quoting a count. Measured values:
- outreach_log.send_status: Draft | Ready | Scheduled | Sent | Cancelled
- outreach_log.draft_status: pending_review | approved | sent | superseded | rejected
- outreach_log.touch_type: Initial message | Connection request | Chase | Reply | Event follow-up |
  Introduction | Meeting confirmation | Other | Chaser 1 | Chaser 2 | Chaser 3 | Follow up
- companies.research_stage: Untouched | Light triage | Deep research done | Outdated
- contacts.connection_status: Not connected | Request sent | Accepted | Already connected | Ignored | Withdrawn
- COMPANIES.opportunity_status: To Review | Prospect | Contacted | Active Lead | Partner | Out of Scope
- CONTACTS.outreach_status: Not started | Ready | Active | Contacted | In conversation | Cooldown |
  Needs review | Do not contact | Left company | Not relevant | To contact | Meeting booked | Opted out | Parked
- contacts.chase_state is TEXT, not an enum (no enum_range): none, awaiting_reply, chaser_drafted,
  chaser_1_sent, chaser_2_sent, exhausted, replied, cooldown
"To Review" is companies.opportunity_status; "Needs review" is contacts.outreach_status. Different fields.

## 8. The two connection fields
contacts.connection_level is DEGREE, an ENUM (1st degree | 2nd degree | 3rd degree | Out of network; a stale
snapshot). Its legacy value "Not connected" is refused by fn_contacts_degree_guard (138): that is a status.
Sales Nav sends "Out-of-Network"; v26 stores "Out of network". connection_status is INVITATION STATE. Never conflate
them. A connection request to an out-of-network person is allowed; only a free DM needs a 1st-degree
connection. A "reply" received by InMail or email proves nothing about connection.

## 9. The consent layer
fn_evaluate_gates. These gates are absolute: promise_of_quiet, dnc_or_opted_out, company_archived,
contact_parked, pending_ruling, group_sibling_engaged (the group guard). The research gate
(company_not_deep_researched) is a WARNING since 21 Sep (team_settings.research_gate_warns_only).
Any batch that touches drafting or state must prove the consent codes unchanged: refusal counts per
reason_code before and after, every change accounted for. chase_state is read by eight functions
including the gate; a repair to it needs a rolled-back dry run showing zero newly eligible contacts.

## 10. The voice stack
Drafting loads layered assets from the voice_assets TABLE, not from files: layer 1 pier_rules, layer 2
pier_terminology (always on); layer 3 linkedin_architect or email_architect by channel; layer 4
voice_oliver ONLY for first_message_after_cr and warm_email_reply. voice_assets.applies_to is decorative:
nothing reads it; the gate is in generate-draft-from-context. Sign-off rule lives in layer 1 (Oliver;
"Oli" only where that contact already received a message signed Oli).

## 11. Source documents live outside the repo
- Oliver's EA documents: /Users/bradley/Documents/Claude/Projects/Pier Executive Assistant/
- Handover pack (scoring model, sizing standard, DACH board export, volume estimates, interim_intel):
  /Users/bradley/Downloads/260908_PIER_lovable_handover_pack_OM_C2/
- Improvement log export (retired; Supabase `improvements` is now the only log):
  /Users/bradley/Documents/nAIled IT/Pier Insurance/
A session that does not know these exist will invent what it cannot find. Lead_and_ICP_Brief.md has no
section 8.1(g); the "To Review" default stands anyway.

## 12. Architecture in ten lines
- Supabase (project qzfrcfzeiagziqjnfarw) owns all data, the gates, the send queue, the cron jobs
  (daily-chase-engine 06:15 UTC, send-queue-drain and -housekeeping every minute, weekday-daily-insight,
  weekly-enrich-company-websites, weekly-dq-snapshot; bearer read from Vault `internal_app_secret`).
- Edge Functions: generate-draft-from-context (drafter), chase-engine (routes: chasers, first message
  after CR, cold InMail, reply sweep), send-approved-draft (gates + queue + PhantomBuster launch),
  send-approved-callback (the ONE place a send becomes Sent or Cancelled; idempotent on phantom_run_id),
  capture-and-classify-reply, upsert-contact-from-sales-nav, update-contact-on-cr-accepted, ai-edit-draft.
  Also score-company, distill-learned-corrections (cron INACTIVE), proofread-drafts (Haiku, flags only).
- Lovable owns every screen; calls Edge Functions with the user's JWT (except generate-daily-insight, secret-only v17).
- PhantomBuster SENDS: 5691059901018698 Pier LinkedIn Message Sender (DM), 8651232052097344 Pier Sales
  Navigator Message Sender (InMail), 7500783933729451 Pier LinkedIn Auto Connect (CR).
- PhantomBuster SCRAPES: 2343586699386601 Pier Sales Nav Watcher, repointed by Brad on 22 Sep and now
  reading the Lovable Master List ("Out-of-Network" 422 fixed in v26, 23 Sep; 22 Sep run made 68 duplicates, NOT merged).
  Two SEPARATE inbox scrapers, BOTH run: a Sales Nav InMail thread and a normal LinkedIn DM thread are
  different inboxes and neither shows the other (why InMail replies were invisible until 22 Sep):
  - 7307653238072765 Pier Sales Navigator Inbox Scraper -> Make hook ending pvfyton1djs2sgrt4l9gjm5nsnslyh6m.
    Reads InMail threads. Payload: threadUrl, lastMessageDate, lastMessageType, lastMessageBody,
    lastMessageSubject, isLastMessageFromMe, totalMessageCount, unreadMessageCount, isArchived,
    restriction, timestamp (Make's run time as an ISO string, not the message time), participants[] with a NUMBER degree.
  - 2840951049581867 Pier LinkedIn Inbox Scraper -> Make hook ending bx735w393em1h9ig9okgyjgd9cmx1p8h.
    Reads the normal LinkedIn inbox. Different payload shape, separate Make scenario, same destination
    (capture-and-classify-reply).
- Make WATCHES (team 586107): 9589633 Pier Sales Nav Watcher (webhook from PhantomBuster ->
  upsert-contact-from-sales-nav, hardcoded listName "P0 Sales Nav List"), the connection watcher, the
  inbox watchers (instant webhooks; InMail one is 9850348, bearer = scoped inbound secret, typed in the module), and 9714524 Pier Send Callback (webhook -> send-approved-callback; to be
  replaced by PhantomBuster calling the function directly with ?auth=). Make ops are metered.

## 13. Live gotchas
- The permission system can refuse a production deploy ("Production Deploy"). Do NOT retry or work around
  it; report it and let Brad approve or run it.
- Cowork sometimes applies migrations directly through the MCP; a file may need writing retrospectively
  (115, 121). `supabase migration list` cannot reconcile; scripts/check_migrations_reconcile.py does.
- Background agents can die on a session rate limit mid-task; re-measure state before trusting anything.
- The send path works (first sends 21 Sep) but the UI spinner does not resolve; TEST_MODE is false.
- 136 outreach_log rows are Sent + draft_status superseded: real sends with a wrong flag, NOT to be
  cancelled; the Sent tile undercounts by them. 6 of 57 migrated "Reply" rows are Oliver's own messages.
- The four held wrong-channel approved drafts and the four duplicate Initial messages are Brad's; do not touch.
