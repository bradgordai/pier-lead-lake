-- 067: F8 reply matching. LinkedIn's inbox scraper hands us anonymised sender URLs
-- (/in/ACoAA...), an entity URN and a thread URL, never the public slug, so exact slug
-- matching only works for contacts we have already seen. Three additions:
--   1. contacts.linkedin_aliases: every opaque identifier that has ever been matched to this
--      contact (auto or by a human). Once learned, the sender exact-matches forever.
--   2. unmatched_replies: the orphan queue. An inbound we cannot file is stored, never dropped,
--      and assigned from Reconciliation > Unmatched replies.
--   3. outreach_log.external_key: sha256 of thread + timestamp + body so a replayed payload
--      (backfill, on-demand sync, the 4-hourly watcher re-sending the same inbox snapshot)
--      cannot create a second touch.
alter table public.contacts add column if not exists linkedin_aliases jsonb not null default '[]'::jsonb;
comment on column public.contacts.linkedin_aliases is
  'F8: opaque LinkedIn identifiers learned from matched inbound messages (anonymised /in/ACoAA... URLs, messaging thread URLs, participant entity URNs). Array of strings, lowercase. Any inbound whose identifiers intersect this array exact-matches.';
create index if not exists idx_contacts_linkedin_aliases on public.contacts using gin (linkedin_aliases jsonb_path_ops);

alter table public.outreach_log add column if not exists external_key text;
comment on column public.outreach_log.external_key is
  'F8 idempotency key for messages captured from LinkedIn: sha256(threadUrl|timestamp|body). Unique per team when set.';
create unique index if not exists uq_outreach_external_key on public.outreach_log (team_id, external_key) where external_key is not null;

create table if not exists public.unmatched_replies (
  id               uuid primary key default gen_random_uuid(),
  team_id          uuid not null,
  external_key     text not null,
  thread_url       text,
  sender_url       text,
  sender_urn       text,
  sender_first_name text,
  sender_last_name  text,
  sender_occupation text,
  message_body     text not null,
  message_at       timestamptz,
  is_from_me       boolean not null default false,
  payload          jsonb not null default '{}'::jsonb,
  candidates       jsonb not null default '[]'::jsonb,
  status           text not null default 'open' check (status in ('open','assigned','dismissed')),
  assigned_contact_id uuid references public.contacts(id) on delete set null,
  assigned_by      uuid,
  assigned_at      timestamptz,
  created_touch_id uuid references public.outreach_log(id) on delete set null,
  created_at       timestamptz not null default now(),
  unique (team_id, external_key)
);
comment on table public.unmatched_replies is
  'F8 orphan queue: inbound LinkedIn messages the matching ladder could not file. Assigned from Reconciliation, which learns the sender aliases and files the touch.';
create index if not exists idx_unmatched_replies_open on public.unmatched_replies (team_id, status, created_at desc);

alter table public.unmatched_replies enable row level security;
drop policy if exists unmatched_replies_team on public.unmatched_replies;
create policy unmatched_replies_team on public.unmatched_replies
  for all to authenticated
  using (team_id in (select public.fn_user_teams()))
  with check (team_id in (select public.fn_user_teams()));
