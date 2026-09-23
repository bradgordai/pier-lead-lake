-- 144 F22B.8: company state moves with its outreach, and a company can be PARKED with a written reason.
-- (a) i125 AUTOMATIC LABEL FLIPPING (companies.opportunity_status, forwards only, never backwards):
--       a Sent outbound MESSAGE to any contact (touch_type not Reply, not Connection request) : To Review / Prospect -> Contacted
--       a SALES reply from any contact                                                         : To Review / Prospect / Contacted -> Active Lead
--     A "sales reply" is any Reply whose classification is set and is NOT Left company / Wrong person / Referral /
--     Out of office / Do not contact / Not interested (a "no thanks" is not an active lead). The classification is
--     written just after the Reply row is inserted, so the trigger fires on that update.
--     Out of Scope and Partner are never touched. A connection request alone does not flip anything (it is an
--     invitation, not a message): 68 companies have only CRs sent — reported for Brad, not flipped.
--     Mislabelled companies are fixed in this migration (before-values in migration_audit phase f22b_8a_flip).
-- (b) i127 PARK: parked_at, park_reason (required), parked_by, park_review_after. Parked = fits Pier but is not a
--     priority now (A1 Telekom); Out of Scope = does not fit. A parked company leaves the research queue and Today
--     until park_review_after, then it AUTO-PROMOTES back into the research queue flagged park_expired.
--     X = 6 MONTHS from the last research refresh (or from the parking date if it was never refreshed) — PROPOSED,
--     change park_review_after's default here if Brad wants another value.
--     NOT DONE (consent layer): the chase engine can still draft for a parked company's contacts; blocking that needs
--     a new gate in fn_evaluate_gates, which this batch must not touch. Flagged for Brad.
do $$ declare b jsonb; begin
  select jsonb_object_agg(coalesce(opportunity_status::text,'NULL'), n) into b from
    (select opportunity_status, count(*) n from public.companies group by 1) x;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, detail)
  values ('f22b-2026-09-23', 'f22b_8a_flip', 'companies', 'counts', 'opportunity_status_before', b);
end $$;

create or replace function public.fn_company_state_flip() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.company_id is null then return new; end if;
  if new.touch_type::text not in ('Reply','Connection request') and new.send_status::text = 'Sent'
     and (tg_op = 'INSERT' or old.send_status is distinct from new.send_status) then
    update public.companies set opportunity_status = 'Contacted'
     where id = new.company_id and opportunity_status::text in ('To Review','Prospect');
  elsif new.touch_type::text = 'Reply' and new.reply_classification is not null
     and (tg_op = 'INSERT' or old.reply_classification is distinct from new.reply_classification)
     and new.reply_classification::text not in ('Left company','Wrong person','Referral','Out of office','Do not contact','Not interested') then
    update public.companies set opportunity_status = 'Active Lead'
     where id = new.company_id and opportunity_status::text in ('To Review','Prospect','Contacted');
  end if;
  return new;
end $$;
drop trigger if exists trg_company_state_flip on public.outreach_log;
create trigger trg_company_state_flip after insert or update of send_status, reply_classification on public.outreach_log
  for each row execute function public.fn_company_state_flip();

-- Backfill the companies already mislabelled against their own history.
with rep as (
  select distinct o.company_id from public.outreach_log o
   where o.touch_type::text = 'Reply' and o.reply_classification is not null
     and o.reply_classification::text not in ('Left company','Wrong person','Referral','Out of office','Do not contact','Not interested')),
msg as (
  select distinct o.company_id from public.outreach_log o
   where o.send_status::text = 'Sent' and o.touch_type::text not in ('Reply','Connection request')),
chg as (
  select co.id, co.opportunity_status::text as before,
         case when co.id in (select company_id from rep) and co.opportunity_status::text in ('To Review','Prospect','Contacted') then 'Active Lead'
              when co.id in (select company_id from msg) and co.opportunity_status::text in ('To Review','Prospect') then 'Contacted' end as after
    from public.companies co where co.archived_at is null),
aud as (
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22b-2026-09-23', 'f22b_8a_flip', 'companies', c.id::text, 'opportunity_status_forward', c.id,
         jsonb_build_object('before', c.before, 'after', c.after)
    from chg c where c.after is not null
  returning target_id, detail->>'after' as after)
update public.companies co set opportunity_status = a.after::opportunity_status from aud a where co.id = a.target_id;

