-- 128 F20.1(c): record the consent proof for migration 127 and remove the scratch table it used.
-- Snapshots of fn_evaluate_gates for all 799 active contacts x (initial_message, chaser) were taken in batches
-- before and after 127. Result: 1,598 evaluations each side, 505 changed, ALL 505 were
-- company_not_deep_researched (501 -> PASS, 4 -> thread_text_missing), 0 changes from any other code.
insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f20-2026-09-21', 'f20_1_research_gate_warns', 'function', 'fn_evaluate_gates', 'consent_proof', null,
  jsonb_build_object(
    'evaluations_each_side', (select count(*) from public._f20_gate_snap where phase = 'before'),
    'changed', (select count(*) from public._f20_gate_snap b join public._f20_gate_snap a on a.id = b.id and a.req = b.req and a.phase = 'after' where b.phase = 'before' and a.code <> b.code),
    'changed_that_were_not_research', (select count(*) from public._f20_gate_snap b join public._f20_gate_snap a on a.id = b.id and a.req = b.req and a.phase = 'after' where b.phase = 'before' and a.code <> b.code and b.code <> 'company_not_deep_researched'),
    'before', (select jsonb_object_agg(code, n) from (select code, count(*) n from public._f20_gate_snap where phase = 'before' group by 1) x),
    'after',  (select jsonb_object_agg(code, n) from (select code, count(*) n from public._f20_gate_snap where phase = 'after' group by 1) x));
drop table public._f20_gate_snap;
