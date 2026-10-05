-- 172 F26 Task 6: the connection request dispatcher. SHIPS SWITCHED OFF. Brad turns it on himself.
--
-- One pg_cron entry, every minute:  select ... from team_settings where cr_dispatch_enabled
-- With the flag false the WHERE clause matches no row, so fn_cr_dispatch_tick is never even called: no phantom call,
-- no outreach_log row, no queue mutation, no state write.
--
-- With the flag true, one tick:
--   1. closes the books on the previous dispatch (outreach_log Sent -> cr_queue sent; Cancelled -> skipped);
--   2. waits while a dispatched CR is still in flight (not yet Sent or Cancelled): one at a time;
--   3. reads v_cr_allowance_today and STOPS on NULL (stale extractor) or remaining_today = 0. NULL is never zero;
--   4. waits until the random 60-180 s gap since the previous dispatch has passed;
--   5. takes the top row of v_cr_queue_ordered and RE-CHECKS it at this moment (status, mode, cr_blocked_until, URL,
--      fn_evaluate_gates for a connection_request). A refusal marks the row skipped with the reason; nothing launches;
--   6. writes the outreach_log row (touch_type Connection request, channel LinkedIn CR, approved, Ready, no note) and
--      hands it to fn_claim_send_slot on agent 7500783933729451. The existing send-queue-drain cron then launches it
--      through send-approved-draft, which re-runs the gate, the 120/week CR cap and TEST_MODE, and the callback
--      (send-approved-callback, the one place a send becomes Sent) closes it. There is no second launcher.
-- The send slot adds its own 180-300 s spacing per agent, so the effective gap is at least 180 s.
-- Once a day (first enabled tick of the UTC day) the tick refreshes the queue with fn_cr_queue_populate (cap 400).

alter table public.team_settings add column if not exists cr_dispatch_enabled boolean not null default false;
comment on column public.team_settings.cr_dispatch_enabled is
  'F26.6: master switch for the automatic connection request dispatcher. Default and shipped OFF. Only a team admin may turn it on; any member may turn it off.';

create table if not exists public.cr_dispatch_state (
  team_id uuid primary key references public.teams(id),
  last_tick_at timestamptz,
  last_result jsonb,
  last_dispatch_at timestamptz,
  next_earliest_at timestamptz,
  last_populated_on date
);
alter table public.cr_dispatch_state enable row level security;
drop policy if exists cr_dispatch_state_team_read on public.cr_dispatch_state;
create policy cr_dispatch_state_team_read on public.cr_dispatch_state for select to authenticated
  using (team_id in (select public.fn_user_teams()));
revoke all on public.cr_dispatch_state from anon;
revoke insert, update, delete on public.cr_dispatch_state from authenticated;

-- A dispatched row leaves the visible queue (it is now in the send queue / history).
create or replace view public.v_cr_queue_ordered with (security_invoker = true) as
select row_number() over (order by q.manual_rank asc nulls last, c.lead_wave asc nulls last, cs.score desc nulls last, q.queued_at asc, q.id) as position,
       q.id as queue_id, q.team_id, q.contact_id, c.contact_id as contact_ref,
       trim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')) as contact_name,
       c.job_title, c.lead_wave, c.lead_wave_source, c.connection_status::text as connection_status,
       c.connection_level::text as connection_level, c.linkedin_url,
       co.id as company_id, co.company_name, coalesce(co.outreach_mode, 'continue') as outreach_mode, cs.score as company_score,
       q.manual_rank, q.queued_at, q.scheduled_for, q.status
  from public.cr_queue q
  join public.contacts c on c.id = q.contact_id
  left join public.companies co on co.id = c.company_id
  left join public.company_scores cs on cs.company_id = c.company_id
 where q.status = 'queued' and q.outreach_log_id is null;
grant select on public.v_cr_queue_ordered to authenticated;
revoke all on public.v_cr_queue_ordered from anon;

