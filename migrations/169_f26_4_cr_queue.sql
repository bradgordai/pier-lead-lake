-- 169 F26 Task 4: the connection request queue. Nothing here sends; the dispatcher (Task 6) ships switched off.
--
-- Eligibility, enforced in SQL (fn_cr_queue_candidates), never in the UI:
--   live contact (not archived, not a merge loser), connection_status Not connected or Ignored,
--   a LinkedIn URL (no URL, no CR), not 1st degree (a CR to a 1st-degree connection cannot be sent),
--   company outreach_mode continue or pause_messages (pause_crs / pause_all keep a contact out; no company = continue),
--   cr_blocked_until null or past, and fn_evaluate_gates returns NO refusal for a connection_request.
-- The brief says "no ABSOLUTE refusal". Today the gate has no warning channel: every code it returns is a refusal at
-- the moment of firing, so a contact it refuses could sit in the queue but never be dispatched. Requiring no refusal
-- is the same rule once the §9 flag conversions land (a converted code stops being returned), and keeps the queue to
-- people who can actually be sent a request today. Measured 5 Oct: 207 eligible on this rule, 240 on absolute-only.
--
-- Order (v_cr_queue_ordered, computed, never frozen): manual_rank asc (a drag always wins), lead_wave asc,
-- company score desc, queued_at asc.

create table if not exists public.cr_queue (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  contact_id uuid not null unique references public.contacts(id),
  status text not null default 'queued' check (status in ('queued','sent','skipped','cancelled')),
  queued_at timestamptz not null default now(),
  scheduled_for timestamptz,
  sent_at timestamptz,
  phantom_run_id text,
  outreach_log_id uuid references public.outreach_log(id),
  skip_reason text,
  manual_rank integer,
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now()
);
create index if not exists cr_queue_team_status_idx on public.cr_queue (team_id, status);
comment on table public.cr_queue is
  'F26.4: one row per contact queued for a LinkedIn connection request. Filled only by fn_cr_queue_populate (eligibility in SQL). Sent only by the dispatcher (Task 6), which re-checks the gate at firing.';

-- The app may reorder (manual_rank) and skip / cancel / re-queue. Only the dispatcher (service role) may mark sent.
create or replace function public.fn_cr_queue_guard()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at := now();
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    if new.status = 'sent' and old.status is distinct from 'sent' then
      raise exception 'cr_queue: only the dispatcher can mark a request sent' using errcode = 'check_violation';
    end if;
    if new.sent_at is distinct from old.sent_at or new.phantom_run_id is distinct from old.phantom_run_id
       or new.outreach_log_id is distinct from old.outreach_log_id or new.contact_id is distinct from old.contact_id
       or new.team_id is distinct from old.team_id then
      raise exception 'cr_queue: sent_at, phantom_run_id, outreach_log_id, contact_id and team_id are written by the system only' using errcode = 'check_violation';
    end if;
    if old.status = 'sent' then
      raise exception 'cr_queue: a sent request is history and cannot be changed' using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $$;
revoke execute on function public.fn_cr_queue_guard() from public, anon, authenticated;
drop trigger if exists trg_cr_queue_guard on public.cr_queue;
create trigger trg_cr_queue_guard before update on public.cr_queue for each row execute function public.fn_cr_queue_guard();

alter table public.cr_queue enable row level security;
drop policy if exists cr_queue_team_read on public.cr_queue;
create policy cr_queue_team_read on public.cr_queue for select to authenticated
  using (team_id in (select public.fn_user_teams()));
drop policy if exists cr_queue_team_update on public.cr_queue;
create policy cr_queue_team_update on public.cr_queue for update to authenticated
  using (team_id in (select public.fn_user_teams())) with check (team_id in (select public.fn_user_teams()));
revoke all on public.cr_queue from anon;
revoke insert, delete on public.cr_queue from authenticated;

-- Candidates: the eligibility rule in one place (populate, the dry run, and the dispatcher's re-check all use it).
create or replace function public.fn_cr_queue_candidates(p_team_id uuid)
returns table (contact_id uuid, lead_wave smallint, outreach_mode text, company_score integer)
language sql stable set search_path = public, pg_temp as $$
  select c.id, c.lead_wave, coalesce(co.outreach_mode, 'continue'), cs.score
    from public.contacts c
    left join public.companies co on co.id = c.company_id
    left join public.company_scores cs on cs.company_id = c.company_id
   where c.team_id = p_team_id
     and c.archived_at is null and c.merged_into_contact_id is null
     and c.connection_status::text in ('Not connected', 'Ignored')
     and c.linkedin_url_key is not null
     and c.connection_level is distinct from '1st degree'
     and coalesce(co.outreach_mode, 'continue') in ('continue', 'pause_messages')
     and (c.cr_blocked_until is null or c.cr_blocked_until <= current_date)
     and not exists (select 1 from public.fn_evaluate_gates(p_team_id, c.id, 'LinkedIn DM', 'connection_request'))
$$;
revoke execute on function public.fn_cr_queue_candidates(uuid) from public, anon, authenticated;

-- Populate: adds eligible contacts not already in the queue. Dry run writes nothing and returns the counts.
-- Refuses to add more than p_max (default 400) in one go unless told otherwise.
create or replace function public.fn_cr_queue_populate(p_team_id uuid, p_dry_run boolean default true, p_max integer default 400)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v jsonb; v_new int; v_added int := 0;
begin
  if auth.uid() is not null and p_team_id not in (select public.fn_user_teams()) then
    raise exception 'cr_queue: not a member of this team' using errcode = 'insufficient_privilege';
  end if;
  drop table if exists _crq;
  create temp table _crq on commit drop as
  select k.* from public.fn_cr_queue_candidates(p_team_id) k
   where not exists (select 1 from public.cr_queue q where q.contact_id = k.contact_id);
  select count(*) into v_new from _crq;
  v := jsonb_build_object(
    'dry_run', p_dry_run, 'would_add', v_new,
    'by_wave', (select jsonb_object_agg(coalesce(lead_wave::text, 'none'), n) from (select lead_wave, count(*) n from _crq group by 1) x),
    'by_outreach_mode', (select jsonb_object_agg(outreach_mode, n) from (select outreach_mode, count(*) n from _crq group by 1) x),
    'already_in_queue', (select count(*) from public.cr_queue where team_id = p_team_id));
  if p_dry_run then return v; end if;
  if v_new > p_max then
    return v || jsonb_build_object('added', 0, 'refused', format('would add %s, more than the cap of %s', v_new, p_max));
  end if;
  insert into public.cr_queue (team_id, contact_id, created_by)
  select p_team_id, contact_id, auth.uid() from _crq
  on conflict (contact_id) do nothing;
  get diagnostics v_added = row_count;
  return v || jsonb_build_object('added', v_added);
end $$;
-- Not granted to the app: the gate check runs per contact (about 0.15 s each), longer than a browser request should
-- wait. The dispatcher cron (Task 6) refreshes the queue; the screen only reads and reorders.
revoke execute on function public.fn_cr_queue_populate(uuid, boolean, integer) from public, anon, authenticated;

-- The ordered queue the screen and the dispatcher read. security_invoker so RLS on cr_queue applies to the app.
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
 where q.status = 'queued';
grant select on public.v_cr_queue_ordered to authenticated;
revoke all on public.v_cr_queue_ordered from anon;
