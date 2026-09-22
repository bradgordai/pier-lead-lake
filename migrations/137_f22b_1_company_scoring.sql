-- 137 F22B.1: company scoring. TWO FIELDS, TWO JOBS.
--   companies.priority (P0-P3, OoS, Competitor) is FOR THE RESEARCH AGENT and is NOT touched here: not removed,
--   not replaced, not written, and none of the six functions that read it is edited.
--   company score is FOR THE USER: how valuable approaching the company is. It orders OUTREACH.
--
-- Model: 260904_PIER_lead_scoring_model_v01_OM_C2.md (v03) with ONE OVERRIDE, Brad's ruling of 23 Sep 2026:
--   UNASSESSED COMPONENTS SCORE ZERO. This OVERRIDES section 4.3 of the model ("removed from the denominator").
--   score = raw points over a full 100; assessed_points = how many of the 100 could be assessed;
--   research_upside = 100 - assessed_points. DO NOT "fix" this back to the denominator rule.
--   The one exception, also Brad's (F22B.1(d)) and the model's (4.2): an UNKNOWN incumbent takes the neutral
--   14/30. It is counted in score but NOT in assessed_points, and is displayed "incumbent: not checked (neutral 14/30)".
-- No score row = "not scored". A score of 0 is a finding. They are never the same row.

-- (e) Territory: ONE rank table, no country logic in code. Aliases are rows (UK and United Kingdom both exist in
-- companies.country today). A country absent from this table scores rank 0 (3 points) and SAYS SO.
create table if not exists public.score_territory_ranks (
  country text primary key,
  rank int not null check (rank between -1 and 3),
  points int not null check (points between 0 and 15),
  note text
);
insert into public.score_territory_ranks (country, rank, points, note) values
  ('Germany',1,15,'current focus'),('Austria',1,15,'current focus'),('Switzerland',1,15,'current focus'),
  ('France',2,11,'next in sequence'),('Spain',2,11,'next in sequence'),('Italy',2,11,'next in sequence'),
  ('Netherlands',3,7,'opportunistic'),('Belgium',3,7,'opportunistic'),('Luxembourg',3,7,'opportunistic'),('Ireland',3,7,'opportunistic'),
  ('Poland',0,3,'not sequenced yet'),('Sweden',0,3,'not sequenced yet (Nordics)'),('Denmark',0,3,'not sequenced yet (Nordics)'),
  ('Norway',0,3,'not sequenced yet (Nordics)'),('Finland',0,3,'not sequenced yet (Nordics)'),('Iceland',0,3,'not sequenced yet (Nordics)'),
  ('Hungary',0,3,'not sequenced yet'),('Czech Republic',0,3,'not sequenced yet'),('Czechia',0,3,'not sequenced yet'),
  ('Portugal',0,3,'not sequenced yet'),('Estonia',0,3,'not sequenced yet'),
  ('United Kingdom',-1,0,'someone else''s territory (Jack); the gate blocks it anyway'),('UK',-1,0,'someone else''s territory (Jack); alias of United Kingdom')
on conflict (country) do nothing;
alter table public.score_territory_ranks enable row level security;
drop policy if exists score_territory_ranks_read on public.score_territory_ranks;
create policy score_territory_ranks_read on public.score_territory_ranks for select to authenticated using (true);

