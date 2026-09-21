-- 122 F19.3: the send queue releases on the CALLBACK, not on a timer. Oliver approved this design on 18 Sep.
-- (a) in-flight = a send_queue row at 'launched' whose outreach_log row has not reached Sent or Cancelled.
-- (d) the dead-man's switch ships with it: 10 minutes with no terminal state marks the row STUCK and releases
--     the queue. It is not the mechanism; it is the net for PhantomBuster never calling back at all.
-- (f) the randomised 180-300 s gap stays on top, measured from the last terminal state or launch.
-- (c) an unmatched callback is PARKED in send_callback_orphans, never dropped.
alter table public.send_queue add column if not exists finished_at timestamptz;
alter table public.send_queue add column if not exists stuck_at timestamptz;
alter table public.send_queue add column if not exists released_by uuid;
alter table public.send_queue add column if not exists released_at timestamptz;
alter table public.send_queue drop constraint if exists send_queue_status_check;
alter table public.send_queue add constraint send_queue_status_check
  check (status in ('queued','draining','launched','done','failed','stuck','released','cancelled'));

create table if not exists public.send_callback_orphans (
  container_id text primary key,
  team_id uuid not null,
  payload jsonb not null,
  received_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolution text
);
alter table public.send_callback_orphans enable row level security;
drop policy if exists send_callback_orphans_team_read on public.send_callback_orphans;
create policy send_callback_orphans_team_read on public.send_callback_orphans for select to authenticated
  using (team_id in (select team_id from public.team_members where user_id = auth.uid()));
revoke all on public.send_callback_orphans from anon;

-- Reconcile the queue with the truth in outreach_log, then apply the dead-man's switch. Called by every
-- claim and every drain, so the queue can never freeze for ever.
create or replace function public.fn_send_queue_housekeeping(p_team_id uuid) returns integer
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_stuck integer;
begin
  update public.send_queue q set status = case when o.send_status::text = 'Sent' then 'done' else 'failed' end,
         finished_at = coalesce(q.finished_at, now())
    from public.outreach_log o
   where o.id = q.outreach_log_id and q.team_id = p_team_id and q.status in ('launched','stuck')
     and o.send_status::text in ('Sent','Cancelled');
  update public.send_queue q set status = 'stuck', stuck_at = now(),
         detail = 'No callback within 10 minutes of launch. Queue released. Check the send in LinkedIn before resending.'
   where q.team_id = p_team_id and q.status = 'launched' and q.launched_at < now() - interval '10 minutes';
  get diagnostics v_stuck = row_count;
  return v_stuck;
end $$;
revoke all on function public.fn_send_queue_housekeeping(uuid) from public, anon, authenticated;

