# Oli's six test shapes — concrete mapping

Oli's handover §6. Three shapes must REFUSE. Reason codes are the closed set from
migration 054's `refusals_reason_code_check`.

**Status of this doc:** written from LIVE data as it stands 2026-09-03 18:xx BST,
**before** the Phase 2 migration. Shapes 1, 2, 3 and 5 need contacts that only exist in
full after the workbook import; the candidates named are live stand-ins where one exists,
and marked `POST-MIGRATION` where the population is not there yet.

## Gate precedence — settle this before testing

Several contacts trip more than one gate. The refusal must be deterministic, so gates are
evaluated in this order and the FIRST match is returned:

1. `promise_of_quiet`   — absolute, Oli: binding, not recoverable
2. `dnc_or_opted_out`   — absolute
3. `contact_parked`     — UK, Jack's territory
4. `cr_cooldown_active` — CR inside the six-month block
5. `allowance_exhausted`— per-channel cap reached
6. `channel_illegal_in_market`
7. `company_not_deep_researched`
8. `thread_text_missing`

Rationale: consent and territory gates outrank data-quality gates. A promise-of-quiet
contact must never come back as "company not deep researched" — that reads as a fixable
problem and invites someone to fix it and retry.

## The six shapes

| # | Shape | Expected | Reason code |
|---|---|---|---|
| 1 | First message after accept, English | DRAFT | — |
| 2 | Chaser, allowance fine | DRAFT | — |
| 3 | Chaser, allowance exhausted | **REFUSE** | `allowance_exhausted` |
| 4 | Promise-of-quiet contact | **REFUSE** | `promise_of_quiet` |
| 5 | German du + Sie pair | DRAFT ×2, register preserved | — |
| 6 | Thread text missing | **REFUSE** | `thread_text_missing` |

### Shape 1 — first message after accept, EN
Pool: 34 live contacts that are `Accepted` at a `Deep research done` company.
`POST-MIGRATION`: pick one with `language_code='EN'` and no prior outbound touch.
Expect a draft, `touch_type='Initial message'`, `channel='LinkedIn DM'` (free, per C1).

### Shape 2 — chaser within allowance
DM route, `chaser_count < dm_chaser_cap (3)`. Expect a draft on **LinkedIn DM, not InMail**
— this is the Batch B flag-3 fix; chasing an already-connected contact over InMail burns a
credit for nothing.