do $$ declare b jsonb; back int; begin
  select jsonb_object_agg(coalesce(opportunity_status::text,'NULL'), n) into b from
    (select opportunity_status, count(*) n from public.companies group by 1) x;
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, detail)
  values ('f22b-2026-09-23', 'f22b_8a_flip', 'companies', 'counts', 'opportunity_status_after', b);
  -- no company moved backwards: every change is To Review/Prospect/Contacted -> a later state
  select count(*) into back from public.migration_audit
   where phase = 'f22b_8a_flip' and action = 'opportunity_status_forward'
     and not ((detail->>'after' = 'Contacted' and detail->>'before' in ('To Review','Prospect'))
           or (detail->>'after' = 'Active Lead' and detail->>'before' in ('To Review','Prospect','Contacted')));
  if back <> 0 then raise exception '% backward moves', back; end if;
end $$;

-- (b) PARK
alter table public.companies add column if not exists parked_at timestamptz;
alter table public.companies add column if not exists park_reason text;
alter table public.companies add column if not exists parked_by uuid;
alter table public.companies add column if not exists park_review_after date;
alter table public.companies drop constraint if exists companies_park_reason_required;
alter table public.companies add constraint companies_park_reason_required
  check (parked_at is null or length(btrim(coalesce(park_reason, ''))) > 0);
create or replace function public.fn_company_park_stamp() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.parked_at is not null and (tg_op = 'INSERT' or old.parked_at is null) then
    new.parked_by := coalesce(new.parked_by, auth.uid());
    new.park_review_after := coalesce(new.park_review_after, (coalesce(new.last_refreshed, new.parked_at::date) + interval '6 months')::date);
  elsif new.parked_at is null then
    new.park_reason := null; new.parked_by := null; new.park_review_after := null;
  end if;
  return new;
end $$;
drop trigger if exists trg_company_park_stamp on public.companies;
create trigger trg_company_park_stamp before insert or update of parked_at on public.companies
  for each row execute function public.fn_company_park_stamp();

-- Research queue: a parked company is out until park_review_after, then back in flagged park_expired.
-- (Columns appended at the end; everything above is the 137 definition verbatim except research_priority_rank.)
create or replace view public.v_company_score with (security_invoker = true) as
select co.id as company_id, co.team_id, co.company_id as company_ref, co.company_name, co.country, co.priority,
       co.research_stage, co.opportunity_status, co.last_refreshed, co.archived_at,
       s.score, s.assessed_points, s.research_upside,
       s.gwp_points, s.gwp_assessed, s.gwp_value_gbp, s.gwp_band, s.size_rung, s.devices_per_month, s.gwp_basis,
       s.switch_points, s.switch_assessed, s.switch_gap, s.switch_lockin, s.switchability, s.switch_basis,
       s.territory_points, s.territory_assessed, s.territory_rank, s.territory_in_table, s.territory_basis,
       s.wedge_points, s.wedge_assessed, s.wedge_tests, s.wedge_stale, s.wedge_basis,
       s.source as score_source, s.model_version, s.scored_at, s.needs_rescore, s.rescore_reason,
       (s.company_id is not null) as is_scored,
       (s.company_id is not null and (s.needs_rescore or (co.last_refreshed is not null and co.last_refreshed > s.scored_at::date))) as score_stale,
       r.reach, r.reach_rung, r.contacts_counted, r.contacts_live, r.contacts_warm, r.contacts_open,
       case when co.parked_at is not null and co.park_review_after > current_date then null
            else case co.priority::text when 'P0' then 0 when 'P1' then 1 when 'P2' then 2 when 'P3' then 3 when 'OoS' then null when 'Competitor' then null else 4 end
       end as research_priority_rank,
       coalesce(s.research_upside, 100) as research_upside_for_queue,
       co.parked_at, co.park_reason, co.park_review_after,
       (co.parked_at is not null and co.park_review_after <= current_date) as park_expired
  from public.companies co
  left join public.company_scores s on s.company_id = co.id
  left join public.v_company_reach r on r.company_id = co.id;

-- Today: a parked company's people leave v_today_todo until the park is reviewed (143 definition + one filter).
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
     and not (co.parked_at is not null and co.park_review_after > current_date)   -- F22B.8(b): parked companies leave Today
     and not (st.snoozed_until is not null and st.snoozed_until > now() and st.broken_at is null)),
per_person as (
  select distinct on (contact_id) * from scored
   order by contact_id, returned desc, kind_rank, item_since)
select p.*,
       row_number() over (partition by p.team_id order by p.returned desc, p.over_allowance, p.kind_rank,
                          floor(p.score / 20.0) desc nulls last, p.reach_rung desc nulls last, p.item_since) as position
  from per_person p;
