-- 161 F25 Task 4: layer 5 becomes small addressable rules the drafter reads, behind a human gate.
-- (a) generate-draft-from-context v46 reads learned_correction_rules (status 'active', scoped) into the USER prompt.
-- (b) outreach_log.applied_correction_rule_ids uuid[]: the ids of the rules that were in the prompt, so a rule's effect on
--     rejections can be measured. Written once at draft insert.
-- (c) learned_correction_rules_status_check measured 2 Oct as ('active','deleted') ONLY; extended to
--     proposed | active | rejected | superseded | deleted. distill-learned-corrections v3 writes 'proposed' and no longer
--     marks every active rule 'deleted' on each run. supersedes_ids carries the ids a proposed rule replaces; when Oliver
--     APPROVES it (status -> active), trg_learned_rule_supersede retires exactly those rules to 'superseded' with
--     superseded_by = the new rule. Nothing is ever retired by the distiller itself.
--     The voice_assets 'learned_corrections' row is no longer written or read for drafting; its body is left untouched and
--     only its version string is changed to say it is historical.
-- CROSS LOGIC (measured 2 Oct): no SQL function reads learned_correction_rules; after this the only reader is the
-- drafter. fn_evaluate_gates, the chase engine and the send path are unaffected.

alter table public.learned_correction_rules drop constraint if exists learned_correction_rules_status_check;
alter table public.learned_correction_rules add constraint learned_correction_rules_status_check
  check (status in ('proposed','active','rejected','superseded','deleted'));
alter table public.learned_correction_rules add column if not exists supersedes_ids uuid[] not null default '{}';
alter table public.learned_correction_rules add column if not exists superseded_by uuid
  references public.learned_correction_rules(id) on delete set null;
create index if not exists learned_correction_rules_team_status_idx on public.learned_correction_rules (team_id, status);

create or replace function public.fn_learned_rule_supersede() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
begin
  if new.status = 'active' and old.status is distinct from 'active' and cardinality(new.supersedes_ids) > 0 then
    update public.learned_correction_rules
       set status = 'superseded', superseded_by = new.id, edited_at = now()
     where team_id = new.team_id and id = any(new.supersedes_ids) and id <> new.id and status in ('active','proposed');
  end if;
  return new;
end $$;
drop trigger if exists trg_learned_rule_supersede on public.learned_correction_rules;
create trigger trg_learned_rule_supersede after update of status on public.learned_correction_rules
  for each row execute function public.fn_learned_rule_supersede();

alter table public.outreach_log add column if not exists applied_correction_rule_ids uuid[];
comment on column public.outreach_log.applied_correction_rule_ids is
  'F25.4b: learned_correction_rules ids that were in the drafting prompt for this row (drafter v46+). Null on older rows.';

update public.voice_assets
   set version = 'lc-v1 HISTORICAL (2026-09-23; 4 rules). Not read since F25 (2 Oct 2026): the drafter reads learned_correction_rules directly.'
 where id = 'learned_corrections';
