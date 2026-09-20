-- 117 F18.2 + F18.9(b): the reply sweep's candidate function, and the ONE review queue everything in F18 uses.
-- Consent layer untouched: fn_evaluate_gates is not modified; the sweep calls it with requested='reply'.

-- The review queue: the single destination for anything that needs a human decision. Nothing merges,
-- drafts or changes because a row is here; a row only ASKS.
create table if not exists public.review_queue (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  kind text not null check (kind in ('company_fuzzy_match','company_duplicate','reply_answered_by_hand','reply_company_in_monday','reply_order_unknown','company_no_domain')),
  title text not null,
  detail text,
  company_id uuid references public.companies(id),
  other_company_id uuid references public.companies(id),
  contact_id uuid references public.contacts(id),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open','decided','later')),
  decision text,
  decided_by uuid,
  decided_at timestamptz,
  dedupe_key text not null,
  source text not null,
  created_at timestamptz not null default now(),
  unique (team_id, dedupe_key)
);
create index if not exists review_queue_open on public.review_queue (team_id, status, kind);
alter table public.review_queue enable row level security;
drop policy if exists review_queue_team_select on public.review_queue;
create policy review_queue_team_select on public.review_queue for select to authenticated
  using (team_id in (select team_id from public.team_members where user_id = auth.uid()));
drop policy if exists review_queue_team_update on public.review_queue;
create policy review_queue_team_update on public.review_queue for update to authenticated
  using (team_id in (select team_id from public.team_members where user_id = auth.uid()))
  with check (team_id in (select team_id from public.team_members where user_id = auth.uid()));
revoke all on public.review_queue from anon;

alter table public.team_settings add column if not exists reply_sweep_per_run integer not null default 5;

-- Who the sweep may draft for: replied, not archived (contact or company), last inbound not already
-- answered (no Follow up dated on or after it), no open reply hold in the review queue, and no open
-- Follow up draft. Oldest waiting first. The gates are evaluated by the engine, not here.
create or replace function public.fn_reply_candidates(p_team_id uuid, p_limit integer default 5)
returns table(contact_id uuid, company_id uuid, last_inbound date, inbound_channel text, days_waiting integer, connection_status text)
language sql stable set search_path to 'public','pg_temp' as $$
  with li as (
    select o.contact_id, max(o.touch_date) as last_in
      from public.outreach_log o
     where o.team_id = p_team_id and o.touch_type::text = 'Reply'
     group by o.contact_id)
  select c.id, c.company_id, li.last_in,
         (select o.channel::text from public.outreach_log o where o.contact_id = c.id and o.touch_type::text = 'Reply' order by o.touch_date desc, o.created_at desc limit 1),
         (current_date - li.last_in)::int, c.connection_status::text
    from public.contacts c
    join li on li.contact_id = c.id
    left join public.companies co on co.id = c.company_id
   where c.team_id = p_team_id and c.chase_state = 'replied'
     and c.archived_at is null and (co.id is null or co.archived_at is null)
     and not exists (select 1 from public.outreach_log f where f.contact_id = c.id and f.touch_type::text = 'Follow up'
                      and f.draft_status::text not in ('superseded','rejected') and f.send_status::text <> 'Cancelled'
                      and (f.touch_date >= li.last_in or f.send_status::text in ('Draft','Ready','Scheduled')))
     and not exists (select 1 from public.review_queue q where q.contact_id = c.id and q.status in ('open','later')
                      and q.kind in ('reply_answered_by_hand','reply_company_in_monday','reply_order_unknown'))
   order by li.last_in asc
   limit p_limit;
$$;
revoke all on function public.fn_reply_candidates(uuid, integer) from public, anon;
grant execute on function public.fn_reply_candidates(uuid, integer) to authenticated, service_role;

-- Seed the reply holds. (d) answered by hand on Mon 15 Sep; (e) company promoted to Monday; and replies
-- where an outbound Follow up shares the inbound's date, so the order cannot be told from the data.
insert into public.review_queue (team_id, kind, title, detail, contact_id, company_id, payload, dedupe_key, source)
select c.team_id,
       case when c.contact_id in ('P562','P256') then 'reply_answered_by_hand'
            when co.archive_reason = 'promoted_to_monday' then 'reply_company_in_monday'
            else 'reply_order_unknown' end,
       c.first_name || ' ' || c.last_name || ' (' || coalesce(co.company_name, '?') || ') replied; no reply draft will be generated',
       case when c.contact_id in ('P562','P256') then 'Oliver answered by hand on 15 Sep 2026; the system has no record of it. Record the manual send (docs/procedures/recording-a-manual-send.md) or confirm nothing further is owed.'
            when co.archive_reason = 'promoted_to_monday' then 'Company is promoted to Monday; the conversation belongs to the deal. Confirm whether a reply from the Lake is wanted.'
            else 'An outbound Follow up carries the same date as their last reply, so the data cannot say who spoke last. Check the thread.' end,
       c.id, c.company_id,
       jsonb_build_object('contact_ref', c.contact_id, 'last_inbound', li.last_in, 'archive_reason', co.archive_reason),
       'reply_hold:' || c.contact_id, 'f18_2_seed'
  from public.contacts c
  join (select contact_id, max(touch_date) last_in from public.outreach_log where touch_type::text = 'Reply' group by 1) li on li.contact_id = c.id
  left join public.companies co on co.id = c.company_id
 where c.chase_state = 'replied'
   and ( c.contact_id in ('P562','P256')
      or co.archive_reason = 'promoted_to_monday'
      or exists (select 1 from public.outreach_log f where f.contact_id = c.id and f.touch_type::text = 'Follow up'
                  and f.send_status::text = 'Sent' and f.touch_date = li.last_in) )
on conflict (team_id, dedupe_key) do nothing;

-- F18.1(e) second regression, corrected: an UNSENT chaser must have a sent message on its own channel.
-- (Oliver's hand history holds sent chasers whose opener was on another channel; those are history, not defects.)
create or replace view public.v_regress_chaser_without_sent_initial with (security_invoker = true) as
select o.id, o.contact_ref, o.touch_type::text as touch_type, o.channel::text as channel, o.send_status::text as send_status, o.draft_status::text as draft_status
  from public.outreach_log o
 where o.touch_type::text in ('Chaser 1','Chaser 2','Chaser 3','Chase')
   and o.send_status::text in ('Draft','Ready','Scheduled') and o.draft_status::text in ('pending_review','approved')
   and not exists (select 1 from public.outreach_log s where s.contact_id = o.contact_id and s.channel = o.channel
                    and s.send_status::text = 'Sent' and s.touch_type::text not in ('Reply','Connection request') and s.id <> o.id);
