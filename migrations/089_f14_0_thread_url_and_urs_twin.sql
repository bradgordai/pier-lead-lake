-- 089 F14.0 (2026-09-14): thread identity on outreach_log, and the one double-ingested row.
-- thread_id (uuid) is null on every row because LinkedIn thread URLs are not UUIDs. The watcher
-- now writes the thread URL as text on the same path; history is NOT backfilled.
alter table public.outreach_log add column if not exists thread_url text;
comment on column public.outreach_log.thread_url is 'F14.0: LinkedIn messaging thread URL as the watcher reports it. Written forward from 2026-09-14 only.';
create index if not exists outreach_log_thread_url_idx on public.outreach_log (team_id, thread_url) where thread_url is not null;
alter table public.unmatched_replies add column if not exists thread_url text;

-- Urs Moeller: the inbox watcher filed his dispatched opener a second time on 2026-09-14 19:22
-- (body differs only by a trailing space in the first 40 characters). Mark, do not delete.
do $$
declare v_run text := 'f14-0-urs-twin-2026-09-14';
begin
  update public.outreach_log set draft_status = 'superseded',
    rejection_feedback = jsonb_build_object('reason','duplicate_of_dispatched_row','twin','49f0a880-a210-4d9c-8df2-bffe443d01dd','detail','Inbox watcher re-filed the dispatched opener (F14.0, 2026-09-14). Kept for audit, excluded from counts.'),
    thread_url = 'https://www.linkedin.com/messaging/thread/2-N2I0OGUyYTktNWY5OC00ZDBlLWJlYTYtZjUyMjNmN2JkMjFmXzEwMA==/',
    updated_at = now()
   where id = '66f962ae-0e00-4161-bdd0-c14e36cd731c' and draft_status::text = 'sent';
  insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
    values (v_run, 'f14_0_twin', 'outreach_log', 'inbox-7ca5ddd1-297a-4033-a4aa-e705bfe2e2c9', 'update', '66f962ae-0e00-4161-bdd0-c14e36cd731c',
            jsonb_build_object('before', jsonb_build_object('draft_status','sent'), 'after', jsonb_build_object('draft_status','superseded'), 'twin', '49f0a880-a210-4d9c-8df2-bffe443d01dd'));
end $$;
-- v_sent_touches must not count a superseded twin.
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
   and o.channel::text <> 'Other'
   and o.draft_status::text <> 'superseded';
