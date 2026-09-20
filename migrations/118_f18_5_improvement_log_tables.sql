-- 118_f18_5_improvement_log_tables.sql
-- F18.5(a)(e): the improvement log moves out of the shared artifact and into Supabase.
-- Three new tables, team-scoped like refusals / company_alerts (team_id + fn_user_teams()).
-- Data arrives in 118b_f18_5_improvement_log_import*.sql. The activity triggers are created
-- at the END of the 118b import so that the import itself writes no activity rows.
--
-- RLS design
--   read  : any authenticated member of the team (fn_user_teams()).
--   write : only users for whom fn_improvement_log_can_edit(team_id) is true.
--   anon  : nothing. No policy and all table privileges revoked.
-- team_members.role exists but only holds 'admin' (Brad) and 'member' (Oliver AND Jack), so
-- the role alone cannot tell Oliver (editor) from Jack (read-only), and team_members is out
-- of scope for this change. fn_improvement_log_can_edit() therefore says: team admin, OR a
-- team member whose auth email is in the short editor list inside the function. A future
-- 'editor' role value is honoured too, so the list can be retired without touching policies.

create table public.improvements (
  id                 uuid primary key default gen_random_uuid(),
  team_id            uuid not null references public.teams(id),
  item_key           text not null,
  title              text not null,
  category           text not null,
  owner              text not null,
  priority           text not null,
  status             text not null default 'open',
  raised_by          text,
  created_at         timestamptz not null default now(),
  build_wave         integer,
  blocks             text[] not null default '{}',
  blocked_by         text[] not null default '{}',
  done_by            text,
  done_at            timestamptz,
  pinned             boolean not null default false,
  hidden             boolean not null default false,
  seen_by            jsonb not null default '{}'::jsonb,
  detail             text not null default '',
  notes              text not null default '',
  linked_company_id  uuid references public.companies(id),
  linked_contact_id  uuid references public.contacts(id),
  updated_at         timestamptz not null default now(),
  constraint improvements_team_item_key_uniq unique (team_id, item_key),
  constraint improvements_status_chk check (status in ('open','done')),
  constraint improvements_priority_chk check (priority in ('blocker','must','nice','question','parked'))
);

comment on table public.improvements is
  'F18.5 improvement log. item_key is the human i-number from the original log (e.g. i094): unique per team, never renumbered.';
comment on column public.improvements.blocks is 'item_key values this item unblocks';
comment on column public.improvements.blocked_by is 'item_key values that must land first';
comment on column public.improvements.seen_by is 'jsonb object: display name -> ISO timestamp last seen';

create index improvements_team_status_idx on public.improvements (team_id, status);
create index improvements_linked_company_idx on public.improvements (linked_company_id) where linked_company_id is not null;
create index improvements_linked_contact_idx on public.improvements (linked_contact_id) where linked_contact_id is not null;

create table public.improvement_comments (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references public.teams(id),
  improvement_id  uuid not null references public.improvements(id) on delete cascade,
  who             text not null,
  at              timestamptz not null default now(),
  text            text not null
);
create index improvement_comments_improvement_idx on public.improvement_comments (improvement_id, at);

-- improvement_id is nullable + ON DELETE SET NULL so that the 'delete' activity row survives
-- the row it describes; item_key keeps the human identity.
create table public.improvement_activity (
  id              uuid primary key default gen_random_uuid(),
  team_id         uuid not null references public.teams(id),
  improvement_id  uuid references public.improvements(id) on delete set null,
  item_key        text,
  who             text not null default 'system',
  at              timestamptz not null default now(),
  action          text not null,
  before          jsonb,
  after           jsonb
);
create index improvement_activity_improvement_idx on public.improvement_activity (improvement_id, at desc);
create index improvement_activity_team_at_idx on public.improvement_activity (team_id, at desc);

-- updated_at: the repo's standard trigger function
create trigger tg_improvements_updated_at
  before update on public.improvements
  for each row execute function public.tg_update_updated_at();

-- who may edit the improvement log
create or replace function public.fn_improvement_log_can_edit(p_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select exists (
    select 1
    from public.team_members tm
    join auth.users u on u.id = tm.user_id
    where tm.team_id = p_team_id
      and tm.user_id = (select auth.uid())
      and (
        tm.role in ('admin', 'editor')
        or lower(u.email) in ('oliver.muller@pierinsurance.com')
      )
  );
$fn$;

revoke all on function public.fn_improvement_log_can_edit(uuid) from public;
revoke all on function public.fn_improvement_log_can_edit(uuid) from anon;
grant execute on function public.fn_improvement_log_can_edit(uuid) to authenticated, service_role;

-- privileges: anon gets nothing; authenticated gets only what the policies can use
revoke all on public.improvements, public.improvement_comments, public.improvement_activity from anon;
revoke all on public.improvements, public.improvement_comments, public.improvement_activity from authenticated;
grant select, insert, update on public.improvements to authenticated;
grant select, insert, update, delete on public.improvement_comments to authenticated;
grant select on public.improvement_activity to authenticated;

alter table public.improvements enable row level security;
alter table public.improvement_comments enable row level security;
alter table public.improvement_activity enable row level security;

-- improvements: team reads, editors insert/update. No delete policy: the log never deletes.
create policy improvements_team_read on public.improvements
  for select to authenticated
  using (team_id in (select fn_user_teams()));
create policy improvements_editor_insert on public.improvements
  for insert to authenticated
  with check (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id));
create policy improvements_editor_update on public.improvements
  for update to authenticated
  using (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id))
  with check (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id));

-- comments: team reads, editors write
create policy improvement_comments_team_read on public.improvement_comments
  for select to authenticated
  using (team_id in (select fn_user_teams()));
create policy improvement_comments_editor_insert on public.improvement_comments
  for insert to authenticated
  with check (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id));
create policy improvement_comments_editor_update on public.improvement_comments
  for update to authenticated
  using (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id))
  with check (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id));
create policy improvement_comments_editor_delete on public.improvement_comments
  for delete to authenticated
  using (team_id in (select fn_user_teams()) and fn_improvement_log_can_edit(team_id));

-- activity: team reads; rows are written only by the SECURITY DEFINER triggers (118b tail)
create policy improvement_activity_team_read on public.improvement_activity
  for select to authenticated
  using (team_id in (select fn_user_teams()));
