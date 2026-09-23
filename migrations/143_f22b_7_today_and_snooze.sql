-- 143 F22B.7: Today, rebuilt as four sections, with a snooze that actually works.
--
-- SNOOZE (today_item_state, one row per item):
--   - snooze_days 1..14 (check); snoozed_until = snoozed_at + days (trigger). While snoozed the item is ABSENT from
--     v_today_todo, so it also leaves every count built on it.
--   - On expiry, or when the snooze BREAKS, the item comes back at the TOP of its section marked returned, with its
--     original wait still visible (item_since is the draft's / reply's own date, never reset by the snooze).
--   - DONE retires the item permanently (done_at, done_by, done_reason). A new event for the person is a NEW item key,
--     so a later reply is never swallowed by an old Done.
--   - EARLY BREAK, the point of the feature: a new inbound message (outreach_log Reply insert), a connection accepted
--     (contacts.connection_status -> Accepted) or any outreach_status change breaks every active snooze for that person
--     (broken_at, break_reason). Triggers below.
-- ITEM KEYS: 'draft:<outreach_log id>' for an open draft; 'reply:<outreach_log id>' for a reply with no open draft.
--
-- SECTION 1 v_today_todo: one row per PERSON (their top item), ordered:
--   returned first; items whose channel allowance is spent go to the bottom (they return to the pool and are
--   re-ranked on every read, never rolled over in a stored order); then replies > chasers > first DM after CR >
--   InMail openers > connection requests; then company score band (score/20, unscored last); then reach rung;
--   then the oldest wait. Allowances read team_settings: CRs per ISO week vs weekly_cr_target, DMs per ISO week vs
--   weekly_dm_cap, InMails per calendar month vs monthly_inmail_grant (the limits send-approved-draft works to).
-- SECTIONS 2-4: v_today_you_did (a person's own approve / reject / edit / send in the last 24 h, from audit_log),
--   v_today_picked_up (replies filed, connections accepted, new leads, last 24 h), v_today_system_did (drafts created
--   by touch type, refusals by reason code, last 24 h). Owner filter is the UI's (Oliver only for now).

create table if not exists public.today_item_state (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  contact_id uuid not null references public.contacts(id) on delete cascade,
  item_key text not null,
  snoozed_at timestamptz,
  snooze_days int check (snooze_days between 1 and 14),
  snoozed_until timestamptz,
  snoozed_by uuid,
  broken_at timestamptz,
  break_reason text,
  done_at timestamptz,
  done_by uuid,
  done_reason text,
  created_at timestamptz not null default now(),
  unique (team_id, item_key)
);
create index if not exists today_item_state_contact_idx on public.today_item_state (contact_id);
alter table public.today_item_state enable row level security;
drop policy if exists today_item_state_team_all on public.today_item_state;
create policy today_item_state_team_all on public.today_item_state for all to authenticated
  using (team_id in (select fn_user_teams())) with check (team_id in (select fn_user_teams()));

create or replace function public.fn_today_item_state_stamp() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.snooze_days is not null and (tg_op = 'INSERT' or new.snooze_days is distinct from old.snooze_days
       or new.snoozed_at is distinct from old.snoozed_at) then
    new.snoozed_at := coalesce(new.snoozed_at, now());
    new.snoozed_until := new.snoozed_at + make_interval(days => new.snooze_days);
    new.snoozed_by := coalesce(new.snoozed_by, auth.uid());
    new.broken_at := null; new.break_reason := null;          -- a fresh snooze starts unbroken
  end if;
  if new.done_at is not null and (tg_op = 'INSERT' or old.done_at is null) then
    new.done_by := coalesce(new.done_by, auth.uid());
  end if;
  return new;
end $$;
drop trigger if exists trg_today_item_state_stamp on public.today_item_state;
create trigger trg_today_item_state_stamp before insert or update on public.today_item_state
  for each row execute function public.fn_today_item_state_stamp();

-- EARLY BREAK
create or replace function public.fn_today_break_snooze(p_contact uuid, p_reason text) returns void
language sql set search_path to 'public', 'pg_temp' as $$
  update public.today_item_state set broken_at = now(), break_reason = p_reason
   where contact_id = p_contact and snoozed_until > now() and broken_at is null and done_at is null;
$$;
create or replace function public.fn_today_break_on_reply() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.touch_type::text = 'Reply' and new.contact_id is not null then
    perform public.fn_today_break_snooze(new.contact_id, 'new inbound message ' || to_char(now(), 'YYYY-MM-DD'));
  end if;
  return new;
end $$;
drop trigger if exists trg_today_break_on_reply on public.outreach_log;
create trigger trg_today_break_on_reply after insert on public.outreach_log
  for each row execute function public.fn_today_break_on_reply();
create or replace function public.fn_today_break_on_contact_change() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.connection_status is distinct from old.connection_status and new.connection_status::text = 'Accepted' then
    perform public.fn_today_break_snooze(new.id, 'connection accepted ' || to_char(now(), 'YYYY-MM-DD'));
  elsif new.outreach_status is distinct from old.outreach_status then
    perform public.fn_today_break_snooze(new.id, 'status changed to ' || coalesce(new.outreach_status::text, 'none'));
  end if;
  return new;
end $$;
drop trigger if exists trg_today_break_on_contact_change on public.contacts;
create trigger trg_today_break_on_contact_change after update of connection_status, outreach_status on public.contacts
  for each row execute function public.fn_today_break_on_contact_change();

-- SECTION 1
create or replace view public.v_today_todo with (security_invoker = true) as
with ts as (select team_id, weekly_cr_target, weekly_dm_cap, monthly_inmail_grant from public.team_settings),
used as (
  select t.team_id,
    count(*) filter (where t.touch_type::text = 'Connection request' and date_trunc('week', t.sent_on) = date_trunc('week', current_date)) as cr_week,
    count(*) filter (where t.channel::text = 'LinkedIn DM' and date_trunc('week', t.sent_on) = date_trunc('week', current_date)) as dm_week,
    count(*) filter (where t.channel::text = 'LinkedIn inMail' and date_trunc('month', t.sent_on) = date_trunc('month', current_date)) as inmail_month
  from public.v_sent_touches t group by t.team_id),
last_in as (
  select distinct on (o.contact_id) o.contact_id, o.id, o.touch_date, o.created_at, o.reply_classification::text as cls
    from public.outreach_log o where o.touch_type::text = 'Reply' order by o.contact_id, o.touch_date desc, o.created_at desc),
last_out as (
  select o.contact_id, max(o.touch_date) as d from public.outreach_log o
   where o.touch_type::text <> 'Reply' and o.send_status::text = 'Sent' group by o.contact_id),
drafts as (
  select 'draft:' || o.id as item_key, o.team_id, o.contact_id, o.id as outreach_log_id, o.touch_type::text as touch_type,
         o.channel::text as channel, o.draft_status::text as draft_state, o.created_at as item_since,
         case when o.touch_type::text in ('Follow up','Reply') then 'reply'
              when o.touch_type::text in ('Chaser 1','Chaser 2','Chaser 3','Chase') then 'chaser'
              when o.touch_type::text = 'Connection request' then 'connection_request'
              when o.channel::text = 'LinkedIn inMail' then 'inmail_opener'
              else 'first_message' end as kind
    from public.outreach_log o
   where o.draft_status::text in ('pending_review','approved') and o.send_status::text in ('Draft','Ready')),
replies as (
  select 'reply:' || li.id as item_key, c.team_id, c.id as contact_id, li.id as outreach_log_id, 'Reply'::text as touch_type,
         null::text as channel, 'no draft'::text as draft_state, li.created_at as item_since,
         case when li.cls in ('Left company','Wrong person','Referral') then 'reply_non_sales' else 'reply' end as kind
    from public.contacts c join last_in li on li.contact_id = c.id
    left join last_out lo on lo.contact_id = c.id
   where c.chase_state = 'replied' and (lo.d is null or li.touch_date >= lo.d)
     and not exists (select 1 from drafts d where d.contact_id = c.id)),
items as (select * from drafts union all select * from replies),
scored as (
  select i.*, c.first_name, c.last_name, c.owner_user_id, c.company_id, co.company_name,
         s.score, r.reach, r.reach_rung,
         st.snoozed_until, st.broken_at, st.break_reason, st.done_at,
         (st.snoozed_until is not null and st.done_at is null and (st.snoozed_until <= now() or st.broken_at is not null)) as returned,
         case when st.broken_at is not null then st.break_reason when st.snoozed_until <= now() then 'snooze expired' end as returned_reason,
         case i.kind when 'reply' then 1 when 'reply_non_sales' then 1 when 'chaser' then 2 when 'first_message' then 3
                     when 'inmail_opener' then 4 when 'connection_request' then 5 else 6 end as kind_rank,
         case when i.kind = 'connection_request' then coalesce(u.cr_week, 0) >= coalesce(ts.weekly_cr_target, 80)
              when i.channel = 'LinkedIn DM' and i.kind not in ('reply','reply_non_sales') then coalesce(u.dm_week, 0) >= coalesce(ts.weekly_dm_cap, 15)
              when i.channel = 'LinkedIn inMail' and i.kind not in ('reply','reply_non_sales') then coalesce(u.inmail_month, 0) >= coalesce(ts.monthly_inmail_grant, 50)
              else false end as over_allowance
    from items i
    join public.contacts c on c.id = i.contact_id and c.archived_at is null
    left join public.companies co on co.id = c.company_id
    left join public.company_scores s on s.company_id = c.company_id
    left join public.v_company_reach r on r.company_id = c.company_id
    left join public.today_item_state st on st.team_id = i.team_id and st.item_key = i.item_key
    left join ts on ts.team_id = i.team_id
    left join used u on u.team_id = i.team_id
   where not (st.done_at is not null)
     and not (st.snoozed_until is not null and st.snoozed_until > now() and st.broken_at is null)),
per_person as (
  select distinct on (contact_id) * from scored
   order by contact_id, returned desc, kind_rank, item_since)
select p.*,
       row_number() over (partition by p.team_id order by p.returned desc, p.over_allowance, p.kind_rank,
                          floor(p.score / 20.0) desc nulls last, p.reach_rung desc nulls last, p.item_since) as position
  from per_person p;

-- SECTION 2
create or replace view public.v_today_you_did with (security_invoker = true) as
select a.team_id, a.actor_user_id, a.created_at as event_at, a.entity_id as outreach_log_id,
       (a.after_value->>'contact_id')::uuid as contact_id, a.after_value->>'touch_type' as touch_type,
       case when a.after_value->>'draft_status' = 'approved' and a.before_value->>'draft_status' is distinct from 'approved' then 'approved'
            when a.after_value->>'draft_status' = 'rejected' and a.before_value->>'draft_status' is distinct from 'rejected' then 'rejected'
            when a.after_value->>'send_status' is distinct from a.before_value->>'send_status'
                 and a.after_value->>'send_status' in ('Scheduled','Sent') then 'sent'
            when a.after_value->>'message_body' is distinct from a.before_value->>'message_body' then 'edited' end as action
  from public.audit_log a
 where a.entity_type = 'outreach_log' and a.actor_user_id is not null and a.created_at > now() - interval '24 hours'
   and (a.after_value->>'draft_status' is distinct from a.before_value->>'draft_status'
        or a.after_value->>'send_status' is distinct from a.before_value->>'send_status'
        or a.after_value->>'message_body' is distinct from a.before_value->>'message_body');

-- SECTION 3
create or replace view public.v_today_picked_up with (security_invoker = true) as
select o.team_id, o.created_at as event_at, 'reply'::text as kind, o.contact_id, o.reply_classification::text as detail
  from public.outreach_log o where o.touch_type::text = 'Reply' and o.created_at > now() - interval '24 hours'
union all
select c.team_id, c.cr_accepted_at, 'connection_accepted', c.id, c.connection_status::text
  from public.contacts c where c.cr_accepted_at > now() - interval '24 hours'
union all
select c.team_id, c.created_at, 'new_lead', c.id, coalesce(c.source_list, 'added')
  from public.contacts c where c.created_at > now() - interval '24 hours';

-- SECTION 4
create or replace view public.v_today_system_did with (security_invoker = true) as
select o.team_id, o.created_at as event_at, 'draft_created'::text as kind, o.contact_id, o.touch_type::text as detail
  from public.outreach_log o where o.agent_produced and o.created_at > now() - interval '24 hours'
union all
select r.team_id, r.created_at, 'refusal', r.contact_id, r.reason_code
  from public.refusals r where r.created_at > now() - interval '24 hours';

grant select on public.v_today_todo, public.v_today_you_did, public.v_today_picked_up, public.v_today_system_did to authenticated;