-- Why one queued contact may not be sent a request right now (NULL = it may). Same rule as fn_cr_queue_candidates.
create or replace function public.fn_cr_dispatch_recheck(p_team_id uuid, p_contact_id uuid)
returns text language plpgsql stable set search_path = public, pg_temp as $$
declare c record; v_mode text; g record;
begin
  select * into c from public.contacts where id = p_contact_id and team_id = p_team_id;
  if not found then return 'contact_not_found'; end if;
  if c.archived_at is not null or c.merged_into_contact_id is not null then return 'contact_archived_or_merged'; end if;
  if c.connection_status::text not in ('Not connected', 'Ignored') then return 'connection_status_now_' || c.connection_status::text; end if;
  if c.linkedin_url_key is null then return 'no_linkedin_url'; end if;
  if c.connection_level is not distinct from '1st degree' then return 'already_1st_degree'; end if;
  if c.cr_blocked_until is not null and c.cr_blocked_until > current_date then return 'cr_blocked_until_' || c.cr_blocked_until; end if;
  select coalesce(co.outreach_mode, 'continue') into v_mode from public.companies co where co.id = c.company_id;
  if coalesce(v_mode, 'continue') not in ('continue', 'pause_messages') then return 'company_' || v_mode; end if;
  select * into g from public.fn_evaluate_gates(p_team_id, p_contact_id, 'LinkedIn CR', 'connection_request') limit 1;
  if g.reason_code is not null then return 'gate_' || g.reason_code; end if;
  return null;
end $$;
revoke execute on function public.fn_cr_dispatch_recheck(uuid, uuid) from public, anon, authenticated;

create or replace function public.fn_cr_dispatch_tick(p_team_id uuid, p_dry_run boolean default false)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare
  v_enabled boolean; st public.cr_dispatch_state; a record; top record; v_why text; v_log uuid; slot record;
  v_result jsonb; v_closed int := 0; v_skipped int := 0; v_inflight int; v_pop jsonb;
begin
  select cr_dispatch_enabled into v_enabled from public.team_settings where team_id = p_team_id;
  if not coalesce(v_enabled, false) and not p_dry_run then
    return jsonb_build_object('status', 'disabled');          -- belt and braces: the cron WHERE already filtered it
  end if;
  if not p_dry_run then
    perform pg_advisory_xact_lock(hashtext('cr_dispatch:' || p_team_id::text));
    insert into public.cr_dispatch_state (team_id) values (p_team_id) on conflict (team_id) do nothing;
  end if;
  select * into st from public.cr_dispatch_state where team_id = p_team_id;

  -- 1. close the books
  if not p_dry_run then
    update public.cr_queue q set status = 'sent', sent_at = coalesce(o.sent_at_actual, now())
      from public.outreach_log o
     where q.team_id = p_team_id and q.status = 'queued' and q.outreach_log_id = o.id and o.send_status::text = 'Sent';
    get diagnostics v_closed = row_count;
    update public.cr_queue q set status = 'skipped', skip_reason = 'send cancelled: ' || coalesce(o.rejection_feedback->>'reason', 'launch failed or cancelled')
      from public.outreach_log o
     where q.team_id = p_team_id and q.status = 'queued' and q.outreach_log_id = o.id and o.send_status::text = 'Cancelled';
  end if;

  -- 2. one in flight at a time
  select count(*) into v_inflight from public.cr_queue q join public.outreach_log o on o.id = q.outreach_log_id
   where q.team_id = p_team_id and q.status = 'queued' and o.send_status::text not in ('Sent', 'Cancelled');

  -- daily refresh of the queue (first enabled tick of the day)
  if not p_dry_run and (st.last_populated_on is null or st.last_populated_on < current_date) then
    v_pop := public.fn_cr_queue_populate(p_team_id, false, 400);
    update public.cr_dispatch_state set last_populated_on = current_date where team_id = p_team_id;
  end if;

  -- 3. the counter. NULL means stop.
  select * into a from public.v_cr_allowance_today where team_id = p_team_id;

  select * into top from public.v_cr_queue_ordered where team_id = p_team_id order by position limit 1;
  v_why := case when top.contact_id is null then null else public.fn_cr_dispatch_recheck(p_team_id, top.contact_id) end;

  v_result := jsonb_build_object(
    'at', now(), 'dry_run', p_dry_run, 'enabled', coalesce(v_enabled, false),
    'closed_sent', v_closed, 'in_flight', v_inflight,
    'allowance', jsonb_build_object('sent_today', a.sent_today, 'remaining_today', a.remaining_today, 'state', a.state, 'extractor_read_at', a.extractor_read_at),
    'next_earliest_at', st.next_earliest_at,
    'top', case when top.contact_id is null then null else jsonb_build_object('position', top.position, 'contact', top.contact_ref, 'name', top.contact_name,
            'company', top.company_name, 'lead_wave', top.lead_wave, 'company_score', top.company_score, 'manual_rank', top.manual_rank,
            'why_first', case when top.manual_rank is not null then 'manual_rank ' || top.manual_rank
                              else format('wave %s, company score %s, queued %s', top.lead_wave, coalesce(top.company_score::text, 'none'), to_char(top.queued_at, 'YYYY-MM-DD HH24:MI')) end,
            'recheck', coalesce(v_why, 'passes')) end,
    'populate', v_pop);

  if v_inflight > 0 then v_result := v_result || jsonb_build_object('status', 'waiting_in_flight');
  elsif a.remaining_today is null then v_result := v_result || jsonb_build_object('status', 'stopped_counter_stale');
  elsif a.remaining_today <= 0 then v_result := v_result || jsonb_build_object('status', 'stopped_at_cap');
  elsif st.next_earliest_at is not null and now() < st.next_earliest_at then v_result := v_result || jsonb_build_object('status', 'waiting_gap');
  elsif top.contact_id is null then v_result := v_result || jsonb_build_object('status', 'queue_empty');
  elsif v_why is not null then
    v_result := v_result || jsonb_build_object('status', 'skipped_top', 'skip_reason', v_why);
    if not p_dry_run then
      update public.cr_queue set status = 'skipped', skip_reason = v_why where id = top.queue_id;
    end if;
  elsif p_dry_run then
    v_result := v_result || jsonb_build_object('status', 'would_dispatch');
  else
    -- 6. write the Connection request row and hand it to the existing send queue. Nothing launches here.
    insert into public.outreach_log (team_id, touch_id, touch_date, contact_id, company_id, channel, touch_type,
                                     send_status, draft_status, agent_produced, sent_by, message_body)
    select p_team_id, 'cr-' || gen_random_uuid(), current_date, c.id, c.company_id, 'LinkedIn CR', 'Connection request',
           'Ready', 'approved', false, 'cr_dispatcher', null
      from public.contacts c where c.id = top.contact_id
    returning id into v_log;
    select * into slot from public.fn_claim_send_slot(p_team_id, v_log, '7500783933729451');
    update public.cr_queue set outreach_log_id = v_log, scheduled_for = slot.not_before where id = top.queue_id;
    update public.cr_dispatch_state set last_dispatch_at = now(),
           next_earliest_at = now() + make_interval(secs => 60 + floor(random() * 121)::int)
     where team_id = p_team_id;
    v_result := v_result || jsonb_build_object('status', 'dispatched', 'outreach_log_id', v_log, 'send_after', slot.not_before);
  end if;

  if not p_dry_run then
    update public.cr_dispatch_state set last_tick_at = now(), last_result = v_result where team_id = p_team_id;
  end if;
  return v_result;