-- The current score of each company. One row per company; no row = not scored.
create table if not exists public.company_scores (
  company_id uuid primary key references public.companies(id) on delete cascade,
  team_id uuid not null,
  score int not null check (score between 0 and 100),
  assessed_points int not null check (assessed_points between 0 and 100),
  research_upside int generated always as (100 - assessed_points) stored,
  -- (b) GWP potential, 40
  gwp_points int not null check (gwp_points between 0 and 40),
  gwp_assessed boolean not null,
  gwp_value_gbp numeric, gwp_band text, size_rung text, devices_per_month numeric, gwp_basis text,
  -- (b)(c)(d) incumbent switchability, 30. switchability = GAP - LOCK-IN, -4..+4; points scale on that.
  switch_points int not null check (switch_points between 0 and 30),
  switch_assessed boolean not null,
  switch_gap int check (switch_gap between 0 and 4),
  switch_lockin int check (switch_lockin between 0 and 5),
  switchability int check (switchability between -4 and 4),
  switch_basis text,
  -- (b)(e) territory, 15
  territory_points int not null check (territory_points between 0 and 15),
  territory_assessed boolean not null,
  territory_rank int, territory_in_table boolean, territory_basis text,
  -- (b)(c) wedge quality, 15; minus 4 when the walk is over 180 days old, floored at 2
  wedge_points int not null check (wedge_points between 0 and 15),
  wedge_assessed boolean not null,
  wedge_tests jsonb, wedge_stale boolean, wedge_basis text,
  source text not null check (source in ('oliver_board_v01','scoring_agent')),
  model_version text not null,
  scored_at timestamptz not null default now(),
  research_refreshed_at_scoring date,
  needs_rescore boolean not null default false,
  rescore_reason text,
  detail jsonb,
  check (score = gwp_points + switch_points + territory_points + wedge_points)
);
create index if not exists company_scores_team_score_idx on public.company_scores (team_id, score desc);
create index if not exists company_scores_dirty_idx on public.company_scores (needs_rescore) where needs_rescore;
alter table public.company_scores enable row level security;
drop policy if exists company_scores_team_read on public.company_scores;
create policy company_scores_team_read on public.company_scores for select to authenticated
  using (team_id in (select fn_user_teams()));
-- Writes only through the score-company Edge Function (service role) and migrations.

-- Every call of the scoring sub-agent, dry run or not, with its full working. Audit trail, never read for ranking.
create table if not exists public.company_score_runs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  run_label text,
  dry_run boolean not null,
  agent_output jsonb,
  working jsonb,
  score int, assessed_points int,
  estimated_cost_gbp numeric,
  error text,
  created_at timestamptz not null default now()
);
create index if not exists company_score_runs_company_idx on public.company_score_runs (company_id, created_at desc);
alter table public.company_score_runs enable row level security;
drop policy if exists company_score_runs_team_read on public.company_score_runs;
create policy company_score_runs_team_read on public.company_score_runs for select to authenticated
  using (team_id in (select fn_user_teams()));

-- (h) RECOMPUTE RULE. A change to any scoring input on companies marks the score dirty (trigger). Contacts do not
-- feed the score; they feed REACH, which is computed ON READ in v_company_reach and is therefore never stale.
-- A dirty agent score is re-scored by the hourly job below (max 10 per run). A dirty OLIVER import is NOT
-- re-scored automatically (that would overwrite his judgement); it shows STALE until someone rescores it.
create or replace function public.fn_company_score_mark_dirty() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare changed text[] := '{}';
begin
  if new.research_stage is distinct from old.research_stage then changed := changed || 'research_stage'; end if;
  if new.annual_devices_sold is distinct from old.annual_devices_sold
     or new.annual_devices_sold_evidence is distinct from old.annual_devices_sold_evidence
     or new.employees is distinct from old.employees or new.monthly_visits is distinct from old.monthly_visits
     or new.estimated_revenue_gbp is distinct from old.estimated_revenue_gbp then changed := changed || 'company_size'; end if;
  if new.insurance_offered is distinct from old.insurance_offered or new.insurance_provider is distinct from old.insurance_provider
     or new.insurance_structure_type is distinct from old.insurance_structure_type
     or new.insurance_monthly_price is distinct from old.insurance_monthly_price
     or new.insurance_annual_price is distinct from old.insurance_annual_price
     or new.coverage_summary is distinct from old.coverage_summary or new.policy_url is distinct from old.policy_url
     or new.distribution_model is distinct from old.distribution_model or new.customer_journey is distinct from old.customer_journey
     then changed := changed || 'insurance'; end if;
  if new.usp_notes is distinct from old.usp_notes then changed := changed || 'wedge'; end if;
  if new.country is distinct from old.country then changed := changed || 'country'; end if;
  if new.last_refreshed is distinct from old.last_refreshed then changed := changed || 'last_refreshed'; end if;
  if array_length(changed, 1) > 0 then
    update public.company_scores set needs_rescore = true,
      rescore_reason = left(coalesce(rescore_reason || '; ', '') || array_to_string(changed, ',') || ' changed ' || to_char(now(), 'YYYY-MM-DD'), 500)
     where company_id = new.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_company_score_mark_dirty on public.companies;