### Shape 3 — chaser, allowance exhausted  → MUST REFUSE
Two ways to construct, and both should be tested:
- **DM route**: `chaser_count >= 3`
- **InMail route**: `chaser_count >= 1` (Oli's correction 3a — one initial + one chaser)
The InMail case is the one that regressed before: the pre-correction engine run on
2026-09-03 06:15 drafted 25 InMail Chaser 1s, all now superseded.
Expect `{refused: true, reason_code: "allowance_exhausted"}` and a `refusals` row.

### Shape 4 — promise of quiet → MUST REFUSE
`POST-MIGRATION`: `contacts.promise_of_quiet = true`. Regex scan of the frozen workbook
returns **17 candidates** against Oli's 16 (list and delta in the Phase 2 report).
Strongest single test case: **P198 Dennis Backofen** — matches both `binding promise` and
`letzte Nachricht von mir`, so it is unambiguous in either language.
Expect `{refused: true, reason_code: "promise_of_quiet"}`. Must refuse on EVERY channel and
under EVERY rule, including a manual request.

**Known near-misses that must NOT be flagged** (verify they draft normally):
- **P101** — invited check-in Aug 2027. A scheduled future touch, not a promise to stop.
- **P398** — declined, wrong person. `Not relevant`, refuses as `dnc_or_opted_out` or is
  simply out of pool; it must not be recorded as a promise of quiet.

### Shape 5 — German du + Sie
78 live DE contacts; 53 at deep-researched companies. The register lives in the workbook's
`Formality` column, which **has no live counterpart yet** — the live `contacts` table has no
formality/register column. `POST-MIGRATION` and **blocked until the import adds it**.
Pick one `du` and one `Sie` contact at the same company where possible, so the only variable
is register. Expect two drafts whose register differs and survives the model call.

### Shape 6 — thread text missing → MUST REFUSE
Live candidates exist **today**. 81 of 193 `Sent` rows have no body at all, so `sent_body`
backfilled only 112. Verified candidates, each with exactly one sent outbound touch and an
empty body:

| ref | contact | company | connection | research stage |
|---|---|---|---|---|
| **P212** | Florian Hipfl | HOFER KG | Request sent | Light triage |
| **P215** | Alexander Stork | ALDI DX | Request sent | Light triage |
| **P219** | Robert Pauly | Tchibo | Accepted | Light triage |
| **P208** | Davit Gniech | Tchibo | Request sent | Light triage |

**Caution:** all four are at `Light triage` companies, so they trip
`company_not_deep_researched` too. Under the precedence above that gate fires FIRST (7
before 8), so these would refuse with the *wrong* code for this test. To test shape 6
cleanly, use a contact at a `Deep research done` company whose prior sent touches are empty
— or temporarily assert the expected code as `company_not_deep_researched` and note it.
**P219 is the best of the four** (Accepted, so it is a real chaser candidate).

## Sizing note that affects the whole test day

Only **58 of 361 companies (16%) are `Deep research done`**; 247 are `Light triage` and 58
`Untouched`. Since `company_not_deep_researched` refuses *message* drafts (blank CRs are
unaffected per Oli's board rule), the catch-up queue will return **far more refusals than
drafts**. That is the gate working as specified, but it sits against Oli's "happy with the
full backlog" expectation, and he should see the split before the test day rather than
discover it in the queue.

## Results, 2026-09-04 (post-migration, drafter v26, all dry runs)

| # | Contact | Result |
|---|---|---|
| 1 | P269 Anthony, GreenIT Ireland, EN | DRAFT (LinkedIn DM, warm cache, GBP 0.0146) |
| 2 | P037 Elena Panova, A1 Telekom | DRAFT, Chaser 1 on LinkedIn DM (free route) |
| 3 | P227 Bram Weijschede, Fixje (3 DM chasers) | REFUSED allowance_exhausted, "3 of 3 sent" |
| 3 | P050 Vittorio Buonfiglio, MediaMarkt (1 InMail chaser) | REFUSED allowance_exhausted, "1 of 1 sent" |
| 4 | P198 Dennis Backofen | REFUSED promise_of_quiet (first message and chaser) |
| 5 | P001 Peter Stolzlederer (du) / P045 Alejandro Plater (Sie), both A1 | two DRAFTS, register preserved in each |
| 6 | P706 Florian Pfeiffer, Sparhandy / P297 Alessandro P., TrenDevice | REFUSED thread_text_missing |

Shape 5 now works because migration 058/Phase 2 imported the workbook Formality column onto
`contacts.formality` (359 rows) and the drafter passes it as an explicit register line.

## Standing regression tests (F13.8, added 2026-09-10)

Run after any change to the send path, the callback, the chase engine or a migration that
touches contacts. Every query must return 0 (test 5: the two numbers must be equal). Team id
`ef73c15e-4d6f-4159-bcfa-cc76b5ae4972`. Dates are London dates, the same as fn_apply_send_effects.

```sql
-- 1. No Sent row where touch_date differs from the real send date.
select count(*) from outreach_log
 where send_status='Sent' and sent_at_actual is not null
   and touch_date <> (sent_at_actual at time zone 'Europe/London')::date;

-- 2. No contact messaged in the last 30 days sitting in an UNEARNED chase cooldown
--    (chase_state 'cooldown' with no sent chaser). An earned rest is chase_state 'exhausted',
--    or an operator-set Cooldown status with a chaser sent (Lutz Schottenhammer, 2027-08-16).
select count(*) from contacts
 where archived_at is null and cooldown_until > current_date
   and chase_state = 'cooldown' and coalesce(chaser_count,0) = 0
   and last_contacted >= current_date - 30;

-- 3. No contact with a sent message (not a connection request) still Not started / To contact.
select count(*) from contacts c
 where c.archived_at is null and c.outreach_status in ('Not started','To contact')
   and exists (select 1 from outreach_log o where o.contact_id=c.id and o.send_status='Sent'
                 and o.touch_type not in ('Reply','Connection request'));

-- 4. No contact claiming chaser_N_sent with zero sent chasers.
select count(*) from contacts
 where chase_state in ('chaser_1_sent','chaser_2_sent') and coalesce(chaser_count,0) = 0;

-- 5. Today's send count equals the rows this system dispatched today (phantom_run_id set).
select (select count(*) from v_sent_touches
         where sent_on = (now() at time zone 'Europe/London')::date
           and phantom_run_id is not null) as today_log,
       (select count(*) from outreach_log
         where phantom_run_id is not null and send_status='Sent'
           and (sent_at_actual at time zone 'Europe/London')::date = (now() at time zone 'Europe/London')::date) as today_dispatched;
```

Baseline 2026-09-10 after F13: 0, 0, 0, 0, 1 = 1. The v_sent_touches count without the
phantom_run_id filter also includes rows Oli marks sent by hand or the inbox watcher files as his
own messages; those are real sends too, so the Today tile may legitimately exceed the dispatched
count on days Oli messages outside the app.

## Standing regression tests, F14.8 (added 2026-09-14)

Run beside the F13 five. Every query returns 0 unless stated.

```sql
-- 6. No automation source silent longer than its threshold (12 h for the three watchers).
select count(*) from v_automation_health where is_silent;

-- 7. No EXECUTE grant to anon or authenticated on a function that mutates contact or outreach state.
--    (fn_user_teams, fn_task_scope and the read-only fn_* helpers are exempt by name.)
select count(*) from information_schema.role_routine_grants
 where routine_schema='public' and privilege_type='EXECUTE' and grantee in ('anon','authenticated')
   and routine_name in ('fn_apply_send_effects','fn_heartbeat','fn_set_field_provenance','fn_ledger_inmail_send',
                        'fn_ledger_inmail_reverse','fn_ledger_inmail_accept_refund','fn_match_contact_by_alias');

-- 8. No Sent row rendering a draft editor. Not a SQL test: open /outreach/<id> for any row with
--    send_status = 'Sent' and confirm no Approve / Send now / AI edit / Regenerate control renders.
--    Rows to use: 69f0ae51-3318-4563-a15b-bec63615e9e7 (Fischer), 49f0a880-a210-4d9c-8df2-bffe443d01dd (Moeller).

-- 9. Consent-gate refusal counts unchanged across a build. Snapshot before and after; the four
--    consent codes must match exactly (only volume codes may move).
select reason_code, count(*) from refusals
 where reason_code in ('promise_of_quiet','dnc_or_opted_out','contact_parked','cr_cooldown_active')
   and created_at >= current_date - 7 group by 1 order by 1;

-- 10. No duplicate outreach_log row on external_key, nor on (contact_id, touch_date, touch_type)
--     among live rows created after 2026-09-14 (migration-era duplicates are known and listed in the F14 record).
select (select count(*) from (select external_key from outreach_log where external_key is not null group by 1 having count(*)>1) x)
     + (select count(*) from (select contact_id, touch_date, touch_type from outreach_log
                               where created_at >= '2026-09-14' and draft_status <> 'superseded' group by 1,2,3 having count(*)>1) y);
```

Baseline 2026-09-14 after F14: 0, 0, (visual), promise_of_quiet 2 / dnc_or_opted_out 1 / contact_parked 0 /
cr_cooldown_active 0, 0.

## F15 regression set (2026-09-15) — routing matrix, event-driven drafting, replies

Run these beside the F13 and F14 sets. Every query is read-only. All must hold before and after any change to the drafter, the chase engine, the classifier or the candidate functions.

```sql
-- F15-1 Invariant (a): no pending chaser exists without a real Sent message on that channel. Expect 0.
select count(*) from outreach_log o join contacts c on c.id=o.contact_id
 where o.draft_status='pending_review' and o.touch_type::text like 'Chaser %'
   and not exists (select 1 from outreach_log s where s.contact_id=c.id and s.send_status='Sent'
                     and s.touch_type::text not in ('Reply','Connection request') and s.channel::text=o.channel::text);

-- F15-2 Invariant (b): no pending LinkedIn DM to a contact who is not connected. Expect 0.
select count(*) from outreach_log o join contacts c on c.id=o.contact_id
 where o.draft_status='pending_review' and o.channel::text='LinkedIn DM'
   and c.connection_status::text not in ('Accepted','Already connected');

-- F15-3 fn_chase_candidates never proposes a chaser without a real message on its channel. Expect 0.
select count(*) from fn_chase_candidates('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972',5000) f
 where not exists (select 1 from outreach_log s where s.contact_id=f.contact_id and s.send_status='Sent'
                     and s.touch_type::text not in ('Reply','Connection request') and s.channel::text=f.channel);

-- F15-4 fn_cold_inmail_candidates never returns a connected contact or one already messaged. Expect 0.
select count(*) from fn_cold_inmail_candidates('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972',5000) f join contacts c on c.id=f.contact_id
 where c.connection_status::text in ('Accepted','Already connected')
    or exists (select 1 from outreach_log s where s.contact_id=c.id and s.send_status='Sent' and s.touch_type::text not in ('Reply','Connection request'));

-- F15-5 chase_state 'replied' is a hard block: no chaser candidate and no pending chaser for a replied contact. Expect 0 / 0.
select (select count(*) from fn_chase_candidates('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972',5000) f join contacts c on c.id=f.contact_id where c.chase_state='replied'),
       (select count(*) from outreach_log o join contacts c on c.id=o.contact_id where o.draft_status='pending_review' and o.touch_type::text like 'Chaser %' and c.chase_state='replied');

-- F15-6 A contact under ruling (pending_ruling) is refused on every channel and every request type. Expect every row = pending_ruling.
select distinct coalesce(g.reason_code,'PASS') from contacts c
 join refusals r on r.contact_id=c.id and r.reason_code='pending_ruling'
 cross join lateral (values ('LinkedIn inMail','initial_message'),('LinkedIn DM','chaser'),('Email','reply')) v(ch,req)
 left join lateral fn_evaluate_gates(c.team_id, c.id, v.ch, v.req) g on true
 where c.outreach_status::text='Needs review';

-- F15-7 Consent gates unchanged: refusal counts by reason code over the last 7 days, compare before/after.
select reason_code, count(*) from refusals where created_at > now()-interval '7 days' group by 1 order by 1;

-- F15-8 A reply moves the contact to In conversation: no live (non-migrated) reply on a contact still earlier in the funnel. Expect 0.
select count(*) from contacts c where c.chase_state='replied'
   and c.outreach_status::text in ('Not started','To contact','Ready','Active','Contacted');

-- F15-9 Superseded agent drafts and inbox duplicates are never 'Sent'; sent-then-replaced rows stay Sent. Expect 0.
select count(*) from outreach_log where draft_status='superseded' and send_status='Sent'
   and (agent_produced or coalesce(rejection_feedback->>'reason','')='duplicate_of_dispatched_row');

-- F15-10 Every agent draft written since v35 carries a voice stack stamp, and layer 4 appears only on
-- first messages after CR (Initial message / LinkedIn DM) or email replies. Expect 0 for both counts.
select (select count(*) from outreach_log where agent_produced and created_at > '2026-09-15 06:00+00' and voice_stack_versions is null),
       (select count(*) from outreach_log where agent_produced and voice_stack_versions ? 'voice_oliver'
          and not ((touch_type::text='Initial message' and channel::text='LinkedIn DM') or (touch_type::text='Follow up' and channel::text='Email')));
```

Behavioural checks (dry runs, nothing written): POST generate-draft-from-context with dry_run:true for (i) a Withdrawn contact with a bare CR and trigger chaser_1: expect touch_type Initial message, channel LinkedIn inMail, routing_notes non-empty; (ii) the same contact with trigger cr_accepted: expect channel LinkedIn inMail; (iii) an Accepted contact with a sent DM and trigger chaser_1: expect Chaser 1 on LinkedIn DM, voice_stack_versions without voice_oliver; (iv) an Accepted, never-messaged contact with trigger cr_accepted: expect layer4 = first_message_after_cr. POST chase-engine with dry_run:true: candidates_by_route must show only cr_not_accepted (LinkedIn inMail) and accepted_chase (LinkedIn DM), and cold_inmail_openers.considered <= cold_inmail_openers_per_run.

## F16.1 regression set (2026-09-15) — group guard

```sql
-- F16-1a No draft at Draft / Ready / Scheduled (measured send_status values) for a contact whose company has a
-- GENUINELY engaged group sibling (duplicates and out_of_scope excluded), for ANY request type. Expect 0.
select count(*) from outreach_log o join contacts c on c.id=o.contact_id
 where o.send_status::text in ('Draft','Ready','Scheduled') and o.draft_status::text = 'pending_review'
   and exists (select 1 from fn_group_siblings_engaged(c.team_id, c.company_id));
-- F16-1b The guard is not scoped by request type: the same contact refuses on chaser, reply and initial_message alike.
select count(distinct r) from (select coalesce((select reason_code from fn_evaluate_gates(c.team_id,c.id,'LinkedIn DM',req) limit 1),'PASS') r
  from contacts c cross join (values ('initial_message'),('chaser'),('reply')) v(req) where c.contact_id='P285-any') x;  -- pick a Save Group contact; expect 1 distinct value
-- F16-1c Duplicate candidates never block: every pair in fn_company_duplicate_candidates is absent from fn_group_siblings_engaged. Expect 0.
select count(*) from fn_company_duplicate_candidates('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972') d
 where exists (select 1 from fn_group_siblings_engaged('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', d.company_id) g where g.company_id = d.sibling_id);
-- F16-1d out_of_scope never blocks: no engaged sibling whose only claim is archive_reason out_of_scope. Expect 0.
select count(*) from companies me cross join lateral fn_group_siblings_engaged(me.team_id, me.id) g join companies s on s.id=g.company_id
 where s.archive_reason='out_of_scope' and s.monday_deal_id is null and s.opportunity_status::text not in ('Contacted','Active Lead','Partner')
   and not exists (select 1 from contacts c where c.company_id=s.id and c.outreach_status::text in ('Contacted','In conversation','Meeting booked'));
-- F16-1e Gate cost: one fn_evaluate_gates call under 500 ms (was 3539 ms before migration 102).
-- F16-1f Chase engine summary reconciles: the dry-run JSON carries reconciles = true.
-- SEC-1 No cron job command references cron.job; every job calling an Edge Function carries its own Authorization header.
select jobid, jobname, (command ilike '%cron.job%') refs_cron_job, (command ilike '%functions/v1%') calls_ef, (command ilike '%authorization%') has_auth
  from cron.job;  -- expect refs_cron_job false everywhere and has_auth true wherever calls_ef is true. Never select the raw command.
```
