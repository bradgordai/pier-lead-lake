-- 111 F17.4 (i094): connection state carries a source and a date; Pfeiffer corrected; contradictions surfaced.
alter table public.contacts add column if not exists connection_status_source text;
alter table public.contacts add column if not exists connection_status_at timestamptz;
alter table public.contacts add column if not exists connection_status_evidence text;
comment on column public.contacts.connection_status_source is
  'Who or what last set connection_status. Accepted is only trustworthy from a positive accept signal matched on LinkedIn URL or slug (phantom_recently_connected, salesnav_export). A name match or absence from a list is not an accept.';

-- Backfill what is knowable. Everything migrated from the workbook is attributed to it, not to a platform signal.
update public.contacts set connection_status_source = case
    when next_action ilike '%CONNECTION STATUS CORRECTED%' then 'workbook_correction_20260902_recently_accepted_drop'
    when legacy_source is not null then 'workbook_migration:' || legacy_source
    else 'unattributed' end,
  connection_status_at = coalesce(migrated_at, created_at)
where connection_status_source is null;

-- Pfeiffer P706: Sales Navigator shows 2nd degree, request sent 2026-08-28, still pending. The 2 Sep
-- correction was a SURNAME collision with Veronika Pfeiffer (P307), who did accept. The note on the row
-- says that wrong match "was refused once already"; it was then applied anyway.
update public.contacts set
  connection_status = 'Request sent', connection_level = '2nd degree',
  connection_status_source = 'manual_verified_salesnav:oliver_2026-09-17', connection_status_at = now(),
  connection_status_evidence = 'Sales Navigator 17 Sep 2026: 2nd degree, invitation sent 2026-08-28, pending. Previous value Accepted / 1st degree came from a surname match to Veronika Pfeiffer (P307) in the 2 Sep workbook correction.',
  next_action = 'CR pending since 2026-08-28. No free DM exists. [F17.4 2026-09-18: connection status corrected Accepted -> Request sent; the earlier "corrected" note was a surname collision with Veronika Pfeiffer P307.]',
  next_action_date = null
where contact_id = 'P706' and connection_status::text = 'Accepted';

-- Every future change of connection_status is stamped. A writer that names its source keeps it; one that
-- does not is recorded as such, so an unattributed Accepted is visible instead of silent.
create or replace function public.fn_stamp_connection_status() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if new.connection_status is distinct from old.connection_status then
    new.connection_status_at := now();
    if new.connection_status_source is not distinct from old.connection_status_source then
      new.connection_status_source := 'unattributed:' || coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role', current_user);
      new.connection_status_evidence := null;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_stamp_connection_status on public.contacts;
create trigger trg_stamp_connection_status before update on public.contacts
  for each row execute function public.fn_stamp_connection_status();

-- Two fields describing one person must not disagree in silence.
create or replace view public.v_contact_state_conflicts with (security_invoker = true) as
select c.id, c.team_id, c.contact_id as contact_ref, c.first_name, c.last_name, c.company_id,
       c.connection_status::text as connection_status, c.connection_level, c.outreach_status::text as outreach_status,
       c.connection_status_source, c.connection_status_at, x.conflict
from public.contacts c
cross join lateral (values
  (case when c.connection_status::text = 'Accepted' and c.outreach_status::text in ('To contact','Not started')
         and not exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.channel::text = 'LinkedIn DM' and o.send_status::text = 'Sent')
        then 'accepted_but_never_messaged' end),
  (case when c.connection_status::text in ('Accepted','Already connected') and c.connection_level is not null and c.connection_level <> '1st degree'
        then 'connected_but_not_1st_degree' end),
  (case when c.connection_status::text in ('Request sent','Not connected','Withdrawn','Ignored') and c.connection_level = '1st degree'
        then '1st_degree_but_not_connected' end),
  (case when c.connection_status::text = 'Accepted' and (c.connection_status_source is null or c.connection_status_source like 'unattributed%' or c.connection_status_source like 'workbook_correction%')
        then 'accepted_without_positive_signal' end)
) as x(conflict)
where c.archived_at is null and x.conflict is not null;
grant select on public.v_contact_state_conflicts to authenticated;
