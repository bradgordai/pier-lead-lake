-- 077: F12 T5 (2026-09-09). Estimates can never be written into a stated-figure column.
-- Design: sizing lives in an APPEND-ONLY history table where every row names its rung and says
-- whether it is an estimate; the only stated-figure column on companies (annual_devices_sold)
-- now refuses a write that does not carry partner evidence. Estimates therefore have exactly one
-- home (company_size, is_estimate = true) and cannot collide with stated figures anywhere.
create table if not exists public.company_size (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  company_id uuid not null references public.companies(id) on delete cascade,
  recorded_at timestamptz not null default now(),
  devices_per_month numeric,
  devices_per_year numeric,
  phones_share numeric check (phones_share is null or (phones_share >= 0 and phones_share <= 1)),
  laptops_share numeric check (laptops_share is null or (laptops_share >= 0 and laptops_share <= 1)),
  accessories_note text,
  online_share numeric check (online_share is null or (online_share >= 0 and online_share <= 1)),
  in_store_share numeric check (in_store_share is null or (in_store_share >= 0 and in_store_share <= 1)),
  own_channel_share numeric check (own_channel_share is null or (own_channel_share >= 0 and own_channel_share <= 1)),
  rung text not null check (rung in ('E0','E1','E2','E3','E4','E5')),
  confidence text check (confidence in ('high','medium','low-medium','low','none')),
  basis text not null,
  tier_mark text check (tier_mark is null or tier_mark in ('T1','T2','T3','below_floor','unsized')),
  is_estimate boolean not null,
  stated_by text,
  stated_on date,
  evidence_verbatim text,
  ceiling_caveat text,
  superseded_by uuid references public.company_size(id),
  created_by text,
  created_at timestamptz not null default now(),
  -- E1 is the only stated rung and it needs a quote and a source; every other rung IS an estimate.
  constraint company_size_stated_or_estimate check (
    (is_estimate = false and rung = 'E1' and evidence_verbatim is not null and btrim(evidence_verbatim) <> '' and stated_by is not null)
    or (is_estimate = true and rung <> 'E1')
  ),
  constraint company_size_unsized check (rung <> 'E0' or (devices_per_month is null and devices_per_year is null))
);
create index if not exists company_size_company_idx on public.company_size (company_id, recorded_at desc);
alter table public.company_size enable row level security;
drop policy if exists company_size_team on public.company_size;
create policy company_size_team on public.company_size for all to authenticated using (team_id in (select fn_user_teams())) with check (team_id in (select fn_user_teams()));
-- Append-only: the only permitted update is marking a row superseded; deletes are refused.
create or replace function public.fn_company_size_append_only() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if tg_op = 'DELETE' then raise exception 'company_size is append-only: supersede the row instead of deleting it' using errcode='check_violation'; end if;
  if row(new.*) is distinct from row(old.*) and (
       new.superseded_by is null or old.superseded_by is not null
       or row_to_json(new)::jsonb - 'superseded_by' <> row_to_json(old)::jsonb - 'superseded_by') then
    raise exception 'company_size is append-only: only superseded_by may be set, once' using errcode='check_violation';
  end if;
  return new;
end $$;
drop trigger if exists trg_company_size_append_only on public.company_size;
create trigger trg_company_size_append_only before update or delete on public.company_size for each row execute function public.fn_company_size_append_only();
create or replace view public.v_company_size_current as
  select distinct on (company_id) * from public.company_size where superseded_by is null order by company_id, recorded_at desc;
-- The stated-figure column on companies: a write must carry the partner's own words and who said it.
alter table public.companies add column if not exists annual_devices_sold_evidence text;
alter table public.companies add column if not exists annual_devices_sold_stated_by text;
comment on column public.companies.annual_devices_sold is 'STATED figures only (rung E1). Writing here without annual_devices_sold_evidence + annual_devices_sold_stated_by is refused. Estimates go to company_size with is_estimate = true.';
create or replace function public.fn_companies_stated_figure_guard() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if new.annual_devices_sold is distinct from old.annual_devices_sold and new.annual_devices_sold is not null and btrim(new.annual_devices_sold) <> '' then
    if new.annual_devices_sold_evidence is null or btrim(new.annual_devices_sold_evidence) = '' or new.annual_devices_sold_stated_by is null or btrim(new.annual_devices_sold_stated_by) = '' then
      raise exception 'annual_devices_sold is a stated-figure column: it needs the partner''s verbatim evidence and who stated it. An estimate belongs in company_size with is_estimate = true.' using errcode='check_violation';
    end if;
    new.field_provenance := coalesce(new.field_provenance,'{}'::jsonb) || jsonb_build_object('annual_devices_sold', jsonb_build_object('source','stated','basis', new.annual_devices_sold_stated_by, 'at', now()));
  end if;
  return new;
end $$;
drop trigger if exists trg_companies_stated_figure_guard on public.companies;
create trigger trg_companies_stated_figure_guard before update on public.companies for each row execute function public.fn_companies_stated_figure_guard();
