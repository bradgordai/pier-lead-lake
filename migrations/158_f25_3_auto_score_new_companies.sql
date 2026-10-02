-- 158 F25 Task 3: new companies get scored without anyone remembering, behind a switch that defaults OFF.
-- After the F25.2 full run every existing company has a company_scores row, so fn_company_score_mark_dirty (fixed in 157)
-- marks them dirty and the hourly company-rescore-dirty job re-scores them. A company created LATER has no row, and a stub
-- row is impossible without inventing zeros (company_scores has NOT NULL score/assessed/points/source/model_version), so
-- none is created here. Instead:
--   team_settings.auto_score_new_companies boolean not null default false (Brad switches it on in Settings);
--   cron job 'company-score-new' hourly at :47 calls score-company {mode:'unscored', approved_full_run:true, limit:10}
--   ONLY when the switch is on AND an unscored, unarchived company exists. When either is false the job's WHERE makes the
--   statement a no-op: no HTTP call, no AI call, no cost.
-- COST IF ON: 10 x 24 x GBP 0.0064 = GBP 1.54 a day worst case; about GBP 0 once the backlog is clear.
-- Bearer read from Vault internal_app_secret exactly as the existing jobs (137 company-rescore-dirty). Archived companies
-- are excluded from the guard; the EF itself orders by research_priority_rank.

alter table public.team_settings add column if not exists auto_score_new_companies boolean not null default false;
comment on column public.team_settings.auto_score_new_companies is
  'F25.3: when true, cron company-score-new scores up to 10 unscored companies an hour (worst case GBP 1.54/day). Default off.';

select cron.unschedule('company-score-new') where exists (select 1 from cron.job where jobname = 'company-score-new');
select cron.schedule('company-score-new', '47 * * * *', $job$
  select net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/score-company',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'internal_app_secret')),
    body := jsonb_build_object('mode', 'unscored', 'approved_full_run', true, 'limit', 10, 'run_label', 'auto_score_new'),
    timeout_milliseconds := 120000)
  where exists (select 1 from public.team_settings where auto_score_new_companies)
    and exists (select 1 from public.v_company_score where not is_scored and archived_at is null);
$job$);

-- team_settings has no UPDATE policy for authenticated users (writes go through SECURITY DEFINER RPCs, e.g.
-- fn_set_inmail_credits). The Settings toggle uses this one, same membership check.
create or replace function public.fn_set_auto_score_new_companies(p_team uuid, p_on boolean) returns boolean
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
begin
  if auth.uid() is null or p_team not in (select fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if p_on is null then raise exception 'p_on must be true or false'; end if;
  update public.team_settings set auto_score_new_companies = p_on, updated_at = now() where team_id = p_team;
  if not found then raise exception 'no settings row for team %', p_team; end if;
  return p_on;
end $$;
revoke all on function public.fn_set_auto_score_new_companies(uuid, boolean) from public, anon;
grant execute on function public.fn_set_auto_score_new_companies(uuid, boolean) to authenticated;
