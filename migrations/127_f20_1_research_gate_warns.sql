-- 127 F20.1: the deep-research gate becomes a WARNING. Approved by Oliver on the 21 Sep call; design intent per Brad.
-- ONE condition changes in fn_evaluate_gates (the consent layer): the research branch is skipped while
-- team_settings.research_gate_warns_only is true. Every other gate is byte-identical, because the live
-- definition is rewritten by exact text replacement, not retyped. Set the flag false to restore refusal.
-- THE CONSENT PROOF runs outside this file, because evaluating the group guard for all 799 active contacts
-- exceeds one statement's timeout (two in-migration attempts timed out and rolled back cleanly): every
-- contact's outcome on initial_message and chaser is snapshotted in batches into public._f20_gate_snap BEFORE
-- this migration and again AFTER, and compared. Result recorded in migration_audit and in the F20 report.
alter table public.team_settings add column if not exists research_gate_warns_only boolean not null default true;
alter table public.team_settings add column if not exists max_drafts_per_run integer not null default 20;
comment on column public.team_settings.research_gate_warns_only is
  'true = a company that is not deep researched no longer blocks a draft; the draft is flagged instead and Oliver decides. Consent gates are unaffected.';
comment on column public.team_settings.max_drafts_per_run is
  'Ceiling on drafts the 06:15 engine may create in one run, across all routes (F20.11c).';

do $$
declare v_def text;
  v_old constant text := E'AND NOT (p_requested = ''reply'' AND coalesce(s.reply_ignores_research_gate, false));';
  v_rep constant text := E'AND NOT (p_requested = ''reply'' AND coalesce(s.reply_ignores_research_gate, false))\n                        AND NOT coalesce(s.research_gate_warns_only, false);';
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'fn_evaluate_gates';
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'research condition not found exactly once in fn_evaluate_gates; nothing changed';
  end if;
  execute replace(v_def, v_old, v_rep);
end $$;
