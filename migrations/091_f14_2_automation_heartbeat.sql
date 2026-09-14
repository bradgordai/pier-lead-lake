-- 091 F14.2 (2026-09-14): an automation heartbeat. Two Make watchers were dead 9-14 Sep and nothing said so.
create table if not exists public.automation_heartbeat (
  source text primary key,
  team_id uuid not null default 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972',
  label text not null,
  interval_minutes int not null default 240,
  grace_minutes int not null default 480,
  last_seen_at timestamptz,
  last_payload_rows int,
  consecutive_failures int not null default 0,
  last_error text,
  last_failure_at timestamptz,
  updated_at timestamptz not null default now()
);
comment on table public.automation_heartbeat is 'F14.2: one row per named automation. Stamped by the edge function on every successful call. Silent longer than interval + grace = raise.';
alter table public.automation_heartbeat enable row level security;
drop policy if exists automation_heartbeat_team on public.automation_heartbeat;
create policy automation_heartbeat_team on public.automation_heartbeat for select to authenticated using (team_id in (select fn_user_teams()));

create or replace function public.fn_heartbeat(p_source text, p_rows int default null, p_ok boolean default true, p_error text default null)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if p_ok then
    update public.automation_heartbeat
       set last_seen_at = now(), last_payload_rows = coalesce(p_rows, last_payload_rows), consecutive_failures = 0, updated_at = now()
     where source = p_source;
  else
    update public.automation_heartbeat
       set consecutive_failures = consecutive_failures + 1, last_error = left(p_error, 500), last_failure_at = now(), updated_at = now()
     where source = p_source;
  end if;
  if not found then
    raise exception 'automation_heartbeat: unknown source %', p_source using errcode = 'foreign_key_violation';
  end if;
end $$;
revoke all on function public.fn_heartbeat(text, int, boolean, text) from public, anon, authenticated;
grant execute on function public.fn_heartbeat(text, int, boolean, text) to service_role;

insert into public.automation_heartbeat (source, label, interval_minutes, grace_minutes) values
  ('inbox_watcher', 'Inbox watcher (capture-and-classify-reply)', 240, 480),
  ('connection_watcher', 'Connection watcher (update-contact-on-cr-accepted)', 240, 480),
  ('sales_nav_watcher', 'Sales Nav watcher (upsert-contact-from-sales-nav)', 240, 480)
on conflict (source) do nothing;

-- Backfill from the most recent real row each source produced, so the panel tells the truth now.
update public.automation_heartbeat h set last_seen_at = x.ts from (
  select 'inbox_watcher' src, greatest((select max(created_at) from public.outreach_log where touch_id like 'reply-%' or touch_id like 'inbox-%'), (select max(created_at) from public.unmatched_replies)) ts
  union all select 'connection_watcher', (select max(updated_at) from public.contacts where connection_status::text = 'Accepted')
  union all select 'sales_nav_watcher', (select max(greatest(created_at, updated_at)) from public.contacts where url_provenance->'linkedin_sales_nav_url'->>'source' = 'watcher')
) x where x.src = h.source and x.ts is not null;

create or replace view public.v_automation_health with (security_invoker = true) as
select source, label, team_id, last_seen_at, last_payload_rows, consecutive_failures, last_error, last_failure_at,
       interval_minutes + grace_minutes as threshold_minutes,
       (extract(epoch from (now() - last_seen_at)) / 60)::int as silent_minutes,
       (last_seen_at is null or now() - last_seen_at > make_interval(mins => interval_minutes + grace_minutes)) as is_silent
  from public.automation_heartbeat;
grant select on public.v_automation_health to authenticated;
