-- 110 F17.3 (i096): revision_number is assigned by the database, never trusted from application code.
-- The app computed it from a count and landed on a number already taken, so Approve showed a green toast
-- (status saved) and a red one (revision insert refused). Whatever number the caller sends, a taken or
-- missing number becomes max+1 for that draft, serialised per draft. The unique constraint stays as the guard.
create or replace function public.fn_assign_revision_number() returns trigger
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_max int;
begin
  perform pg_advisory_xact_lock(hashtext('draft_rev:' || new.outreach_log_id::text));
  select max(revision_number) into v_max from public.draft_revisions where outreach_log_id = new.outreach_log_id;
  if new.revision_number is null
     or exists (select 1 from public.draft_revisions d where d.outreach_log_id = new.outreach_log_id and d.revision_number = new.revision_number) then
    new.revision_number := coalesce(v_max, -1) + 1;
  end if;
  return new;
end $$;
drop trigger if exists trg_assign_revision_number on public.draft_revisions;
create trigger trg_assign_revision_number before insert on public.draft_revisions
  for each row execute function public.fn_assign_revision_number();
