-- 088 F13.5 (2026-09-10): one source for "what went out and when". sent_on is the TRUE send date
-- (sent_at_actual as a London date, else touch_date for rows this system never dispatched).
-- security_invoker: the caller's RLS on outreach_log / contacts / companies applies. Owner scoping
-- is done by the app through fn_task_scope on owner_user_id; no new visibility predicate here.
create or replace view public.v_sent_touches with (security_invoker = true) as
select o.id, o.team_id, o.contact_id, o.company_id, o.touch_id,
       o.channel::text as channel, o.touch_type::text as touch_type, o.subject_line, o.migrated_legacy, o.phantom_run_id,
       coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date) as sent_on,
       o.sent_at_actual, o.touch_date,
       c.owner_user_id, c.first_name, c.last_name, c.archived_at as contact_archived_at,
       co.company_name, co.archived_at as company_archived_at
  from public.outreach_log o
  left join public.contacts c on c.id = o.contact_id
  left join public.companies co on co.id = o.company_id
 where o.send_status::text = 'Sent'
   and o.touch_type::text <> 'Reply'
   and o.channel::text <> 'Other';
grant select on public.v_sent_touches to authenticated;
comment on view public.v_sent_touches is 'F13.5: sent touches keyed on the true send date (sent_on). Today tiles and the activity log read this, nothing else.';
