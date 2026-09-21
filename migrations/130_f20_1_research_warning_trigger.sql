-- 130 F20.1(b): the research warning no longer depends on which drafter version is deployed.
-- The drafter change that fills outreach_log.research_warning is committed (1e5ad02) but its production deploy
-- was refused by the permission system on 21 Sep, while migration 127 had already opened the gate. Without
-- this, a draft for an un-researched company would arrive with no flag at all. A BEFORE INSERT trigger sets
-- the warning for any new unsent draft whose company is not 'Deep research done' (or has no company), unless
-- the writer already supplied one. It never blocks or alters anything else.
create or replace function public.fn_stamp_research_warning() returns trigger
language plpgsql set search_path to 'public','pg_temp' as $$
declare v_stage text; v_found boolean := false;
begin
  if new.research_warning is not null or new.send_status::text <> 'Draft'
     or new.touch_type::text in ('Reply','Connection request') then
    return new;
  end if;
  if new.contact_id is not null then
    select co.research_stage::text, true into v_stage, v_found
      from public.contacts c join public.companies co on co.id = c.company_id where c.id = new.contact_id;
  end if;
  if not coalesce(v_found, false) then
    new.research_warning := 'COMPANY NOT DEEP RESEARCHED (no company linked): written without company research. Check it before sending.';
  elsif v_stage is distinct from 'Deep research done' then
    new.research_warning := 'COMPANY NOT DEEP RESEARCHED (' || coalesce(v_stage, 'no stage') || '): written without company research, so the hook is generic. Check it before sending.';
  end if;
  return new;
end $$;
drop trigger if exists trg_stamp_research_warning on public.outreach_log;
create trigger trg_stamp_research_warning before insert on public.outreach_log
  for each row execute function public.fn_stamp_research_warning();
