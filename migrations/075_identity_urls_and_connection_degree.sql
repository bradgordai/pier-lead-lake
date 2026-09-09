-- 075: F12 T3 (2026-09-09). LinkedIn URL and Sales Nav URL are two trusted fields, never conflated;
-- every URL carries where it came from; an accepted contact always has a degree.
-- (1) 20 rows held a /sales/lead/ URL in linkedin_url (workbook-era import). Move it across.
do $$
declare v_run text := 'f12-identity-urls-2026-09-09'; r record;
begin
  for r in select id, contact_id, linkedin_url, linkedin_sales_nav_url, linkedin_slug from contacts where linkedin_url ilike '%/sales/%' loop
    insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 't3_unconflate', 'contacts', r.contact_id, 'update', r.id, jsonb_build_object('before', jsonb_build_object('linkedin_url', r.linkedin_url, 'linkedin_sales_nav_url', r.linkedin_sales_nav_url, 'linkedin_slug', r.linkedin_slug)));
  end loop;
  update contacts set
    linkedin_sales_nav_url = coalesce(nullif(linkedin_sales_nav_url,''), linkedin_url),
    linkedin_url = case when linkedin_slug is not null and linkedin_slug <> '' then 'https://www.linkedin.com/in/' || linkedin_slug else null end,
    updated_at = now()
  where linkedin_url ilike '%/sales/%';
end $$;
-- (2) Trust marker per URL: where each value came from.
alter table public.contacts add column if not exists url_provenance jsonb not null default '{}'::jsonb;
comment on column public.contacts.url_provenance is 'F12 T3: {"linkedin_url": {"source": workbook|watcher|manual|inferred, "at": iso, "basis": text}, "linkedin_sales_nav_url": {...}}. The value in the column is only as trusted as its source.';
update contacts c set url_provenance = jsonb_strip_nulls(jsonb_build_object(
  'linkedin_url', case when linkedin_url is not null and linkedin_url <> '' then jsonb_build_object(
      'source', case when exists (select 1 from migration_audit a where a.target_id=c.id and a.run_id='f12-identity-urls-2026-09-09') then 'inferred'
                     when c.legacy_source is not null or c.migrated_at is not null then 'workbook' else 'watcher' end,
      'at', coalesce(c.migrated_at, c.created_at),
      'basis', case when exists (select 1 from migration_audit a where a.target_id=c.id and a.run_id='f12-identity-urls-2026-09-09') then 'rebuilt from linkedin_slug 2026-09-09' when c.legacy_source is not null then c.legacy_source else 'ingest' end) end,
  'linkedin_sales_nav_url', case when linkedin_sales_nav_url is not null and linkedin_sales_nav_url <> '' then jsonb_build_object(
      'source', case when c.legacy_source is not null or c.migrated_at is not null then 'workbook' else 'watcher' end,
      'at', coalesce(c.migrated_at, c.created_at),
      'basis', coalesce(c.legacy_source, 'ingest')) end))
where url_provenance = '{}'::jsonb;
-- (3) The two fields can never hold each other's kind of URL again.
alter table public.contacts drop constraint if exists contacts_linkedin_url_is_public_profile;
alter table public.contacts add constraint contacts_linkedin_url_is_public_profile check (linkedin_url is null or linkedin_url !~* 'linkedin\.com/sales/');
alter table public.contacts drop constraint if exists contacts_sales_nav_url_is_sales_nav;
alter table public.contacts add constraint contacts_sales_nav_url_is_sales_nav check (linkedin_sales_nav_url is null or linkedin_sales_nav_url = '' or linkedin_sales_nav_url ~* 'linkedin\.com/sales/');
-- (4) Degree: backfill what is derivable (accepted = 1st degree), then never let an accepted or
--     requested contact sit with a blank degree again.
do $$
declare v_run text := 'f12-identity-urls-2026-09-09'; r record;
begin
  for r in select id, contact_id, connection_status from contacts where connection_status::text in ('Accepted','Already connected') and connection_level is null loop
    insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 't3_degree_backfill', 'contacts', r.contact_id, 'update', r.id, jsonb_build_object('connection_status', r.connection_status, 'connection_level_set', '1st degree', 'basis', 'accepted or already connected implies 1st degree'));
  end loop;
  update contacts set connection_level = '1st degree', updated_at = now()
   where connection_status::text in ('Accepted','Already connected') and connection_level is null;
end $$;
create or replace function public.fn_contacts_degree_guard() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $$
begin
  -- Accepted / already connected IS 1st degree: derive it rather than block.
  if new.connection_status::text in ('Accepted','Already connected') and new.connection_level is null then
    new.connection_level := '1st degree';
  end if;
  -- A request to a 2nd or 3rd degree profile must say which. Fails closed on the state change.
  if new.connection_status::text = 'Request sent' and new.connection_level is null
     and (tg_op = 'INSERT' or new.connection_status is distinct from old.connection_status or new.connection_level is distinct from old.connection_level) then
    raise exception 'connection_level is required when connection_status is Request sent (contact %). Source the degree from Sales Nav before recording the request.', coalesce(new.contact_id, new.id::text)
      using errcode = 'check_violation';
  end if;
  return new;
end $$;
drop trigger if exists trg_contacts_degree_guard on public.contacts;
create trigger trg_contacts_degree_guard before insert or update on public.contacts for each row execute function public.fn_contacts_degree_guard();
revoke execute on function public.fn_contacts_degree_guard() from public, anon, authenticated;
