-- 132 F22A.2: the reply pipeline accepts both inbox scrapers.
-- (c) contacts.linkedin_urn: the Sales Navigator member token (ACwAA...) taken from EITHER /sales/lead/ or
--     /sales/people/ (any ",NAME_SEARCH,..." / ",name,..." suffix stripped), indexed, backfilled, and kept current
--     by a trigger whenever a URL field changes. NOT unique: 84 contacts share a token with a duplicate row today.
-- (g) linkedin_threads: one row per inbox thread per team, fed by both scrapers. total_message_count from the
--     scraper vs held_count in outreach_log; incomplete = total > held. Detection only; no back-scrape.
-- (d) the 6 migrated "Reply" rows that are Oliver's own messages are relabelled outbound ("Follow up"). Nothing
--     deleted; before/after in migration_audit. Contact chase_state is NOT touched (flagged in the report).

alter table public.contacts add column if not exists linkedin_urn text;
create index if not exists contacts_team_linkedin_urn_idx on public.contacts (team_id, linkedin_urn) where linkedin_urn is not null;

create or replace function public.fn_extract_linkedin_urn(p text) returns text
language sql immutable as $$ select substring(p from '(ACwAA[A-Za-z0-9_-]+)') $$;

create or replace function public.fn_contacts_stamp_urn() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  new.linkedin_urn := coalesce(public.fn_extract_linkedin_urn(new.linkedin_sales_nav_url),
                               public.fn_extract_linkedin_urn(new.linkedin_url),
                               public.fn_extract_linkedin_urn(new.linkedin_aliases::text),
                               new.linkedin_urn);
  return new;
end $$;
drop trigger if exists trg_contacts_stamp_urn on public.contacts;
create trigger trg_contacts_stamp_urn before insert or update of linkedin_sales_nav_url, linkedin_url, linkedin_aliases
  on public.contacts for each row execute function public.fn_contacts_stamp_urn();

update public.contacts set linkedin_urn = coalesce(public.fn_extract_linkedin_urn(linkedin_sales_nav_url),
                                                   public.fn_extract_linkedin_urn(linkedin_url),
                                                   public.fn_extract_linkedin_urn(linkedin_aliases::text))
 where linkedin_urn is distinct from coalesce(public.fn_extract_linkedin_urn(linkedin_sales_nav_url),
                                              public.fn_extract_linkedin_urn(linkedin_url),
                                              public.fn_extract_linkedin_urn(linkedin_aliases::text));

create table if not exists public.linkedin_threads (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  thread_url text not null,
  source text not null check (source in ('sales_nav_inbox','linkedin_inbox')),
  channel text,
  contact_id uuid references public.contacts(id) on delete set null,
  counterpart_urn text,
  total_message_count int,
  held_count int not null default 0,
  incomplete boolean generated always as (coalesce(total_message_count,0) > held_count) stored,
  last_message_at timestamptz,
  last_message_from_me boolean,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (team_id, thread_url)
);
create index if not exists linkedin_threads_contact_idx on public.linkedin_threads (contact_id);
alter table public.linkedin_threads enable row level security;
drop policy if exists linkedin_threads_team_read on public.linkedin_threads;
create policy linkedin_threads_team_read on public.linkedin_threads for select to authenticated
  using (team_id in (select tm.team_id from public.team_members tm where tm.user_id = auth.uid()));

-- (d) Oliver's own messages filed as Reply by the May workbook migration.
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f22a-2026-09-22', 'f22a_2d_reply_direction', 'outreach_log', o.id::text, 'relabel_outbound', o.id,
       jsonb_build_object('before', jsonb_build_object('touch_type', o.touch_type, 'message_body', o.message_body, 'reply_content', o.reply_content, 'sent_body', o.sent_body, 'sent_by', o.sent_by, 'reply_classification', o.reply_classification),
                          'after', jsonb_build_object('touch_type', 'Follow up', 'sent_by', 'Oliver'))
  from public.outreach_log o
 where o.id in ('945ace51-258a-45f2-9662-6f6c8bff8f52','b516c15d-86da-42f7-93f9-80c079ac7880','ec19df04-d10a-455c-9996-80043c702c97',
                '6f7b36cd-8c5a-4e27-934e-b4d21bc71320','0b07ad40-6023-4dc7-9b7e-941e11d511de','90df9a24-0914-41ef-b3bb-31b111d52ca8')
   and o.touch_type = 'Reply';

update public.outreach_log
   set touch_type = 'Follow up', sent_body = coalesce(sent_body, reply_content, message_body), sent_by = 'Oliver',
       reply_content = null, reply_received_at = null, reply_classification = null
 where id in ('945ace51-258a-45f2-9662-6f6c8bff8f52','b516c15d-86da-42f7-93f9-80c079ac7880','ec19df04-d10a-455c-9996-80043c702c97',
              '6f7b36cd-8c5a-4e27-934e-b4d21bc71320','0b07ad40-6023-4dc7-9b7e-941e11d511de','90df9a24-0914-41ef-b3bb-31b111d52ca8')
   and touch_type = 'Reply';
