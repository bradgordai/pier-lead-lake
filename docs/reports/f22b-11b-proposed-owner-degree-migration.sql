-- PROPOSAL ONLY (F22B.11(b)), NOT APPLIED, NOT IN /migrations. Brad to approve, then copy to migrations/ with the next number.
-- (1) OWNER. 88 contacts have no owner_user_id (75 from the 22 Sep Sales Nav import: upsert-contact-from-sales-nav never
--     sets one; 13 older). The ONLY default is Oliver. A BEFORE INSERT trigger fills a missing owner with Oliver; the
--     88 are backfilled with before-values in migration_audit. Jack's 79 are untouched (they already have an owner).
-- (2) RELATIVE DEGREE. connection_level is a degree RELATIVE TO ONE LinkedIn account, and today nothing says whose.
--     Every scraper runs on Oliver's account, so on Jack's contacts the stored degree is Oliver's degree, not Jack's.
--     Two columns record whose network the degree was read from and when; v_contact_degree shows the degree as "n/a
--     for this owner" when the observer is not the owner. Nothing that gates (fn_evaluate_gates, the six priority
--     functions) reads connection_level, so this changes no consent outcome; run the refusal snapshot anyway.
create or replace function public.fn_contacts_default_owner() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.owner_user_id is null then new.owner_user_id := '6d282957-f63b-49d6-a4de-5a9a947b4284'; end if; -- Oliver
  return new;
end $$;
create trigger trg_contacts_default_owner before insert on public.contacts
  for each row execute function public.fn_contacts_default_owner();

insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f22b-11b', 'owner_backfill', 'contacts', c.contact_id, 'set_owner_oliver', c.id, jsonb_build_object('before_owner', null)
  from public.contacts c where c.owner_user_id is null;
update public.contacts set owner_user_id = '6d282957-f63b-49d6-a4de-5a9a947b4284' where owner_user_id is null;

alter table public.contacts add column if not exists connection_level_observer uuid;       -- whose LinkedIn saw this degree
alter table public.contacts add column if not exists connection_level_observed_at timestamptz;
update public.contacts set connection_level_observer = '6d282957-f63b-49d6-a4de-5a9a947b4284'  -- every scraper runs as Oliver
 where connection_level is not null and connection_level_observer is null;

create or replace view public.v_contact_degree with (security_invoker = true) as
select c.id as contact_id, c.team_id, c.owner_user_id, c.connection_level, c.connection_level_observer, c.connection_level_observed_at,
       case when c.connection_level is null then null
            when c.connection_level_observer is distinct from c.owner_user_id then 'n/a for this owner'
            else c.connection_level::text end as degree_for_owner
  from public.contacts c;
grant select on public.v_contact_degree to authenticated;
