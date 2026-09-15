-- 099 F15.7 / F15.8 / F15.9 (2026-09-15)
-- F15.8: a reply moves the contact to In conversation uniformly (classifier v22 does this going forward).
--        Repair the replied contacts left earlier in the funnel. Never a downgrade, never a consent status.
insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
select 'f15-8-in-conversation-2026-09-15', 'repair', 'contacts', c.contact_id, 'update', c.id,
       jsonb_build_object('name', c.first_name||' '||c.last_name, 'from', c.outreach_status::text, 'to', 'In conversation')
  from public.contacts c
 where c.team_id = 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972' and c.chase_state = 'replied'
   and c.outreach_status::text in ('Not started','To contact','Ready','Active','Contacted');
update public.contacts c set outreach_status = 'In conversation', updated_at = now()
 where c.team_id = 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972' and c.chase_state = 'replied'
   and c.outreach_status::text in ('Not started','To contact','Ready','Active','Contacted');

-- F15.9 (2): a superseded row is never a send. The Urs Moeller twin (inbox copy of his own dispatched
-- opener, superseded on 14 Sep as duplicate_of_dispatched_row) kept send_status 'Sent', so history and
-- the Outreach tab, which read send_status, still showed it. Cause fix: superseding always cancels.
create or replace function public.fn_superseded_is_not_sent() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if new.draft_status::text = 'superseded' and new.send_status::text <> 'Cancelled' then
    new.send_status := 'Cancelled';
    new.sent_at_actual := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_superseded_is_not_sent on public.outreach_log;
create trigger trg_superseded_is_not_sent before insert or update of draft_status on public.outreach_log
  for each row execute function public.fn_superseded_is_not_sent();
insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
select 'f15-9-superseded-cancelled-2026-09-15', 'repair', 'outreach_log', o.touch_id, 'update', o.id,
       jsonb_build_object('contact', o.contact_ref, 'touch_type', o.touch_type::text, 'was_send_status', o.send_status::text, 'reason', o.rejection_feedback->>'reason')
  from public.outreach_log o where o.draft_status::text = 'superseded' and o.send_status::text <> 'Cancelled';
update public.outreach_log set send_status = 'Cancelled', sent_at_actual = null, updated_at = now()
 where draft_status::text = 'superseded' and send_status::text <> 'Cancelled';

-- F15.7: "Replies needing an answer" for Today. A contact whose latest inbound reply is newer than our
-- latest sent message, excluding consent statuses and Meeting booked. Split live (captured by the inbox
-- watcher) from migrated (workbook history). Scoped through fn_task_scope: admins see every owner's,
-- members see their own (work queues are by owner).
create or replace view public.v_replies_needing_answer with (security_invoker = true) as
with lr as (
  select o.contact_id, max(o.touch_date) as last_reply, count(*) as n_replies,
         bool_and(coalesce(o.migrated_legacy, false)) as migrated_only
    from public.outreach_log o where o.touch_type::text = 'Reply' group by o.contact_id),
lo as (
  select o.contact_id, max(o.touch_date) as last_out from public.outreach_log o
   where o.send_status::text = 'Sent' and o.touch_type::text not in ('Reply','Connection request') group by o.contact_id),
lastr as (
  select distinct on (o.contact_id) o.contact_id, o.id as reply_id, o.channel::text as reply_channel,
         o.reply_classification::text as classification, left(coalesce(o.reply_content, o.message_body, ''), 280) as excerpt, o.touch_date
    from public.outreach_log o where o.touch_type::text = 'Reply' order by o.contact_id, o.touch_date desc, o.created_at desc),
draft as (
  select distinct on (o.contact_id) o.contact_id, o.id as reply_draft_id, o.created_at as reply_draft_created_at
    from public.outreach_log o where o.draft_status::text = 'pending_review' and o.touch_type::text = 'Follow up'
   order by o.contact_id, o.created_at desc)
select c.id as contact_id, c.team_id, c.contact_id as contact_ref, c.first_name, c.last_name, c.owner_user_id,
       c.outreach_status::text as outreach_status, c.chase_state, c.connection_status::text as connection_status,
       co.id as company_id, co.company_name, co.research_stage::text as research_stage,
       lr.last_reply, lo.last_out, lr.n_replies,
       case when lr.migrated_only then 'migrated' else 'live' end as source,
       (current_date - lr.last_reply) as days_waiting,
       r.reply_id, r.reply_channel, r.classification, r.excerpt as last_reply_excerpt,
       d.reply_draft_id, d.reply_draft_created_at, (d.reply_draft_id is not null) as has_reply_draft
  from public.contacts c
  join lr on lr.contact_id = c.id
  left join lo on lo.contact_id = c.id
  left join lastr r on r.contact_id = c.id
  left join draft d on d.contact_id = c.id
  left join public.companies co on co.id = c.company_id
 where c.archived_at is null
   and (lo.last_out is null or lr.last_reply >= lo.last_out)
   and c.outreach_status::text not in ('Do not contact','Opted out','Not relevant','Left company','Parked','Meeting booked')
   and exists (select 1 from public.fn_task_scope() s where s.team_id = c.team_id and (s.is_admin or c.owner_user_id = s.user_id));
grant select on public.v_replies_needing_answer to authenticated;
