-- 176 F26.1 Task 10: a send logged by hand moves the contact exactly like an agent send.
--
-- Paths that record a send (measured 5 Oct):
--   1. dispatch: send-approved-draft launches, send-approved-callback (the ONE place a dispatched send becomes Sent)
--      sets send_status = 'Sent' and calls fn_apply_send_effects explicitly. 44 dispatched message rows, all with effects.
--   2. manual log in Lovable (Outreach "mark as sent" / log a touch): writes the outreach_log row as Sent directly and
--      never calls fn_apply_send_effects. 43 message rows since 1 Sep, none with effects.
--   (3. SQL / future paths: anything that sets send_status = 'Sent'.)
-- Choice: an AFTER trigger on outreach_log, so no present or future path can skip it. The callback's explicit call
-- stays and becomes a no-op through the idempotency marker.
--
-- Scope: message touches only: Initial message, Chase, Chaser 1/2/3, Follow up (exactly the types the dispatch path has
-- ever applied effects to). NOT Connection request (its state is connection_status; ~100 hand-logged CRs a week would
-- otherwise start chase clocks), NOT Reply (mostly inbound), NOT Other.
--
-- fn_apply_send_effects changes:
--   - idempotent: outreach_log.send_effects_applied_at; a row already applied returns 'already_applied' and does nothing;
--   - consent: a contact with promise_of_quiet, is_blocked, do_not_contact or outreach_status 'Do not contact' is never
--     moved (the row is marked, the skip audited);
--   - order-safe: the chase clock and state come from the contact's LATEST sent message, so replaying an older row
--     never moves the clock backwards; an older row only marks itself;
--   - a manual row without sent_at_actual falls back to its touch_date.

alter table public.outreach_log add column if not exists send_effects_applied_at timestamptz;
comment on column public.outreach_log.send_effects_applied_at is
  'F26.1 T10: when fn_apply_send_effects processed this Sent row. Non-null means never again (idempotency).';

-- rows the dispatch path already processed
update public.outreach_log o set send_effects_applied_at = a.created_at
  from (select entity_id, min(created_at) created_at from public.audit_log where action = 'send_effects' group by 1) a
 where a.entity_id = o.id and o.send_effects_applied_at is null;

create or replace function public.fn_is_message_touch(p_touch text)
returns boolean language sql immutable parallel safe set search_path = pg_catalog as $$
  select p_touch in ('Initial message', 'Chase', 'Chaser 1', 'Chaser 2', 'Chaser 3', 'Follow up')
$$;

create or replace function public.fn_apply_send_effects(p_outreach_log_id uuid, p_source text default 'send-approved-callback')
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  r public.outreach_log%rowtype;
  c public.contacts%rowtype;
  v_sent_on date;
  v_last_on date;
  v_latest_id uuid;
  v_latest_type text;
  v_interval int := 7;
  v_chasers int := 0;
  v_prior int := 0;
  v_new_type text;
  v_changes jsonb := '{}'::jsonb;
  v_contact_changes jsonb := '{}'::jsonb;
  v_new_state text;
  v_new_status text;
