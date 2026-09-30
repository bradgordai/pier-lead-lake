-- 150 F23 Task 2a (as amended by Brad, 30 Sep): the same-company check is a FLAG, never a refusal.
-- group_sibling_engaged covers LINKED companies only (fn_company_group_pairs R1-R3 on parent_group, Monday deals,
-- sibling opportunity_status). Nothing looked at colleagues at the SAME company_id: The Very Group and Rebuy each had
-- 5 people first-approached on one day, and both mobileup contacts were InMailed 44 seconds apart and both blocked.
--
-- fn_company_already_approached(team, contact, requested) -> (flagged, colleague, approached_at, colleague_contact_id)
--   flagged = another contact at the same company_id has a Sent first approach (touch_type 'Initial message' or
--   'Other'; NOTE the brief's 'Cold InMail' is not a touch_type value: a cold InMail is 'Initial message' on
--   channel 'LinkedIn inMail') with sent_at_actual NOT NULL, and that colleague has not replied since.
--   Chasers and replies are exempt (p_requested 'chaser' / 'reply' never flag). The most recent such colleague is named.
--   The column is called 'flagged' (the brief said 'blocked') because nothing is refused.
-- v_draft_company_flags: the flag for every OPEN draft (Draft/Ready + pending_review/approved), for the draft card.
-- NOT added to fn_evaluate_gates (Task 2b cancelled). Nothing is refused or suppressed.
-- LIMIT: sends before sent_at_actual existed (legacy/July rows, e.g. the mobileup InMails) do not count.

create or replace function public.fn_company_already_approached(p_team_id uuid, p_contact_id uuid, p_requested text)
returns table (flagged boolean, colleague text, approached_at timestamptz, colleague_contact_id uuid)
language sql stable set search_path to 'public', 'pg_temp' as $$
  with me as (
    select c.id, c.company_id from public.contacts c where c.id = p_contact_id and c.team_id = p_team_id),
  approached as (
    select o.contact_id, min(o.sent_at_actual) as first_at
      from public.outreach_log o join public.contacts cc on cc.id = o.contact_id, me
     where o.team_id = p_team_id and cc.company_id = me.company_id and cc.id <> me.id
       and o.send_status::text = 'Sent' and o.sent_at_actual is not null
       and o.touch_type::text in ('Initial message', 'Other')
     group by o.contact_id),
  unanswered as (
    select a.contact_id, a.first_at from approached a
     where not exists (select 1 from public.outreach_log r where r.contact_id = a.contact_id
                        and r.touch_type::text = 'Reply' and coalesce(r.touch_date::timestamptz, r.created_at) >= a.first_at::date))
  select true, trim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')), u.first_at, u.contact_id
    from unanswered u join public.contacts c on c.id = u.contact_id
   where coalesce(p_requested, '') not in ('chaser', 'reply')
     and exists (select 1 from me where me.company_id is not null)
   order by u.first_at desc
   limit 1;
$$;
comment on function public.fn_company_already_approached(uuid, uuid, text) is
  'F23.2a FLAG (not a gate): a colleague at the same company_id got a real first approach and has not replied. Chasers and replies exempt. Returns no row when not flagged.';

create or replace view public.v_draft_company_flags with (security_invoker = true) as
select o.id as outreach_log_id, o.team_id, o.contact_id, o.touch_type::text as touch_type,
       f.flagged, f.colleague, f.approached_at, f.colleague_contact_id,
       'A colleague at this company, ' || f.colleague || ', was approached on '
         || to_char(f.approached_at at time zone 'Europe/London', 'DD Mon YYYY') || ' and has not replied.' as flag_text
  from public.outreach_log o
  cross join lateral public.fn_company_already_approached(o.team_id, o.contact_id,
      case when o.touch_type::text like 'Chaser%' or o.touch_type::text = 'Chase' then 'chaser'
           when o.touch_type::text in ('Follow up', 'Reply') then 'reply'
           else 'initial_message' end) f
 where o.send_status::text in ('Draft', 'Ready') and o.draft_status::text in ('pending_review', 'approved');
grant select on public.v_draft_company_flags to authenticated;
