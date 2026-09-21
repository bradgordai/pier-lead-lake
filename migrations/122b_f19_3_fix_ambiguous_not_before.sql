-- 122b F19.3 FIX, found by the rolled-back test minutes after 122: inside fn_claim_send_slot the name
-- not_before is both a table column and the function's OUTPUT column, so the re-claim path (a second press on
-- an already-queued send) raised 42702 'column reference is ambiguous'. Qualified, and the function now
-- resolves any such conflict to the column. No behaviour change otherwise.
create or replace function public.fn_claim_send_slot(p_team_id uuid, p_outreach_log_id uuid, p_agent_id text)
returns table(launch_now boolean, not_before timestamptz, queue_position int)
language plpgsql security definer set search_path to 'public','pg_temp' as $$
#variable_conflict use_column
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
    update public.send_queue sq set status = 'queued', not_before = greatest(v_nb, sq.not_before) where sq.id = v_row.id;
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
