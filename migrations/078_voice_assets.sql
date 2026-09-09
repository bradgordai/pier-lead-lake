-- 078: F12 T6 (2026-09-09). The four-layer draft stack as versioned rows (manifest s4). One
-- source; the drafter will read it at draft time (cutover is the next session) and stamp each
-- draft with the layer versions that produced it.
create table if not exists public.voice_assets (
  id text primary key,
  team_id uuid not null,
  layer int not null check (layer between 1 and 4),
  applies_to text[] not null default '{}',   -- message types; empty = all
  body text not null,
  version text not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
create table if not exists public.voice_asset_versions (
  id uuid primary key default gen_random_uuid(),
  asset_id text not null references public.voice_assets(id) on delete cascade,
  version text not null,
  body text not null,
  updated_by text,
  recorded_at timestamptz not null default now(),
  unique (asset_id, version)
);
alter table public.voice_assets enable row level security;
alter table public.voice_asset_versions enable row level security;
drop policy if exists voice_assets_team on public.voice_assets;
create policy voice_assets_team on public.voice_assets for select to authenticated using (team_id in (select fn_user_teams()));
drop policy if exists voice_asset_versions_team on public.voice_asset_versions;
create policy voice_asset_versions_team on public.voice_asset_versions for select to authenticated using (exists (select 1 from public.voice_assets a where a.id = asset_id and a.team_id in (select fn_user_teams())));
-- Every insert or body/version change is kept, so a draft can always name the exact text it used.
create or replace function public.fn_voice_assets_version() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if tg_op = 'UPDATE' and new.body = old.body and new.version = old.version then return new; end if;
  if tg_op = 'UPDATE' and new.version = old.version then
    raise exception 'voice_assets: a body change must carry a new version (was %)', old.version using errcode='check_violation';
  end if;
  new.updated_at := now();
  insert into public.voice_asset_versions (asset_id, version, body, updated_by) values (new.id, new.version, new.body, new.updated_by);
  return new;
end $$;
drop trigger if exists trg_voice_assets_version on public.voice_assets;
create trigger trg_voice_assets_version before insert or update on public.voice_assets for each row execute function public.fn_voice_assets_version();
-- Stamp on drafts: filled by the drafter once it reads from this table.
alter table public.outreach_log add column if not exists voice_stack_versions jsonb;
comment on column public.outreach_log.voice_stack_versions is 'F12 T6: {"pier_rules":"v2.0","pier_terminology":"v10.11","linkedin_architect":"v1.7","voice_oliver":"v..."} - the layer versions that produced this draft. Null = drafted before the cutover.';