create or replace function public.fn_claim_send_slot(p_team_id uuid, p_outreach_log_id uuid, p_agent_id text)
returns table(launch_now boolean, not_before timestamptz, queue_position int)
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_row public.send_queue; v_last timestamptz; v_nb timestamptz; v_in_flight boolean;
begin
  perform pg_advisory_xact_lock(hashtext('send_slot:' || p_agent_id));
  perform public.fn_send_queue_housekeeping(p_team_id);
  -- (a) THE GATE: something launched on this agent and not yet confirmed Sent or Cancelled.
  select exists (select 1 from public.send_queue l join public.outreach_log o on o.id = l.outreach_log_id
                  where l.agent_id = p_agent_id and l.status = 'launched' and l.outreach_log_id <> p_outreach_log_id
                    and o.send_status::text not in ('Sent','Cancelled')) into v_in_flight;
  -- (f) spacing on top: 180-300 s after the last launch or confirmed outcome on this agent.
  select max(greatest(coalesce(q.finished_at, '-infinity'), coalesce(q.launched_at, '-infinity'))) into v_last
    from public.send_queue q where q.agent_id = p_agent_id and q.status in ('launched','done','failed','stuck','released');
  select * into v_row from public.send_queue q where q.outreach_log_id = p_outreach_log_id;
  if found and v_row.status in ('queued','draining') then
    v_nb := greatest(v_row.not_before, coalesce(v_last, '-infinity'::timestamptz) + interval '180 seconds');
    if not v_in_flight and v_nb <= now() then
      return query select true, v_nb, 0; return;
    end if;
    update public.send_queue set status = 'queued', not_before = greatest(v_nb, not_before) where id = v_row.id;
    return query select false, greatest(v_nb, now()),
      (select count(*)::int from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining') and x.not_before <= v_row.not_before);
    return;
  end if;
  -- (h) an empty queue with nothing in flight and no recent send: not_before = now, launch immediately.
  v_nb := greatest(now(), coalesce(v_last, '-infinity'::timestamptz) + make_interval(secs => 180 + floor(random() * 121)),
                   coalesce((select max(x.not_before) from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining')), '-infinity'::timestamptz)
                     + make_interval(secs => 180 + floor(random() * 121)));
  if (select count(*) from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining')) = 0 and v_last is null then
    v_nb := now();
  end if;
  insert into public.send_queue (team_id, outreach_log_id, agent_id, not_before, status)
  values (p_team_id, p_outreach_log_id, p_agent_id, v_nb, 'queued')
  on conflict (outreach_log_id) do update set agent_id = excluded.agent_id, not_before = excluded.not_before, status = 'queued',
     launched_at = null, finished_at = null, stuck_at = null, detail = null;
  return query select (not v_in_flight and v_nb <= now()), v_nb,
    (select count(*)::int from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining') and x.not_before <= v_nb);
end $$;
revoke all on function public.fn_claim_send_slot(uuid, uuid, text) from public, anon, authenticated;

create or replace function public.fn_next_due_send(p_team_id uuid)
returns uuid language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_id uuid;
begin
  perform public.fn_send_queue_housekeeping(p_team_id);
  update public.send_queue q set status = 'draining'
   where q.id = (select s.id from public.send_queue s
                  where s.team_id = p_team_id and s.status = 'queued' and s.not_before <= now()
                    and not exists (select 1 from public.send_queue l join public.outreach_log o on o.id = l.outreach_log_id
                                     where l.agent_id = s.agent_id and l.status = 'launched'
                                       and o.send_status::text not in ('Sent','Cancelled'))
                  order by s.not_before limit 1 for update skip locked)
  returning q.outreach_log_id into v_id;
  return v_id;
end $$;
revoke all on function public.fn_next_due_send(uuid) from public, anon, authenticated;

-- (e) Oliver can release a stuck send himself. It only changes the queue row; it never sends anything.
create or replace function public.fn_release_send_queue(p_queue_id bigint) returns text
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_team uuid;
begin
  select team_id into v_team from public.send_queue where id = p_queue_id;
  if v_team is null then return 'not_found'; end if;
  if not exists (select 1 from public.team_members where team_id = v_team and user_id = auth.uid()) then return 'forbidden'; end if;
  update public.send_queue set status = 'released', released_by = auth.uid(), released_at = now(),
         finished_at = coalesce(finished_at, now())
   where id = p_queue_id and status in ('launched','stuck');
  return case when found then 'released' else 'nothing_to_release' end;
end $$;
revoke all on function public.fn_release_send_queue(bigint) from public, anon;
grant execute on function public.fn_release_send_queue(bigint) to authenticated;

-- What the Today strip reads: one row per queue entry that matters now, with the contact's name.
create or replace view public.v_send_queue_status with (security_invoker = true) as
select q.id as queue_id, q.team_id, q.status, q.agent_id, q.not_before, q.launched_at, q.finished_at, q.stuck_at, q.detail,
       o.id as outreach_log_id, o.channel::text as channel, o.touch_type::text as touch_type, o.send_status::text as send_status,
       c.id as contact_id, c.first_name || ' ' || c.last_name as contact_name, co.company_name,
       case when q.status in ('launched','stuck') then round(extract(epoch from now() - q.launched_at))::int end as seconds_in_flight
  from public.send_queue q
  join public.outreach_log o on o.id = q.outreach_log_id
  left join public.contacts c on c.id = o.contact_id
  left join public.companies co on co.id = c.company_id
 where q.status in ('queued','draining','launched','stuck')
    or (q.status in ('done','failed','released') and coalesce(q.finished_at, q.launched_at) >= date_trunc('day', now()));
grant select on public.v_send_queue_status to authenticated;

-- (i) regression: nothing may sit at 'launched' past 10 minutes without a terminal send_status or a stuck mark.
create or replace view public.v_regress_send_queue_launched_too_long with (security_invoker = true) as
select q.id, q.outreach_log_id, q.launched_at, o.send_status::text as send_status
  from public.send_queue q join public.outreach_log o on o.id = q.outreach_log_id
 where q.status = 'launched' and q.launched_at < now() - interval '10 minutes'
   and o.send_status::text not in ('Sent','Cancelled');
grant select on public.v_regress_send_queue_launched_too_long to authenticated;
