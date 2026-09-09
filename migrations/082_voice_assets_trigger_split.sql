-- 082 (F12 T6 fix, 2026-09-09): the version-history insert ran BEFORE the parent row existed,
-- so the FK on voice_asset_versions refused the very first load. Split into a BEFORE trigger
-- (guard + updated_at) and an AFTER trigger (history row).
create or replace function public.fn_voice_assets_version() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if tg_op = 'UPDATE' and new.body = old.body and new.version = old.version then return new; end if;
  if tg_op = 'UPDATE' and new.version = old.version then
    raise exception 'voice_assets: a body change must carry a new version (was %)', old.version using errcode='check_violation';
  end if;
  new.updated_at := now();
  return new;
end $$;
create or replace function public.fn_voice_assets_record_version() returns trigger language plpgsql set search_path to 'public','pg_temp' as $$
begin
  if tg_op = 'UPDATE' and new.body = old.body and new.version = old.version then return new; end if;
  insert into public.voice_asset_versions (asset_id, version, body, updated_by) values (new.id, new.version, new.body, new.updated_by);
  return new;
end $$;
drop trigger if exists trg_voice_assets_version on public.voice_assets;
create trigger trg_voice_assets_version before insert or update on public.voice_assets for each row execute function public.fn_voice_assets_version();
drop trigger if exists trg_voice_assets_record_version on public.voice_assets;
create trigger trg_voice_assets_record_version after insert or update on public.voice_assets for each row execute function public.fn_voice_assets_record_version();
