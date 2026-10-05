-- 170 F26 Task 5: v_cr_allowance_today. The count of connection requests sent today, from the extractor's own data
-- (so it includes everything Oliver sends by hand on LinkedIn, inside or outside this system), plus the CRs logged
-- here AFTER the extractor last read the list (which that read cannot contain yet).
--
-- Fails CLOSED: if the newest extractor run is older than 6 hours, or none exists, sent_today / sent_this_week /
-- remaining_today are NULL and state = 'stale'. The dispatcher treats NULL as stop, never as zero.
--
-- Counting rule from the labels (minimum age at extraction, never a date):
--   today     = min age 0 ("N minutes/hours ago"). An "hours ago" label read early in the day may be yesterday's
--               request; counting it today over-counts, which is the safe direction for a cap.
--   this week = min age < 7 (rolling seven days, LinkedIn's own weekly window).
-- Caps: 20 a day, 100 a week (the brief). remaining_today = least(20 - today, 100 - week), floored at 0.

create or replace view public.v_cr_allowance_today with (security_invoker = true) as
with latest as (
  select distinct on (r.team_id) r.team_id, r.id as run_id, r.extracted_at, r.received_at
    from public.cr_extractor_runs r
   where r.row_count > 0
   order by r.team_id, r.extracted_at desc nulls last, r.received_at desc
),
teams as (select t.id as team_id from public.teams t),
x as (
  select tm.team_id, l.run_id, l.extracted_at,
         (l.extracted_at is null or l.extracted_at < now() - interval '6 hours') as stale,
         (select count(*) from public.cr_extractor_rows w where w.run_id = l.run_id and w.min_age_days = 0) as extractor_today,
         (select count(*) from public.cr_extractor_rows w where w.run_id = l.run_id and w.min_age_days < 7) as extractor_week,
         (select count(*) from public.outreach_log o
           where o.team_id = tm.team_id and o.touch_type::text = 'Connection request' and o.send_status::text = 'Sent'
             and coalesce(o.sent_at_actual, o.updated_at) > coalesce(l.extracted_at, '-infinity'::timestamptz)
             and coalesce(o.sent_at_actual, o.updated_at) >= date_trunc('day', now())) as logged_today_after_read,
         (select count(*) from public.outreach_log o
           where o.team_id = tm.team_id and o.touch_type::text = 'Connection request' and o.send_status::text = 'Sent'
             and coalesce(o.sent_at_actual, o.updated_at) > coalesce(l.extracted_at, '-infinity'::timestamptz)
             and coalesce(o.sent_at_actual, o.updated_at) >= now() - interval '7 days') as logged_week_after_read
    from teams tm left join latest l on l.team_id = tm.team_id
)
select x.team_id,
       x.run_id as extractor_run_id,
       x.extracted_at as extractor_read_at,
       round(extract(epoch from (now() - x.extracted_at)) / 60)::int as extractor_age_minutes,
       x.stale,
       case when x.stale then null else x.extractor_today + x.logged_today_after_read end as sent_today,
       case when x.stale then null else x.extractor_week + x.logged_week_after_read end as sent_this_week,
       20 as daily_cap,
       100 as weekly_cap,
       case when x.stale then null
            else greatest(0, least(20 - (x.extractor_today + x.logged_today_after_read), 100 - (x.extractor_week + x.logged_week_after_read))) end as remaining_today,
       case when x.stale then 'stale'
            when x.extractor_today + x.logged_today_after_read > 20 or x.extractor_week + x.logged_week_after_read > 100 then 'over_cap'
            when x.extractor_today + x.logged_today_after_read = 20 or x.extractor_week + x.logged_week_after_read = 100 then 'at_cap'
            else 'ok' end as state
  from x;
comment on view public.v_cr_allowance_today is
  'F26.5: CRs sent today / this week from the Sent Request Extractor (min age 0 / <7) plus CRs logged after its last read. NULL counts and state=stale when the extractor data is older than 6 hours: the dispatcher stops on NULL.';
grant select on public.v_cr_allowance_today to authenticated;
revoke all on public.v_cr_allowance_today from anon;
