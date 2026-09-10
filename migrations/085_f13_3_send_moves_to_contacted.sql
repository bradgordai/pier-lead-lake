-- 085 F13.3 (2026-09-10): a real send moves the contact to Contacted. Never downgrades a status
-- further along the funnel (In conversation, Meeting booked, Cooldown, Parked, any consent status).
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
  v_new_status text;
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

  if r.contact_id is not null then
    select * into c from public.contacts where id = r.contact_id;
    if found then
      -- F13.2 the chase clock restarts from the real send; any chase cooldown is over.
      select coalesce(ts.chase_interval_days, 7) into v_interval from public.team_settings ts where ts.team_id = r.team_id;
      v_interval := coalesce(v_interval, 7);
      select count(*) into v_chasers from public.outreach_log o
       where o.contact_id = c.id and o.send_status::text = 'Sent' and o.touch_type::text like 'Chaser %';
      v_new_state := case
        when r.touch_type::text like 'Chaser %' and v_chasers >= 2 then 'chaser_2_sent'
        when r.touch_type::text like 'Chaser %' and v_chasers = 1 then 'chaser_1_sent'
        else 'awaiting_reply' end;
      -- F13.3 status: only the pre-contact statuses move; anything further along is kept.
      v_new_status := case when c.outreach_status::text in ('Not started','To contact','Ready') then 'Contacted' else c.outreach_status::text end;

      if c.cooldown_until is not null then
        v_contact_changes := v_contact_changes || jsonb_build_object('cooldown_until', jsonb_build_object('from', c.cooldown_until, 'to', null));
      end if;
      if c.chase_state is distinct from v_new_state then
        v_contact_changes := v_contact_changes || jsonb_build_object('chase_state', jsonb_build_object('from', c.chase_state, 'to', v_new_state));
      end if;
      if c.outreach_status::text is distinct from v_new_status then
        v_contact_changes := v_contact_changes || jsonb_build_object('outreach_status', jsonb_build_object('from', c.outreach_status, 'to', v_new_status));
      end if;
      update public.contacts set
        cooldown_until = null,
        chase_state = v_new_state,
        chaser_count = v_chasers,
        chase_last_outbound_at = v_sent_on,
        chase_next_due_at = v_sent_on + v_interval,
        last_contacted = greatest(coalesce(last_contacted, v_sent_on), v_sent_on),
        outreach_status = v_new_status::public.outreach_status,
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

-- Repair: contacts with a sent message (not a connection request) still Not started / To contact.
do $$
declare r record; v_run text := 'f13-3-contacted-2026-09-10';
begin
  for r in select c.id, c.contact_id, c.first_name, c.last_name, c.outreach_status,
                  (select max(coalesce(o.sent_at_actual::date, o.touch_date)) from public.outreach_log o where o.contact_id=c.id and o.send_status::text='Sent' and o.touch_type::text not in ('Reply','Connection request')) as last_msg
             from public.contacts c
            where c.team_id = 'ef73c15e-4d6f-4159-bcfa-cc76b5ae4972' and c.archived_at is null
              and c.outreach_status::text in ('Not started','To contact')
              and exists (select 1 from public.outreach_log o where o.contact_id=c.id and o.send_status::text='Sent' and o.touch_type::text not in ('Reply','Connection request')) loop
    update public.contacts set outreach_status = 'Contacted', updated_at = now() where id = r.id;
    insert into public.migration_audit(run_id, phase, entity, source_ref, action, target_id, detail)
      values (v_run, 'f13_3_contacted', 'contacts', r.contact_id, 'update', r.id,
              jsonb_build_object('name', r.first_name||' '||r.last_name, 'before', r.outreach_status, 'after', 'Contacted', 'last_msg', r.last_msg));
  end loop;
end $$;
