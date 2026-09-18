# Recording a message you sent by hand

Use this when you sent a LinkedIn DM, InMail or email yourself (not through Pier's Send button) and Pier needs to know. Run the SQL in the Supabase SQL editor (it runs as `postgres`; `fn_apply_send_effects` is not callable from the app). Written 2026-09-18 after the Frank Pelzer row (i100).

## Steps

1. **Check it is not already there.** The inbox sync files your own messages automatically for LinkedIn DMs. Look at the contact's thread in Pier first. If the message is there, stop. If Pier holds an open draft (pending review or approved) for the same person that your hand-sent message replaces, reject it in the app first: inserting a Sent row does not cancel open drafts, and an approved one could still be sent.
2. **Insert one `outreach_log` row** with the template below. The values that matter:
   - `touch_id` = `hand-<YYYYMMDD>-<contact_ref>` (e.g. `hand-20260917-P858`). It is unique; add `-2` for a second hand send to the same person on the same day.
   - `observed_or_inferred` = `'recorded_by_hand'` (the column default is `'observed'`, which is wrong for these rows).
   - `send_status` = `'Sent'`, `draft_status` = `'sent'`, `outcome` = `'Awaiting reply'`.
   - `sent_at_actual` = the real send time with timezone. `touch_date` = the same moment's **UTC date** (the inbox sync compares on the UTC date).
   - `sent_body` **and** `message_body` = the message exactly as sent, pasted, not retyped. **This is what stops a duplicate:** the inbox sync matches an existing row on same contact + same `touch_date` + the first 40 characters of the text (whitespace ignored). Do not put the subject line or a note at the top of the body.
   - `channel` = `'LinkedIn inMail'`, `'LinkedIn DM'` or `'Email'`. `touch_type` = `'Initial message'` for a first message, `'Follow up'` for an ad-hoc later one, `'Chase'` for a chaser (step 3 renumbers `'Chase'` to `Chaser N`).
   - `sent_by` = `'Oliver'`, `created_by` = `'Oliver'`, `agent_produced` = `false`.
   - `thread_url` = the LinkedIn **conversation** URL if you have it (`https://www.linkedin.com/messaging/thread/...`). Leave NULL otherwise; a Sales Navigator lead URL is not a thread URL. Leave `thread_id`, `external_key` and `phantom_run_id` NULL; the sync fills `external_key` and `thread_url` when it sees the message.
   - `team_id`, `contact_id`, `company_id`, `contact_ref` come from the contact (the template looks them up).
3. **Apply the send consequences:** `select public.fn_apply_send_effects('<new row id>', 'manual-send');`
   This is the same function the send callback uses and is safe by hand. It only: sets `touch_date` to the London send date, renumbers `Chase` to `Chaser N`, and on the contact sets `chase_state` (`awaiting_reply`), `chaser_count`, `chase_last_outbound_at`, `chase_next_due_at` (send date + 7), `last_contacted`, clears `cooldown_until`, moves `outreach_status` to `Contacted` if it was Not started / To contact / Ready, and writes one `audit_log` line. It sends nothing, calls nothing external, does not touch the InMail ledger, and re-running it gives the same result. It returns `{"error":"not_sent"}` if `send_status` is not `Sent` or `sent_at_actual` is NULL.
   Do not edit the contact's chase fields by hand.
4. **InMail only, ledger:** `select public.fn_ledger_inmail_send('<new row id>');`
   It writes one `send` row (delta -1, new `balance_after`) and refuses to charge the same row twice (returns NULL). Skip it if the InMail was free (Open Profile). Its note reads "dispatched via send-approved-draft"; that wording is fixed in the function.
5. **Check:** the row shows in the contact's thread; `chase_next_due_at` on the contact is the send date + 7; for an InMail the ledger's newest `balance_after` dropped by 1.

The chaser itself is scheduled from the `outreach_log` row (`fn_chase_candidates` reads Sent rows per channel), so step 2 alone makes the day-seven chaser come up. Step 3 is what makes the contact card and Today view agree with it.

## Template (edit the five marked values; do not run as-is)

```sql
-- 1. the row
with c as (
  select id, team_id, company_id, contact_id as contact_ref
  from public.contacts
  where contact_id = 'P858'                                   -- <<< contact ref
)
insert into public.outreach_log (
  team_id, touch_id, contact_id, company_id, contact_ref,
  channel, touch_type, subject_line, message_body, sent_body,
  send_status, draft_status, outcome,
  sent_at_actual, touch_date,
  sent_by, created_by, agent_produced, migrated_legacy,
  observed_or_inferred, thread_url, draft_language
)
select
  c.team_id,
  'hand-' || to_char(t.sent_at at time zone 'UTC', 'YYYYMMDD') || '-' || c.contact_ref,
  c.id, c.company_id, c.contact_ref,
  'LinkedIn inMail',                                          -- <<< channel
  'Initial message',                                          -- <<< touch type
  b.subject, b.body, b.body,
  'Sent', 'sent', 'Awaiting reply',
  t.sent_at, (t.sent_at at time zone 'UTC')::date,
  'Oliver', 'Oliver', false, false,
  'recorded_by_hand',
  null,                                                       -- thread_url if you have the conversation URL
  'DE'                                                        -- language of the message: EN / DE / NL / FR ...
from c,
  (select timestamptz '2026-09-17 16:00:00+02' as sent_at) t, -- <<< when you sent it, with your UTC offset
  (select 'Subject here, or null for a DM'::text as subject,  -- <<< subject (InMail/email) or null
          $body$PASTE THE MESSAGE EXACTLY AS SENT$body$::text as body) b   -- <<< body
returning id, touch_id;

-- 2. consequences (use the id returned above)
select public.fn_apply_send_effects('00000000-0000-0000-0000-000000000000', 'manual-send');

-- 3. InMail only
select public.fn_ledger_inmail_send('00000000-0000-0000-0000-000000000000');
```
