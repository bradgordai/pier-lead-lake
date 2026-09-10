-- 083 F13.1 (2026-09-10): stamp touch_date at send time.
-- send-approved-callback marks a row Sent and writes sent_at_actual but left touch_date at the
-- draft's original date. Every user-facing date and the chase clock read touch_date.
-- fn_apply_send_effects is the ONE place the consequences of a real send are written; the
-- callback calls it after marking the row Sent. Later F13 migrations extend its body.
create or replace function public.fn_apply_send_effects(p_outreach_log_id uuid, p_source text default 'send-approved-callback')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  r public.outreach_log%rowtype;
  v_sent_on date;
  v_changes jsonb := '{}'::jsonb;
begin
  select * into r from public.outreach_log where id = p_outreach_log_id;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if r.send_status::text <> 'Sent' or r.sent_at_actual is null then
    return jsonb_build_object('error','not_sent','send_status',r.send_status,'sent_at_actual',r.sent_at_actual);
  end if;
  v_sent_on := (r.sent_at_actual at time zone 'Europe/London')::date;

  -- F13.1 the touch carries the date it actually went out.
  if r.touch_date is distinct from v_sent_on then
    update public.outreach_log set touch_date = v_sent_on, updated_at = now() where id = r.id;
    v_changes := v_changes || jsonb_build_object('touch_date', jsonb_build_object('from', r.touch_date, 'to', v_sent_on));
  end if;

  if v_changes <> '{}'::jsonb then
    insert into public.audit_log(team_id, entity_type, entity_id, action, summary, after_value, source)
    values (r.team_id, 'outreach_log', r.id, 'send_effects', 'F13: consequences of a real send applied', v_changes, p_source);
  end if;
  return jsonb_build_object('outreach_log_id', r.id, 'sent_on', v_sent_on, 'changes', v_changes);
end $$;
revoke all on function public.fn_apply_send_effects(uuid, text) from public;
grant execute on function public.fn_apply_send_effects(uuid, text) to service_role;

-- Repair: only rows THIS system dispatched (phantom_run_id set). Migrated legacy rows that were
-- never dispatched here are untouched.
do $$
declare r record; v_run text := 'f13-1-touch-date-2026-09-10'; v_out jsonb;
begin
  for r in select o.id, o.touch_id, o.touch_date, o.sent_at_actual from public.outreach_log o
            where o.phantom_run_id is not null and o.send_status::text = 'Sent' and o.sent_at_actual is not null
              and o.touch_date is distinct from (o.sent_at_actual at time zone 'Europe/London')::date loop
    v_out := public.fn_apply_send_effects(r.id, 'migration 083 repair');
    insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 'f13_1_touch_date', 'outreach_log', r.touch_id, 'update', r.id,
              jsonb_build_object('before', r.touch_date, 'sent_at_actual', r.sent_at_actual, 'result', v_out));
  end loop;
end $$;
