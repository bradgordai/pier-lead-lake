-- 153 F23 Task 8: stop NEW duplicate companies (i170).
-- ROOT CAUSE (read in upsert-contact-from-sales-nav): its company matcher loads only companies with archived_at IS NULL,
-- so a company that exists but is ARCHIVED is invisible to it and the auto-create branch (added_via 'sales_nav_auto')
-- makes a second one. 11 of the 12 current collisions are an archived original plus a newer copy.
--
-- GUARD: a BEFORE INSERT trigger on companies refuses a row whose normalised name (lower, non-alphanumerics stripped)
-- or root_domain matches an existing company of the same team, archived or not. It raises SQLSTATE 23505 with a
-- message naming the existing company. The message deliberately does not contain the text "company_id", so the
-- ingest's company_id-collision retry does not loop; the ingest treats the failure as "auto-create failed" and inserts
-- the contact unmatched, which sends it to Reconciliation for a human to attach. The Lovable "new company" form gets
-- the same readable error.
-- A trigger cannot hand the existing row back to the caller: attaching the contact to the existing company needs a
-- change in upsert-contact-from-sales-nav (and a ruling on attaching to an ARCHIVED company). Not done here.
-- The existing 12 duplicates are NOT merged and NOT touched (the guard only fires on INSERT).

create or replace function public.fn_company_name_key(p_name text) returns text
language sql immutable set search_path to 'public', 'pg_temp' as $$
  select nullif(regexp_replace(lower(coalesce(p_name, '')), '[^a-z0-9]', '', 'g'), '');
$$;

create index if not exists companies_team_name_key_idx on public.companies (team_id, public.fn_company_name_key(company_name));
create index if not exists companies_team_root_domain_idx on public.companies (team_id, lower(root_domain)) where root_domain is not null;

create or replace function public.fn_company_duplicate_guard() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare hit record; k text := public.fn_company_name_key(new.company_name);
begin
  select c.id, c.company_id as ref, c.company_name as name, c.archived_at,
         case when k is not null and public.fn_company_name_key(c.company_name) = k then 'name' else 'domain' end as why
    into hit
    from public.companies c
   where c.team_id = new.team_id
     and ( (k is not null and public.fn_company_name_key(c.company_name) = k)
        or (nullif(btrim(new.root_domain), '') is not null and lower(c.root_domain) = lower(btrim(new.root_domain))) )
   order by c.archived_at nulls first, c.created_at
   limit 1;
  if hit.id is not null then
    raise exception using errcode = '23505',
      message = format('duplicate_company: "%s" matches existing %s %s%s by %s. Use the existing company instead of creating a second.',
                       new.company_name, hit.ref, hit.name, case when hit.archived_at is not null then ' (archived)' else '' end, hit.why),
      detail = format('existing_company_uuid=%s', hit.id);
  end if;
  return new;
end $$;

drop trigger if exists trg_company_duplicate_guard on public.companies;
create trigger trg_company_duplicate_guard before insert on public.companies
  for each row execute function public.fn_company_duplicate_guard();