end $$;
revoke execute on function public.fn_cr_dispatch_tick(uuid, boolean) from public, anon, authenticated;
comment on function public.fn_cr_dispatch_tick(uuid, boolean) is
  'F26.6: one dispatcher tick. p_dry_run = true reports exactly who would go next and why, writes nothing, ignores the flag.';

-- The master switch. ON needs a team admin; OFF any team member (Oliver can always stop it).
create or replace function public.fn_set_cr_dispatch_enabled(p_team uuid, p_on boolean)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or p_team not in (select public.fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if p_on is null then raise exception 'p_on must be true or false'; end if;
  if p_on and not exists (select 1 from public.team_members where team_id = p_team and user_id = auth.uid() and role = 'admin') then
    raise exception 'only a team admin can switch the connection request dispatcher on' using errcode = 'insufficient_privilege';
  end if;
  update public.team_settings set cr_dispatch_enabled = p_on, updated_at = now() where team_id = p_team;
  if not found then raise exception 'no settings row for team %', p_team; end if;
  return p_on;
end $$;
revoke execute on function public.fn_set_cr_dispatch_enabled(uuid, boolean) from public, anon;
grant execute on function public.fn_set_cr_dispatch_enabled(uuid, boolean) to authenticated;

-- The cron entry. With every flag false the WHERE matches nothing and the function is never called.
do $c$ begin
  if exists (select 1 from cron.job where jobname = 'cr-dispatch') then perform cron.unschedule('cr-dispatch'); end if;
  perform cron.schedule('cr-dispatch', '* * * * *',
    $job$select public.fn_cr_dispatch_tick(team_id, false) from public.team_settings where cr_dispatch_enabled$job$);
end $c$;

update public.team_settings set cr_dispatch_enabled = false where cr_dispatch_enabled;
