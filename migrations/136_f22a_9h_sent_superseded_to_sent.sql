-- 136 F22A.9(h): the 136 outreach_log rows that are send_status 'Sent' + draft_status 'superseded' are real sends with a
-- wrong draft flag (F20.14: 125 CRs + 11 initial messages, 130 migrated, no run id, none with a sent twin). Restore
-- draft_status to 'sent'. send_status is NOT touched: the migration asserts that no row changed send_status.
-- This REPLACES F22A.9(c) ("move 138 to Cancelled"), which would have erased 136 real touches from the history.
do $$ declare n int; moved int; begin
  create temp table _f22_136 on commit drop as
    select id, send_status::text ss from public.outreach_log where send_status = 'Sent' and draft_status = 'superseded';
  select count(*) into n from _f22_136;
  if n <> 136 then raise exception 'expected 136 Sent+superseded rows, found %', n; end if;

  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22a-2026-09-22', 'f22a_9h_sent_superseded', 'outreach_log', t.id::text, 'draft_status_superseded_to_sent', t.id,
         jsonb_build_object('before', 'superseded', 'after', 'sent', 'send_status', t.ss)
    from _f22_136 t;

  update public.outreach_log o set draft_status = 'sent' from _f22_136 t where o.id = t.id;

  select count(*) into moved from public.outreach_log o join _f22_136 t on t.id = o.id where o.send_status::text <> t.ss;
  if moved <> 0 then raise exception 'send_status changed on % rows; rolling back', moved; end if;
  raise notice '136 rows restored to draft_status sent; send_status unchanged on all';
end $$;
