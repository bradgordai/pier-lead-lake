-- 108 F17 (Brad, 18 Sep): server-side minimum spacing between sends + a queue, and one open draft per contact per touch type.
create table if not exists public.send_queue (
  id bigint generated always as identity primary key,
  team_id uuid not null,
  outreach_log_id uuid not null unique references public.outreach_log(id),
  agent_id text not null,
  not_before timestamptz not null,
  status text not null default 'queued' check (status in ('queued','draining','launched','failed','cancelled')),
  launched_at timestamptz,
  detail text,
  created_at timestamptz not null default now()
);
create index if not exists send_queue_due on public.send_queue (agent_id, status, not_before);
alter table public.send_queue enable row level security;
drop policy if exists send_queue_team_read on public.send_queue;
create policy send_queue_team_read on public.send_queue for select to authenticated
  using (team_id in (select team_id from public.team_members where user_id = auth.uid()));

-- One slot per PhantomBuster agent, 180-300 s apart (randomised). Serialised by an advisory lock so two
-- simultaneous clicks cannot both read "free". Returns launch_now=false with the time the row will go.
create or replace function public.fn_claim_send_slot(p_team_id uuid, p_outreach_log_id uuid, p_agent_id text)
returns table(launch_now boolean, not_before timestamptz, queue_position int)
language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_row public.send_queue; v_last timestamptz; v_nb timestamptz;
begin
  perform pg_advisory_xact_lock(hashtext('send_slot:' || p_agent_id));
  select * into v_row from public.send_queue q where q.outreach_log_id = p_outreach_log_id;
  if found and v_row.status in ('queued','draining') then
    if v_row.not_before <= now() and not exists (
         select 1 from public.send_queue l where l.agent_id = p_agent_id and l.status = 'launched' and l.launched_at > now() - interval '180 seconds') then
      return query select true, v_row.not_before, 0; return;
    end if;
    return query select false, v_row.not_before,
      (select count(*)::int from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining') and x.not_before <= v_row.not_before);
    return;
  end if;
  select max(coalesce(q.launched_at, q.not_before)) into v_last from public.send_queue q
   where q.agent_id = p_agent_id and q.status in ('queued','draining','launched');
  v_nb := greatest(now(), coalesce(v_last, '-infinity'::timestamptz) + make_interval(secs => 180 + floor(random() * 121)));
  insert into public.send_queue (team_id, outreach_log_id, agent_id, not_before, status)
  values (p_team_id, p_outreach_log_id, p_agent_id, v_nb, 'queued')
  on conflict (outreach_log_id) do update set agent_id = excluded.agent_id, not_before = excluded.not_before, status = 'queued', launched_at = null, detail = null;
  return query select (v_nb <= now()), v_nb,
    (select count(*)::int from public.send_queue x where x.agent_id = p_agent_id and x.status in ('queued','draining') and x.not_before <= v_nb);
end $$;
revoke all on function public.fn_claim_send_slot(uuid, uuid, text) from public, anon, authenticated;

-- The drainer picks the oldest due row per call and marks it draining so it is never picked twice.
create or replace function public.fn_next_due_send(p_team_id uuid)
returns uuid language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_id uuid;
begin
  update public.send_queue q set status = 'draining'
   where q.id = (select s.id from public.send_queue s
                  where s.team_id = p_team_id and s.status = 'queued' and s.not_before <= now()
                    and not exists (select 1 from public.send_queue l where l.agent_id = s.agent_id and l.status = 'launched' and l.launched_at > now() - interval '180 seconds')
                  order by s.not_before limit 1 for update skip locked)
  returning q.outreach_log_id into v_id;
  return v_id;
end $$;
revoke all on function public.fn_next_due_send(uuid) from public, anon, authenticated;

-- One open draft per contact per touch type. A newer open draft supersedes the older ones, logged.
create or replace function public.fn_supersede_older_open_drafts() returns trigger
language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if new.contact_id is null or new.send_status::text not in ('Draft','Ready') or new.draft_status::text not in ('pending_review','approved') then
    return new;
  end if;
  insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
  select o.team_id, o.id, 'superseded_by_newer_open_draft', to_jsonb(o), jsonb_build_object('draft_status','superseded','superseded_by', new.id),
         'F17: one open draft per contact per touch type'
    from public.outreach_log o
   where o.contact_id = new.contact_id and o.touch_type = new.touch_type and o.id <> new.id
     and o.send_status::text in ('Draft','Ready') and o.draft_status::text in ('pending_review','approved');
  update public.outreach_log o set draft_status = 'superseded',
         rejection_feedback = jsonb_build_object('reason','superseded_by_newer_draft','detail','A newer open draft of the same touch type exists for this contact.','superseded_by', new.id)
   where o.contact_id = new.contact_id and o.touch_type = new.touch_type and o.id <> new.id
     and o.send_status::text in ('Draft','Ready') and o.draft_status::text in ('pending_review','approved');
  return new;
end $$;
drop trigger if exists trg_one_open_draft on public.outreach_log;
create trigger trg_one_open_draft after insert on public.outreach_log
  for each row execute function public.fn_supersede_older_open_drafts();

-- Clean up what exists today (Peretti P595 x3 Chaser 3, Dupuis P036 x2 Chaser 1). Keep the newest APPROVED
-- draft where one exists (it carries a human review), otherwise the newest; supersede the rest.
with open_d as (
  select o.*, row_number() over (partition by o.contact_id, o.touch_type
           order by (o.draft_status::text = 'approved') desc, o.created_at desc) rn
    from public.outreach_log o
   where o.contact_id is not null and o.send_status::text in ('Draft','Ready') and o.draft_status::text in ('pending_review','approved')
), logged as (
  insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
  select team_id, id, 'superseded_duplicate_open_draft', to_jsonb(open_d) - 'rn', jsonb_build_object('draft_status','superseded'),
         'F17 cleanup: duplicate open draft of the same touch type; newest approved kept'
    from open_d where rn > 1 returning outreach_log_id
)
update public.outreach_log o set draft_status = 'superseded',
       rejection_feedback = jsonb_build_object('reason','duplicate_open_draft','detail','Superseded 2026-09-18: another open draft of the same touch type exists for this contact (send outage re-draft).')
 where o.id in (select outreach_log_id from logged);
