-- 155 F24 Task 3 CORRECTION to 154 (applied 30 Sep 2026, minutes after 154).
-- DEFECT in 154: fn_contact_duplicate_guard read hit.id when the slug rung had not run (no linkedin_slug), and plpgsql
-- raises 55000 'record "hit" is not assigned yet'. Every contact INSERT without a slug failed (Lovable New contact form,
-- Sales Nav leads that carry only a /sales/lead/ URL). Found by the post-apply rolled-back probe; no ingest call reached
-- the function in between (checked below in the report). Fix: initialise the record before the rungs. Logic unchanged.

create or replace function public.fn_contact_duplicate_guard() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare hit record; why text; k text := public.fn_contact_name_key(new.first_name, new.last_name);
begin
  -- 155: initialise the record, else the name rung reads hit.id on an unassigned record (SQLSTATE 55000)
  select null::uuid as id, null::text as ref, null::text as nm, null::timestamptz as archived_at into hit;
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

