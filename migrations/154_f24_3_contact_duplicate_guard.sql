-- 154 F24 Task 3: stop NEW duplicate contacts (i163). The existing 133 name collisions are NOT merged or touched.
-- 133 names collide (lower(first_name||last_name)) across 268 contacts (Oliver counted 81 on 24 Sep, so it is growing);
-- 77 of those names carry two or more Sent connection requests, feeding the invitation wall.
-- The Sales Nav ingest dedupes on slug, URL, Sales Nav URL and URN, never on name + company, and a person re-exported
-- under a different Sales Nav URL came in twice.
--
-- GUARD: a BEFORE INSERT trigger on contacts refuses a row that matches an existing contact of the same team
--   1. on linkedin_slug (first), else
--   2. on normalised name (lower, non-alphanumerics stripped, first+last) AND the same company_id.
-- It raises SQLSTATE 23505 with a message starting "duplicate_contact" and detail "existing_contact_uuid=<uuid>".
-- upsert-contact-from-sales-nav v27 (deployed BEFORE this migration) catches exactly that and returns the EXISTING
-- contact (adds the list, logs no second CR row), so Make never sees a 500. The message deliberately avoids the text
-- "contact_id" so the ingest's contact_id-collision retry does not loop. The Lovable "New contact" form gets the same
-- readable error. Archived contacts count as existing (a re-import of an archived person should not resurrect a twin).

create or replace function public.fn_contact_name_key(p_first text, p_last text) returns text
language sql immutable set search_path to 'public', 'pg_temp' as $$
  select nullif(regexp_replace(lower(coalesce(p_first, '') || coalesce(p_last, '')), '[^[:alnum:]]', '', 'g'), '');
$$;

create index if not exists contacts_team_company_name_key_idx
  on public.contacts (team_id, company_id, public.fn_contact_name_key(first_name, last_name));
create index if not exists contacts_team_slug_idx on public.contacts (team_id, linkedin_slug) where linkedin_slug is not null;

create or replace function public.fn_contact_duplicate_guard() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare hit record; why text; k text := public.fn_contact_name_key(new.first_name, new.last_name);
begin
  if nullif(btrim(new.linkedin_slug), '') is not null then
    select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
      into hit from public.contacts c
     where c.team_id = new.team_id and c.linkedin_slug = new.linkedin_slug
     order by c.archived_at nulls first, c.created_at limit 1;
    why := 'LinkedIn slug';
  end if;
  if hit.id is null and k is not null and new.company_id is not null then
    select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
      into hit from public.contacts c
     where c.team_id = new.team_id and c.company_id = new.company_id
       and public.fn_contact_name_key(c.first_name, c.last_name) = k
     order by c.archived_at nulls first, c.created_at limit 1;
    why := 'name at the same company';
  end if;
  if hit.id is not null then
    raise exception using errcode = '23505',
      message = format('duplicate_contact: "%s %s" matches existing %s %s%s by %s. Use the existing contact instead of creating a second.',
                       coalesce(new.first_name, ''), coalesce(new.last_name, ''), hit.ref, hit.nm,
                       case when hit.archived_at is not null then ' (archived)' else '' end, why),
      detail = format('existing_contact_uuid=%s', hit.id);
  end if;
  return new;
end $$;

drop trigger if exists trg_contact_duplicate_guard on public.contacts;
create trigger trg_contact_duplicate_guard before insert on public.contacts
  for each row execute function public.fn_contact_duplicate_guard();
