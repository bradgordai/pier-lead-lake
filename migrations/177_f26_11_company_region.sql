-- 177 F26.1 Task 11: companies.region, DERIVED from country. DACH is a region, never a country value.
-- A company is in one country; the region follows from it (trigger), so selecting a DACH country implies the region
-- and filtering the DACH region returns Germany, Austria and Switzerland. Never typed separately.
--
-- Mapping notes (measured 5 Oct):
--   - country holds some sub-national labels: 'Berlin Metropolitan Area', 'Cologne Bonn Region', 'Greater Hamburg Area',
--     'Greater Munich Metropolitan Area' (DACH), 'Greater Paris Metropolitan Region' and 'Greater Madrid Metropolitan Area'
--     (Southern Europe), 'Prague Metropolitan Area' (CEE). They map by the country they are in.
--   - France has no region of its own in the brief's list; it is placed in Southern Europe (flagged in the report).
--   - Empty country, 'Other' and every 'TBC …' value are Unknown, and stay visible as Unknown.

create or replace function public.fn_region_for_country(p_country text)
returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select case
    when l is null or l = '' or l = 'other' or l like 'tbc%' or l like '%(tbc%' then 'Unknown'
    when l in ('germany','deutschland','austria','österreich','switzerland','schweiz','liechtenstein',
               'berlin metropolitan area','cologne bonn region','greater hamburg area','greater munich metropolitan area') then 'DACH'
    when l in ('uk','united kingdom','great britain','england','scotland','wales','northern ireland','ireland') then 'UK and Ireland'
    when l in ('sweden','denmark','norway','finland','iceland') then 'Nordics'
    when l in ('netherlands','the netherlands','belgium','luxembourg') then 'Benelux'
    when l in ('france','spain','italy','portugal','greece','malta','cyprus','monaco','andorra',
               'greater paris metropolitan region','greater madrid metropolitan area') then 'Southern Europe'
    when l in ('poland','hungary','estonia','latvia','lithuania','slovakia','czech republic','czechia','romania','bulgaria',
               'serbia','croatia','slovenia','bosnia and herzegovina','montenegro','north macedonia','albania','ukraine','moldova',
               'prague metropolitan area') then 'CEE'
    else 'Rest of world' end
  from (select lower(btrim(p_country)) l) x
$$;

alter table public.companies add column if not exists region text;
alter table public.companies drop constraint if exists companies_region_check;
alter table public.companies add constraint companies_region_check check (region in
  ('DACH','UK and Ireland','Nordics','Benelux','Southern Europe','CEE','Rest of world','Unknown'));
comment on column public.companies.region is
  'F26.1 T11: derived from country by fn_region_for_country (trigger). DACH = Germany, Austria, Switzerland. Never typed; never a country value.';

create or replace function public.fn_companies_region()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.region := public.fn_region_for_country(new.country);
  return new;
end $$;
revoke execute on function public.fn_companies_region() from public, anon, authenticated;

drop trigger if exists trg_companies_region on public.companies;
create trigger trg_companies_region before insert or update of country, region on public.companies
  for each row execute function public.fn_companies_region();

update public.companies set region = public.fn_region_for_country(country)
 where region is distinct from public.fn_region_for_country(country);

alter table public.companies alter column region set not null;
create index if not exists companies_region_idx on public.companies (region);
