-- 074: F12 T2 (2026-09-09). Seven contacts created since 5 Sep carry source_list 'P0 Sales Nav List'
-- because the Make scenario was pointed at the wrong Sales Nav list. They are in scope; only the
-- label is wrong. Relabelled to 'Lovable Master List'. Nothing deleted.
do $$
declare v_run text := 'f12-source-list-2026-09-09'; r record;
begin
  for r in select id, contact_id, source_list, sn_lists from contacts where source_list='P0 Sales Nav List' and created_at >= '2026-09-05' loop
    insert into migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 't2_relabel', 'contacts', r.contact_id, 'update', r.id, jsonb_build_object('before', jsonb_build_object('source_list', r.source_list, 'sn_lists', r.sn_lists), 'after', jsonb_build_object('source_list', 'Lovable Master List')));
  end loop;
  update contacts set source_list = 'Lovable Master List',
    sn_lists = array_replace(coalesce(sn_lists, '{}'), 'P0 Sales Nav List', 'Lovable Master List'),
    updated_at = now()
  where source_list='P0 Sales Nav List' and created_at >= '2026-09-05';
end $$;
