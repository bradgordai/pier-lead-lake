-- 135 F22A.8: manual intake runs. One row per "Refresh now" press. The chain is button -> Edge Function
-- intake-refresh -> PhantomBuster agents/launch -> phantom runs -> the phantom calls ITS OWN Make webhook -> Make posts
-- to Supabase. The Make webhook is never called directly. This table is what the Today strip reads for "running /
-- finished with N / failed: reason / nothing found", the 15 minute rate limit and the one-at-a-time lock.
create table if not exists public.intake_runs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  intake text not null check (intake in ('sales_nav_leads','connection_acceptances','sales_nav_inbox','linkedin_inbox')),
  agent_id text not null,
  container_id text,
  status text not null default 'launching' check (status in ('launching','running','finished','failed')),
  outcome text check (outcome in ('found','nothing_found','error')),
  result_count int,
  error text,
  launched_by uuid,
  launched_at timestamptz not null default now(),
  finished_at timestamptz
);
create index if not exists intake_runs_team_intake_idx on public.intake_runs (team_id, intake, launched_at desc);
alter table public.intake_runs enable row level security;
drop policy if exists intake_runs_team_read on public.intake_runs;
create policy intake_runs_team_read on public.intake_runs for select to authenticated
  using (team_id in (select fn_user_teams()));
-- Writes only through the Edge Function (service role). No client insert/update policy.
