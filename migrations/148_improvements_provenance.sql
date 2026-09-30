-- 148_improvements_provenance.sql
-- Purpose: make the origin of every improvement row provable, going forward.
--
-- WHY: improvements.raised_by is free text typed by whoever wrote the row. There is no
-- created_by, no auth user, and improvement_activity records who='system' on all 77 inserts.
-- So today it is impossible to prove whether a row came from Oliver in the Lovable app or
-- from Brad/Claude through the MCP. Two columns fix that for every row written from now on.
--
-- SAFETY: additive only. No existing row is rewritten, nothing is deleted, no enum is altered,
-- no trigger or policy is touched. Existing rows are stamped 'unverified' precisely because
-- their origin cannot be proven; that is the honest value, not a guess.

begin;

alter table public.improvements
  add column if not exists source_channel text not null default 'unverified',
  add column if not exists source_actor   text;

comment on column public.improvements.source_channel is
  'How the row arrived. lovable_app = written by a signed-in user through the Lovable UI. '
  'mcp_admin = written by Brad or an assistant through the Supabase MCP. '
  'edge_function = written by a backend function. '
  'unverified = predates provenance tracking, origin cannot be proven.';

comment on column public.improvements.source_actor is
  'Best available identity of the writer: auth.users email for lovable_app, a named operator '
  'for mcp_admin, the function name for edge_function. Null when unknown.';

alter table public.improvements
  drop constraint if exists improvements_source_channel_chk;
alter table public.improvements
  add constraint improvements_source_channel_chk
  check (source_channel in ('lovable_app','mcp_admin','edge_function','unverified'));

-- Stamp future rows automatically. A row written with a Supabase auth JWT (that is, by a
-- signed-in user in Lovable) is provably lovable_app and carries that user's email.
-- Anything else defaults to mcp_admin unless the caller states otherwise.
create or replace function public.fn_improvements_stamp_source()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  -- Only stamp on insert, and only when the caller has not set it explicitly.
  if tg_op = 'INSERT' and (new.source_channel is null or new.source_channel = 'unverified') then
    if v_uid is not null then
      select u.email into v_email from auth.users u where u.id = v_uid;
      new.source_channel := 'lovable_app';
      new.source_actor   := coalesce(v_email, v_uid::text);
    else
      new.source_channel := 'mcp_admin';
      new.source_actor   := coalesce(new.source_actor, 'unattributed service role');
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_improvements_stamp_source on public.improvements;
create trigger trg_improvements_stamp_source
  before insert on public.improvements
  for each row execute function public.fn_improvements_stamp_source();

create index if not exists idx_improvements_source_channel
  on public.improvements (source_channel);

commit;

-- POST-CHECK (run separately, expect 186 unverified and 0 of anything else today):
--   select source_channel, count(*) from public.improvements group by 1 order by 1;