create trigger trg_company_score_mark_dirty after update on public.companies
  for each row execute function public.fn_company_score_mark_dirty();

-- (f) REACH. Separate from the score, never added to it. Computed from contact STATE, not contacts_count.
-- A contact is COUNTED when archived_at is null. It is LIVE when counted AND do_not_contact is not true AND
-- promise_of_quiet is not true AND outreach_status is not one of Do not contact, Opted out, Left company,
-- Not relevant, Parked.
--   warm 4     at least one live contact at connection_status Accepted or Already connected (a free DM today)
--   open 3     else: a live contact not in cooldown (cooldown_until null or past; outreach_status not Cooldown) and
--              not CR-blocked (cr_blocked_until null or past) at connection_status Not connected, Request sent or null
--              (a CR is free, or one is already out)
--   paid 2     else: live contacts exist but every one is Withdrawn / Ignored / in cooldown / CR-blocked (InMail only)
--   sourcing 1 no counted contacts at all
--   locked 0   counted contacts exist but none is live (every route closed)
create or replace view public.v_company_reach with (security_invoker = true) as
with k as (
  select c.company_id,
         count(*) as counted,
         count(*) filter (where live) as live_n,
         count(*) filter (where live and c.connection_status in ('Accepted','Already connected')) as warm_n,
         count(*) filter (where live and coalesce(c.connection_status::text,'Not connected') in ('Not connected','Request sent')
                           and (c.cooldown_until is null or c.cooldown_until <= current_date)
                           and coalesce(c.outreach_status::text,'') <> 'Cooldown'
                           and (c.cr_blocked_until is null or c.cr_blocked_until <= current_date)) as open_n
  from (select c.*, (coalesce(c.do_not_contact,false) = false and coalesce(c.promise_of_quiet,false) = false
                     and coalesce(c.outreach_status::text,'') not in ('Do not contact','Opted out','Left company','Not relevant','Parked')) as live
          from public.contacts c where c.archived_at is null and c.company_id is not null) c
  group by c.company_id
)
select co.id as company_id, co.team_id,
       coalesce(k.counted,0) as contacts_counted, coalesce(k.live_n,0) as contacts_live,
       coalesce(k.warm_n,0) as contacts_warm, coalesce(k.open_n,0) as contacts_open,
       case when coalesce(k.counted,0) = 0 then 1 when k.live_n = 0 then 0 when k.warm_n > 0 then 4 when k.open_n > 0 then 3 else 2 end as reach_rung,
       case when coalesce(k.counted,0) = 0 then 'sourcing' when k.live_n = 0 then 'locked' when k.warm_n > 0 then 'warm' when k.open_n > 0 then 'open' else 'paid' end as reach
  from public.companies co left join k on k.company_id = co.id;

-- The score as the screens read it: score, working, STALE marker, reach, and the two orders.
--   research_order: priority first (P0..P3, then unprioritised; OoS and Competitor are not in the research queue),
--                   then research_upside (unscored counts as 100 upside). This is the RESEARCH view's order.
--   outreach order: score desc, then reach_rung desc. Unscored sorts last and renders "not scored".
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
       case co.priority::text when 'P0' then 0 when 'P1' then 1 when 'P2' then 2 when 'P3' then 3 when 'OoS' then null when 'Competitor' then null else 4 end as research_priority_rank,
       coalesce(s.research_upside, 100) as research_upside_for_queue
  from public.companies co
  left join public.company_scores s on s.company_id = co.id
  left join public.v_company_reach r on r.company_id = co.id;

-- (g) CONTACT SCORE: INHERITED from the company. The model's lead score (decision power 50, channel 30,
-- personalisation 20) is NOT built: Oliver has supplied no working for it.
create or replace view public.v_contact_score with (security_invoker = true) as
select ct.id as contact_id, ct.team_id, ct.company_id, s.score as contact_score, 'inherited_from_company'::text as contact_score_basis,
       s.scored_at, (s.company_id is not null) as is_scored
  from public.contacts ct left join public.company_scores s on s.company_id = ct.company_id;

