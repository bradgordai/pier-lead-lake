-- 065: F6.2 Contacts archived toggle.
-- contacts.company_archived_at mirrors companies.archived_at for the contact's company, kept in
-- step by triggers, so the Contacts list, pulse and counts can exclude "company archived" rows with
-- one plain column predicate (PostgREST cannot OR an embedded-column filter with company_id is null,
-- and 3 live contacts have no company). NULL = company live, or no company.
alter table public.contacts add column if not exists company_archived_at timestamptz;
comment on column public.contacts.company_archived_at is
  'F6.2 mirror of companies.archived_at for this contact''s company (trigger-maintained). NULL when the company is live or the contact has no company. Default Contacts view hides rows where this is set.';

create or replace function public.tg_contact_company_archived_from_company()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.company_archived_at := case when new.company_id is null then null
    else (select c.archived_at from public.companies c where c.id = new.company_id) end;
  return new;
end $$;

drop trigger if exists tg_contacts_company_archived on public.contacts;
create trigger tg_contacts_company_archived
  before insert or update of company_id on public.contacts
  for each row execute function public.tg_contact_company_archived_from_company();

create or replace function public.tg_company_archived_sync_contacts()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.contacts set company_archived_at = new.archived_at
   where company_id = new.id and company_archived_at is distinct from new.archived_at;
  return new;
end $$;

drop trigger if exists tg_companies_archived_sync_contacts on public.companies;
create trigger tg_companies_archived_sync_contacts
  after update of archived_at on public.companies
  for each row when (old.archived_at is distinct from new.archived_at)
  execute function public.tg_company_archived_sync_contacts();

-- Backfill.
update public.contacts ct set company_archived_at = co.archived_at
  from public.companies co
 where co.id = ct.company_id and ct.company_archived_at is distinct from co.archived_at;

create index if not exists idx_contacts_company_archived_at on public.contacts (company_archived_at) where company_archived_at is not null;
