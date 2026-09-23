-- 142 F22B.6: the feedback loop, stage two. Raw corrections become COMPACT, DURABLE rules — never raw rows in the prompt.
-- (a) voice_assets 'learned_corrections', layer 5, beside pier_rules .. voice_oliver. Its body is RENDERED from the
--     active rows of learned_correction_rules, grouped by touch_type and channel so the drafter can load only what applies.
--     NOT WIRED INTO THE DRAFTER (F22B.6(g)): generate-draft-from-context does not read it until Brad approves.
-- (b) learned_correction_runs: one row per distillation (what it read, what it produced, the version before/after,
--     the character count against the ceiling, the cost). The distiller is the Edge Function distill-learned-corrections.
-- (e) learned_correction_rules: each rule with the feedback rows that produced it (source_feedback_ids) and, for the
--     first run, the historic rejected drafts it came from (source_touch_ids). Brad and Oliver can edit or delete any
--     rule (team update policy); a deleted rule is kept with status 'deleted', never removed.
-- The weekly distillation job is created INACTIVE. The first run is manual and Brad approves before it is switched on.
create table if not exists public.learned_correction_runs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null default 'running' check (status in ('running','done','failed','dry_run')),
  triggered_by text not null default 'manual',
  feedback_considered int not null default 0,
  legacy_considered int not null default 0,
  writing_rules int,
  system_issues jsonb,
  version_before text,
  version_after text,
  chars int,
  char_ceiling int,
  estimated_cost_gbp numeric,
  error text,
  output jsonb
);
alter table public.learned_correction_runs enable row level security;
drop policy if exists learned_correction_runs_team_read on public.learned_correction_runs;
create policy learned_correction_runs_team_read on public.learned_correction_runs for select to authenticated
  using (team_id in (select fn_user_teams()));

create table if not exists public.learned_correction_rules (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  rule_text text not null check (length(btrim(rule_text)) > 0),
  scope_touch_type text,          -- null = every touch type
  scope_channel text,             -- null = every channel
  source_feedback_ids uuid[] not null default '{}',
  source_touch_ids uuid[] not null default '{}',
  status text not null default 'active' check (status in ('active','deleted')),
  created_by_run uuid references public.learned_correction_runs(id) on delete set null,
  edited_by uuid,
  edited_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists learned_correction_rules_team_status_idx on public.learned_correction_rules (team_id, status);
alter table public.learned_correction_rules enable row level security;
drop policy if exists learned_correction_rules_team_read on public.learned_correction_rules;
create policy learned_correction_rules_team_read on public.learned_correction_rules for select to authenticated
  using (team_id in (select fn_user_teams()));
drop policy if exists learned_correction_rules_team_edit on public.learned_correction_rules;
create policy learned_correction_rules_team_edit on public.learned_correction_rules for update to authenticated
  using (team_id in (select fn_user_teams())) with check (team_id in (select fn_user_teams()));
create or replace function public.fn_learned_rule_stamp() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if tg_op = 'UPDATE' and auth.uid() is not null then new.edited_by := auth.uid(); new.edited_at := now(); end if;
  return new;
end $$;
drop trigger if exists trg_learned_rule_stamp on public.learned_correction_rules;
create trigger trg_learned_rule_stamp before update on public.learned_correction_rules
  for each row execute function public.fn_learned_rule_stamp();

-- voice_assets allowed layers 1..4; layer 5 is this asset.
alter table public.voice_assets drop constraint if exists voice_assets_layer_check;
alter table public.voice_assets add constraint voice_assets_layer_check check (layer >= 1 and layer <= 5);

insert into public.voice_assets (id, team_id, layer, applies_to, body, version, updated_at, updated_by)
select 'learned_corrections', t.id, 5, '{}',
       '(No learned corrections yet. Layer 5 is rendered from learned_correction_rules and is NOT loaded by the drafter until Brad approves.)',
       'lc-v0 (empty; not wired)', now(), 'Claude Code F22B.6'
  from public.teams t
 where not exists (select 1 from public.voice_assets where id = 'learned_corrections')
 limit 1;

-- (b) weekly distillation, Monday 05:30 UTC, created INACTIVE (F22B.6(g)).
select cron.unschedule('distill-learned-corrections') where exists (select 1 from cron.job where jobname = 'distill-learned-corrections');
select cron.schedule('distill-learned-corrections', '30 5 * * 1', $job$
  select net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/distill-learned-corrections',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'internal_app_secret')),
    body := jsonb_build_object('triggered_by', 'cron'),
    timeout_milliseconds := 120000);
$job$);
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'distill-learned-corrections'), active := false);