grant select on public.v_company_reach, public.v_company_score, public.v_contact_score to authenticated;

-- (h) the hourly re-score of DIRTY AGENT scores (max 10 per run). Makes no HTTP call when nothing is dirty.
-- Never scores an unscored company: the full first run is a separate, human-approved step.
select cron.unschedule('company-rescore-dirty') where exists (select 1 from cron.job where jobname = 'company-rescore-dirty');
select cron.schedule('company-rescore-dirty', '17 * * * *', $job$
  select net.http_post(
    url := 'https://qzfrcfzeiagziqjnfarw.supabase.co/functions/v1/score-company',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
      'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'internal_app_secret')),
    body := jsonb_build_object('mode', 'dirty', 'limit', 10),
    timeout_milliseconds := 120000)
  where exists (select 1 from public.company_scores where needs_rescore and source = 'scoring_agent');
$job$);

-- (j) OLIVER'S DACH SCORES ARE IMPORTED, NOT RECOMPUTED (260908_PIER_lovable_board_export_v01_OM_C2.csv, 73 rows).
-- Only the 3 rows whose domain EXACTLY matches a company held today land now (getgoods.com, toredo.de,
-- ackermann.ch). The other 70 arrive with the DACH import (F22B.3) through its matching rules.
-- Component points are Oliver's, verbatim. score is their RAW SUM (Brad's ruling). For 11 of his 73 rows, all E0,
-- he normalised over 60 assessed points (e.g. 50/60 shown as 83); those land as the raw 50 with his 83 kept in
-- detail.oliver_score_0_100. None of those 11 is among today's 3.
do $$ declare r record; cid uuid; tid uuid; n int := 0; begin
  for r in select * from (values
    ('getgoods.com', 20, 30, 15, 11, 'E4', 76, 100, 'NONE - retailer was its own guarantor', 'one-off (currently not sellable)', 'SELF-FUNDED - already sells protection with no insurer behind it', 'sourced'),
    ('toredo.de',    10, 30, 15, 11, 'E1 total / E4 own-channel', 66, 100, 'NONE - self-funded', 'n/a (bundled free)', 'SELF-FUNDED - already sells protection with no insurer behind it', ''),
    ('ackermann.ch', 20, 30, 15,  9, 'E3', 74, 100, 'NONE - self-funded repair promise', 'one-off Aufpreis', 'SELF-FUNDED - already sells protection with no insurer behind it', 'sourced')
  ) v(dom, g, i, t, w, rung, oliver_score, oliver_assessed, insurer, billing, wedge, decision) loop
    select id, team_id into cid, tid from public.companies where lower(root_domain) = r.dom;
    if cid is null then raise exception 'board import: % not found by exact domain', r.dom; end if;
    insert into public.company_scores (company_id, team_id, score, assessed_points,
      gwp_points, gwp_assessed, size_rung, gwp_basis,
      switch_points, switch_assessed, switch_basis,
      territory_points, territory_assessed, territory_rank, territory_in_table, territory_basis,
      wedge_points, wedge_assessed, wedge_basis,
      source, model_version, scored_at, research_refreshed_at_scoring, detail)
    values (cid, tid, r.g + r.i + r.t + r.w, 100,
      r.g, true, r.rung, 'Oliver board export 8 Sep 2026, rung ' || r.rung,
      r.i, true, 'Oliver board export: insurer ' || r.insurer || '; billing ' || r.billing,
      r.t, true, 1, true, 'Oliver board export (rank 1, current focus)',
      r.w, true, 'Oliver board export: ' || r.wedge,
      'oliver_board_v01', 'lead_scoring_model_v03 (Oliver, imported)', '2026-09-08T00:00:00Z',
      (select last_refreshed from public.companies where id = cid),
      jsonb_build_object('oliver_score_0_100', r.oliver_score, 'oliver_score_assessed', r.oliver_assessed,
                         'oliver_decision', nullif(r.decision, ''), 'import_match', 'exact_domain ' || r.dom))
    on conflict (company_id) do nothing;
    n := n + 1;
  end loop;
  if n <> 3 then raise exception 'expected 3 board imports, got %', n; end if;
end $$;
