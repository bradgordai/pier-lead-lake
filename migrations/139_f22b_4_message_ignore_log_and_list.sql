-- 139 F22B.4: the reply queue holds only things that are plausibly Pier replies. Nothing is discarded silently.
-- (d) message_ignore_log: every inbox message that is NOT queued and NOT filed lands here with its reason
--     (own_message_unmatched, no_evidence_of_pier_outreach, permanent_ignore_list). Low priority, audited monthly.
--     reviewed_at / reviewed_by let the monthly audit mark what it looked at.
-- (e) message_ignore_list: known non-prospects, permanent. Matched on the counterpart's Sales Navigator member
--     token (linkedin_urn) or public slug. Seeded with Brad's own profile (the 22 Sep InMail dispatch test).
--     Oliver adds to it from the Reconciliation screen ("always ignore this sender").
create table if not exists public.message_ignore_log (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  external_key text,
  source text,
  channel text,
  thread_url text,
  counterpart_urn text,
  sender_name text,
  sender_occupation text,
  message_body text,
  message_at timestamptz,
  is_from_me boolean,
  reason text not null check (reason in ('own_message_unmatched','no_evidence_of_pier_outreach','permanent_ignore_list')),
  evidence_checked jsonb,
  payload jsonb,
  from_unmatched_id uuid,
  reviewed_at timestamptz,
  reviewed_by uuid,
  created_at timestamptz not null default now(),
  unique (team_id, external_key)
);
create index if not exists message_ignore_log_team_created_idx on public.message_ignore_log (team_id, created_at desc);
alter table public.message_ignore_log enable row level security;
drop policy if exists message_ignore_log_team_read on public.message_ignore_log;
create policy message_ignore_log_team_read on public.message_ignore_log for select to authenticated
  using (team_id in (select fn_user_teams()));
drop policy if exists message_ignore_log_team_review on public.message_ignore_log;
create policy message_ignore_log_team_review on public.message_ignore_log for update to authenticated
  using (team_id in (select fn_user_teams())) with check (team_id in (select fn_user_teams()));

create table if not exists public.message_ignore_list (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  linkedin_urn text,
  linkedin_slug text,
  display_name text not null,
  reason text not null check (length(btrim(reason)) > 0),
  added_by uuid default auth.uid(),
  added_at timestamptz not null default now(),
  check (linkedin_urn is not null or linkedin_slug is not null)
);
create unique index if not exists message_ignore_list_urn_uq on public.message_ignore_list (team_id, linkedin_urn) where linkedin_urn is not null;
create unique index if not exists message_ignore_list_slug_uq on public.message_ignore_list (team_id, lower(linkedin_slug)) where linkedin_slug is not null;
alter table public.message_ignore_list enable row level security;
drop policy if exists message_ignore_list_team_read on public.message_ignore_list;
create policy message_ignore_list_team_read on public.message_ignore_list for select to authenticated
  using (team_id in (select fn_user_teams()));
drop policy if exists message_ignore_list_team_insert on public.message_ignore_list;
create policy message_ignore_list_team_insert on public.message_ignore_list for insert to authenticated
  with check (team_id in (select fn_user_teams()));
drop policy if exists message_ignore_list_team_delete on public.message_ignore_list;
create policy message_ignore_list_team_delete on public.message_ignore_list for delete to authenticated
  using (team_id in (select fn_user_teams()));

-- Seed: Brad's own profile, taken from the queued 22 Sep InMail dispatch test (never hardcode the team id).
insert into public.message_ignore_list (team_id, linkedin_urn, display_name, reason, added_by)
select u.team_id, u.payload->>'urn', 'Bradley Gordon (Brad, Pier builder)', 'Internal: Brad''s own profile, used for dispatch tests', null
  from public.unmatched_replies u
 where u.message_body like 'InMail dispatch test from Pier Lead Lake%' and u.payload->>'urn' is not null
 limit 1
on conflict do nothing;
do $$ begin
  if (select count(*) from public.message_ignore_list) <> 1 then raise exception 'ignore list seed failed'; end if;
end $$;
