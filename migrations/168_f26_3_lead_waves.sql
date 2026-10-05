-- 168 F26 Task 3: lead waves, derived from the existing seniority and function enums. No new taxonomy.
--   Wave 1: seniority C-suite or Director, or function Executive / Alliances / BD at Senior.
--   Wave 2: seniority Senior or Manager in Sales, Marketing, Product, Operations or Strategy.
--   Wave 3: everything else (including seniority unknown).
-- lead_wave_source: 'derived' (recomputed whenever seniority or function changes) or 'manual' (a person set it in
-- Lovable; derivation never overwrites it). Writing lead_wave without saying 'derived' makes it manual; setting it to
-- NULL, or setting lead_wave_source = 'derived', hands it back to the derivation.

create or replace function public.fn_derive_lead_wave(p_seniority text, p_function text)
returns smallint language sql immutable parallel safe set search_path = pg_catalog as $$
  select (case
    when p_seniority in ('C-suite','Director') then 1
    when p_seniority = 'Senior' and p_function in ('Executive','Alliances / BD') then 1
    when p_seniority in ('Senior','Manager') and p_function in ('Sales','Marketing','Product','Operations','Strategy') then 2
    else 3 end)::smallint
$$;

alter table public.contacts add column if not exists lead_wave smallint;
alter table public.contacts add column if not exists lead_wave_source text;
alter table public.contacts drop constraint if exists contacts_lead_wave_check;
alter table public.contacts add constraint contacts_lead_wave_check check (lead_wave in (1, 2, 3));
alter table public.contacts drop constraint if exists contacts_lead_wave_source_check;
alter table public.contacts add constraint contacts_lead_wave_source_check check (lead_wave_source in ('derived','manual'));
comment on column public.contacts.lead_wave is
  'F26.3: 1 = C-suite/Director or Senior Executive/Alliances-BD; 2 = Senior/Manager in Sales, Marketing, Product, Operations, Strategy; 3 = everything else. Orders the CR queue after manual_rank.';
comment on column public.contacts.lead_wave_source is
  'F26.3: derived (follows seniority/function) or manual (set by a person; never overwritten by derivation).';

create or replace function public.fn_contacts_lead_wave()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'UPDATE' and new.lead_wave is distinct from old.lead_wave and new.lead_wave is not null
     and new.lead_wave_source is not distinct from old.lead_wave_source then
    new.lead_wave_source := 'manual';                       -- a person changed the wave
  elsif tg_op = 'INSERT' and new.lead_wave is not null and new.lead_wave_source is null then
    new.lead_wave_source := 'manual';
  end if;
  if new.lead_wave is null then
    new.lead_wave_source := 'derived';                      -- cleared: back to the derivation
  end if;
  if coalesce(new.lead_wave_source, 'derived') = 'derived' then
    new.lead_wave := public.fn_derive_lead_wave(new.seniority::text, new.function::text);
    new.lead_wave_source := 'derived';
  end if;
  return new;
end $$;
revoke execute on function public.fn_contacts_lead_wave() from public, anon, authenticated;

drop trigger if exists trg_contacts_lead_wave on public.contacts;
create trigger trg_contacts_lead_wave before insert or update of seniority, function, lead_wave, lead_wave_source
  on public.contacts for each row execute function public.fn_contacts_lead_wave();

update public.contacts set lead_wave_source = 'derived', lead_wave = public.fn_derive_lead_wave(seniority::text, function::text)
 where lead_wave is null or lead_wave_source is null;