begin
  select * into r from public.outreach_log where id = p_outreach_log_id;
  if not found then return jsonb_build_object('error','not_found'); end if;
  if r.send_status::text <> 'Sent' then
    return jsonb_build_object('error','not_sent','send_status',r.send_status);
  end if;
  if r.send_effects_applied_at is not null then
    return jsonb_build_object('outreach_log_id', r.id, 'status', 'already_applied', 'applied_at', r.send_effects_applied_at);
  end if;
  if r.sent_at_actual is null and r.touch_date is null then
    return jsonb_build_object('error','no_send_date');
  end if;
  v_sent_on := coalesce((r.sent_at_actual at time zone 'Europe/London')::date, r.touch_date);

  if r.touch_type::text = 'Chase' then
    select count(*) into v_prior from public.outreach_log o
     where o.contact_id = r.contact_id and o.id <> r.id and o.send_status::text = 'Sent'
       and o.touch_type::text like 'Chaser %' and o.channel::text = r.channel::text;
    v_new_type := 'Chaser ' || least(v_prior + 1, 3);
    update public.outreach_log set touch_type = v_new_type::public.outreach_type, updated_at = now() where id = r.id;
    v_changes := v_changes || jsonb_build_object('touch_type', jsonb_build_object('from', 'Chase', 'to', v_new_type));
    r.touch_type := v_new_type::public.outreach_type;
  end if;

  if r.sent_at_actual is not null and r.touch_date is distinct from v_sent_on then
    update public.outreach_log set touch_date = v_sent_on, updated_at = now() where id = r.id;
    v_changes := v_changes || jsonb_build_object('touch_date', jsonb_build_object('from', r.touch_date, 'to', v_sent_on));
  end if;

  if r.contact_id is not null then
    select * into c from public.contacts where id = r.contact_id;
    if found then
      if coalesce(c.promise_of_quiet, false) or coalesce(c.is_blocked, false) or coalesce(c.do_not_contact, false)
         or c.outreach_status::text = 'Do not contact' then
        v_changes := v_changes || jsonb_build_object('contact', 'skipped: consent or block flag, contact not moved');
      else
        -- the latest sent message of this contact decides the clock and the state (order-safe replay)
        select o.id, o.touch_type::text, coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date)
          into v_latest_id, v_latest_type, v_last_on
          from public.outreach_log o
         where o.contact_id = c.id and o.send_status::text = 'Sent' and public.fn_is_message_touch(o.touch_type::text)
         order by coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date) desc nulls last, o.sent_at_actual desc nulls last, o.id
         limit 1;
        if v_latest_id is null or v_sent_on >= v_last_on then
          v_latest_id := r.id; v_latest_type := r.touch_type::text; v_last_on := v_sent_on;
        end if;

        select coalesce(ts.chase_interval_days, 7) into v_interval from public.team_settings ts where ts.team_id = r.team_id;
        v_interval := coalesce(v_interval, 7);
        select count(*) into v_chasers from public.outreach_log o
         where o.contact_id = c.id and o.send_status::text = 'Sent' and o.touch_type::text like 'Chaser %';
        v_new_state := case
          when v_latest_type like 'Chaser %' and v_chasers >= 2 then 'chaser_2_sent'
          when v_latest_type like 'Chaser %' and v_chasers = 1 then 'chaser_1_sent'
          else 'awaiting_reply' end;
        v_new_status := case when c.outreach_status::text in ('Not started','To contact','Ready') then 'Contacted' else c.outreach_status::text end;

        if v_latest_id = r.id then
          if c.cooldown_until is not null then
            v_contact_changes := v_contact_changes || jsonb_build_object('cooldown_until', jsonb_build_object('from', c.cooldown_until, 'to', null));
          end if;
          if c.chase_state is distinct from v_new_state then
            v_contact_changes := v_contact_changes || jsonb_build_object('chase_state', jsonb_build_object('from', c.chase_state, 'to', v_new_state));
          end if;
        end if;
        if c.outreach_status::text is distinct from v_new_status then
          v_contact_changes := v_contact_changes || jsonb_build_object('outreach_status', jsonb_build_object('from', c.outreach_status, 'to', v_new_status));
        end if;
        update public.contacts set
          cooldown_until = case when v_latest_id = r.id then null else cooldown_until end,
          chase_state = case when v_latest_id = r.id then v_new_state else chase_state end,
          chaser_count = v_chasers,
          chase_last_outbound_at = v_last_on,
          chase_next_due_at = v_last_on + v_interval,
          last_contacted = greatest(coalesce(last_contacted, v_last_on), v_last_on),
          outreach_status = v_new_status::public.outreach_status,
          updated_at = now()
        where id = c.id;
        v_contact_changes := v_contact_changes || jsonb_build_object('chase_last_outbound_at', v_last_on, 'chase_next_due_at', v_last_on + v_interval,
                                                                     'chaser_count', v_chasers, 'latest_message', v_latest_id);
        v_changes := v_changes || jsonb_build_object('contact', v_contact_changes);
      end if;
    end if;
  end if;

  update public.outreach_log set send_effects_applied_at = now() where id = r.id;
  insert into public.audit_log(team_id, entity_type, entity_id, action, summary, after_value, source)
  values (r.team_id, 'outreach_log', r.id, 'send_effects', 'F13/F26.1: consequences of a real send applied', v_changes, p_source);
  return jsonb_build_object('outreach_log_id', r.id, 'sent_on', v_sent_on, 'changes', v_changes);
end $function$;
revoke execute on function public.fn_apply_send_effects(uuid, text) from public, anon, authenticated;

create or replace function public.fn_send_effects_trigger()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform public.fn_apply_send_effects(new.id, 'trigger:' || coalesce(nullif(new.sent_by, ''), current_user));
  return null;
end $$;
revoke execute on function public.fn_send_effects_trigger() from public, anon, authenticated;

drop trigger if exists trg_send_effects_on_sent on public.outreach_log;
create trigger trg_send_effects_on_sent after insert or update of send_status on public.outreach_log
  for each row
  when (new.send_status::text = 'Sent' and new.send_effects_applied_at is null and public.fn_is_message_touch(new.touch_type::text))
  execute function public.fn_send_effects_trigger();

-- REPAIR: replay the effects for hand-logged message sends since 1 September, once per contact on its latest unapplied row
-- (order-safe), then mark the remaining older rows applied. Consent / blocked contacts are skipped by the function.
create temp table _t10 on commit drop as
select distinct on (o.contact_id) o.contact_id, o.id
  from public.outreach_log o
 where o.send_status::text = 'Sent' and o.phantom_run_id is null and o.send_effects_applied_at is null
   and public.fn_is_message_touch(o.touch_type::text)
   and coalesce(o.sent_at_actual, o.touch_date::timestamptz) >= '2026-09-01' and o.contact_id is not null
 order by o.contact_id, coalesce((o.sent_at_actual at time zone 'Europe/London')::date, o.touch_date) desc, o.sent_at_actual desc nulls last;

select count(*) as replayed, count(*) filter (where public.fn_apply_send_effects(id, 'f26_1_t10_replay') ? 'changes') as applied from _t10;

update public.outreach_log o set send_effects_applied_at = now()
 where o.send_status::text = 'Sent' and o.phantom_run_id is null and o.send_effects_applied_at is null
   and public.fn_is_message_touch(o.touch_type::text)
   and coalesce(o.sent_at_actual, o.touch_date::timestamptz) >= '2026-09-01' and o.contact_id in (select contact_id from _t10);
