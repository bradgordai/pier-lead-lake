-- 084 F13.2 (2026-09-10): the three things called cooldown.
--   cr_blocked_until : six-month block on a NEW connection request to a Withdrawn contact. Kept,
--                      the gate enforces it (cr_cooldown_active fires only for connection_request).
--   chase cooldown   : rest after the final chaser (chase_state 'exhausted' + cooldown_until). Kept.
--   migration artefact: the 4 Sep migration wrote chase_state='cooldown' + cooldown_until onto
--                      Withdrawn contacts; some have since accepted and been messaged, and
--                      fn_chase_candidates skips anyone with cooldown_until in the future.
-- (i) a real send clears any chase cooldown and restarts the clock. (ii) repair at source.
create or replace function public.fn_apply_send_effects(p_outreach_log_id uuid, p_source text default 'send-approved-callback')
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare
  r public.outreach_log%rowtype;
  c public.contacts%rowtype;
  v_sent_on date;
  v_interval int := 7;
  v_chasers int := 0;
  v_changes jsonb := '{}'::jsonb;
  v_contact_changes jsonb := '{}'::jsonb;
  v_new_state text;
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

  -- F13.2 the chase clock restarts from the real send; any chase cooldown is over.
  if r.contact_id is not null then
    select * into c from public.contacts where id = r.contact_id;
    if found then
      select coalesce(ts.chase_interval_days, 7) into v_interval from public.team_settings ts where ts.team_id = r.team_id;
      v_interval := coalesce(v_interval, 7);
      select count(*) into v_chasers from public.outreach_log o
       where o.contact_id = c.id and o.send_status::text = 'Sent' and o.touch_type::text like 'Chaser %';
      v_new_state := case
        when r.touch_type::text like 'Chaser %' and v_chasers >= 2 then 'chaser_2_sent'
        when r.touch_type::text like 'Chaser %' and v_chasers = 1 then 'chaser_1_sent'
        else 'awaiting_reply' end;
      if c.cooldown_until is not null then
        v_contact_changes := v_contact_changes || jsonb_build_object('cooldown_until', jsonb_build_object('from', c.cooldown_until, 'to', null));
      end if;
      if c.chase_state is distinct from v_new_state then
        v_contact_changes := v_contact_changes || jsonb_build_object('chase_state', jsonb_build_object('from', c.chase_state, 'to', v_new_state));
      end if;
      update public.contacts set
        cooldown_until = null,
        chase_state = v_new_state,
        chaser_count = v_chasers,
        chase_last_outbound_at = v_sent_on,
        chase_next_due_at = v_sent_on + v_interval,
        last_contacted = greatest(coalesce(last_contacted, v_sent_on), v_sent_on),
        updated_at = now()
      where id = c.id;
      v_contact_changes := v_contact_changes || jsonb_build_object('chase_last_outbound_at', v_sent_on, 'chase_next_due_at', v_sent_on + v_interval, 'chaser_count', v_chasers);
      v_changes := v_changes || jsonb_build_object('contact', v_contact_changes);
    end if;
  end if;

  if v_changes <> '{}'::jsonb then
    insert into public.audit_log(team_id, entity_type, entity_id, action, summary, after_value, source)
    values (r.team_id, 'outreach_log', r.id, 'send_effects', 'F13: consequences of a real send applied', v_changes, p_source);
  end if;
  return jsonb_build_object('outreach_log_id', r.id, 'sent_on', v_sent_on, 'changes', v_changes);
end $$;

-- Repair at source. A migration artefact is a cooldown that was never earned: chase_state
-- 'cooldown' with zero sent chasers and the migration's stamp date (2027-02-25 / 2027-03-01).
-- Legitimate rests (chase_state 'exhausted', or an operator-set Cooldown with a chaser sent,
-- e.g. Lutz Schottenhammer 2027-08-16) are left alone.
do $$
declare r record; v_run text := 'f13-2-cooldown-artefacts-2026-09-10'; v_out jsonb; v_state text;
begin
  -- the two real sends: the full send effects
  for r in select o.id, o.touch_id from public.outreach_log o
            where o.phantom_run_id is not null and o.send_status::text = 'Sent' and o.sent_at_actual is not null loop
    v_out := public.fn_apply_send_effects(r.id, 'migration 084 repair');
    insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 'f13_2_send_effects', 'outreach_log', r.touch_id, 'update', r.id, v_out);
  end loop;
  -- the remaining artefacts among contacts messaged in the last 30 days
  for r in select c.id, c.contact_id, c.first_name, c.last_name, c.cooldown_until, c.chase_state, c.chaser_count,
                  (select max(coalesce(o.sent_at_actual::date, o.touch_date)) from public.outreach_log o where o.contact_id = c.id and o.send_status::text='Sent' and o.touch_type::text not in ('Reply','Connection request')) as last_msg,
                  (select max(o.touch_date) from public.outreach_log o where o.contact_id = c.id and o.touch_type::text = 'Reply') as last_reply
             from public.contacts c
            where c.team_id = 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972' and c.archived_at is null
              and c.chase_state = 'cooldown' and coalesce(c.chaser_count,0) = 0
              and c.cooldown_until in ('2027-02-25','2027-03-01')
              and c.last_contacted >= current_date - 30 loop
    v_state := case when r.last_reply is not null and (r.last_msg is null or r.last_reply >= r.last_msg) then 'replied' else 'none' end;
    update public.contacts set cooldown_until = null, chase_state = v_state, updated_at = now() where id = r.id;
    insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 'f13_2_clear_artefact', 'contacts', r.contact_id, 'update', r.id,
              jsonb_build_object('name', r.first_name||' '||r.last_name, 'before', jsonb_build_object('cooldown_until', r.cooldown_until, 'chase_state', r.chase_state), 'after', jsonb_build_object('cooldown_until', null, 'chase_state', v_state), 'last_msg', r.last_msg, 'last_reply', r.last_reply));
  end loop;
end $$;
