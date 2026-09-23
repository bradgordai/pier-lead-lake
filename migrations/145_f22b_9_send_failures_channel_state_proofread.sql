-- 145 F22B.9: backlog items that belong with this work.
-- (a) i134 THE CANCELLED-DRAFT DEAD END. Decision: a failed send SUPERSEDES the stranded draft (with the reason) and
--     the card offers Regenerate; it never returns to Draft. Reason: every stranded row so far failed for a STRUCTURAL
--     cause (PhantomBuster "not delivered": InMail refused, not connected) — putting it back to Draft invites the same
--     failure again. A trigger does it at the moment send_status becomes Cancelled on an approved draft, so the
--     "approved plus Cancelled" state — and the raw-string refusal it produced — can no longer exist. The 3 rows
--     stranded today are superseded here with their reasons (before-values in migration_audit phase f22b_9a).
-- (c) i116 CHANNEL STATE: contact_profile_observations (what a profile scrape saw, dated) and v_contact_channels
--     (THREE states per route: open / closed / never_checked; an observation older than 60 days is stale). Nothing
--     writes observations yet (no profile scrape pipeline exists), so the count is zero. Written through
--     fn_record_profile_observation. F22B.2(h): an observation that no invitation is pending on a contact held at
--     "Request sent" opens a review_queue item 'cr_possibly_lapsed' with the observation date — the status is NOT
--     changed. NOT DONE: removing InMail-disabled contacts from the InMail queue means changing
--     fn_cold_inmail_candidates, which this batch must not touch (cross-logic B). Flagged.
-- (d) i133: contact_guidance_notes.applies_to_touch_type (a note for "Chaser 1" only) and contacts.chaser_interval_days
--     (this contact's rhythm instead of the team default). STORED ONLY: the drafter does not yet filter notes by touch
--     type and fn_chase_candidates (protected in this batch) does not yet read the override. Flagged.
-- (e) i098: outreach_log.proofread_flags / proofread_at / proofread_model, filled by the proofread-drafts function.
--     Flags only; the draft text is never changed.
-- (g) P701 signed twice ("Oliver\n\nOliver"): the draft predates drafter v43 (16 Sep; the old sign-off appender added a
--     name after the model had written one). On InMail v43 appends no name, so both trailing name lines are removed.
--     It is the only open draft with a doubled trailing name.

-- (a)
create or replace function public.fn_supersede_failed_send() returns trigger
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare why text;
begin
  if new.send_status::text = 'Cancelled' and old.send_status is distinct from new.send_status and new.draft_status::text = 'approved' then
    select q.detail into why from public.send_queue q where q.outreach_log_id = new.id order by q.created_at desc limit 1;
    new.draft_status := 'superseded';
    new.rejection_feedback := jsonb_build_object('reason', 'send_failed',
      'detail', 'The send did not go out' || coalesce(' (' || why || ')', '') || '. Regenerate to write a new draft; this one is closed.');
  end if;
  return new;
end $$;
drop trigger if exists trg_supersede_failed_send on public.outreach_log;
create trigger trg_supersede_failed_send before update of send_status on public.outreach_log
  for each row execute function public.fn_supersede_failed_send();

do $$ declare n int; begin
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  select 'f22b-2026-09-23', 'f22b_9a', 'outreach_log', o.id::text, 'supersede_stranded_send', o.id,
         jsonb_build_object('before', jsonb_build_object('draft_status', o.draft_status, 'send_status', o.send_status, 'rejection_feedback', o.rejection_feedback),
                            'queue_detail', (select q.detail from public.send_queue q where q.outreach_log_id = o.id order by q.created_at desc limit 1))
    from public.outreach_log o where o.draft_status::text = 'approved' and o.send_status::text = 'Cancelled';
  update public.outreach_log o set draft_status = 'superseded',
         rejection_feedback = case when o.rejection_feedback ? 'reason' and o.rejection_feedback->>'reason' = 'regenerated' then o.rejection_feedback
           else jsonb_build_object('reason', 'send_failed', 'detail', 'The send did not go out'
                || coalesce(' (' || (select q.detail from public.send_queue q where q.outreach_log_id = o.id order by q.created_at desc limit 1) || ')', '')
                || '. Regenerate to write a new draft; this one is closed.') end
   where o.draft_status::text = 'approved' and o.send_status::text = 'Cancelled';
  get diagnostics n = row_count;
  if n <> 3 then raise exception 'expected 3 stranded rows, found %', n; end if;
end $$;

-- (c)
create table if not exists public.contact_profile_observations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  contact_id uuid not null references public.contacts(id) on delete cascade,
  observed_at timestamptz not null default now(),
  source text not null,
  has_disabled_inmail boolean,
  connection_degree int check (connection_degree between 1 and 3),
  out_of_network boolean,
  is_open_link boolean,
  is_premium boolean,
  has_pending_invitation boolean,
  raw jsonb,
  created_at timestamptz not null default now()
);
create index if not exists contact_profile_observations_contact_idx on public.contact_profile_observations (contact_id, observed_at desc);
alter table public.contact_profile_observations enable row level security;
drop policy if exists contact_profile_observations_team_read on public.contact_profile_observations;
create policy contact_profile_observations_team_read on public.contact_profile_observations for select to authenticated
  using (team_id in (select fn_user_teams()));

alter table public.review_queue drop constraint if exists review_queue_kind_check;
alter table public.review_queue add constraint review_queue_kind_check check (kind in ('company_fuzzy_match','company_duplicate',
  'reply_answered_by_hand','reply_company_in_monday','reply_order_unknown','company_no_domain','cr_possibly_lapsed'));

create or replace function public.fn_record_profile_observation(p_contact uuid, p_source text, p_observed_at timestamptz,
  p_has_disabled_inmail boolean, p_connection_degree int, p_out_of_network boolean, p_is_open_link boolean,
  p_is_premium boolean, p_has_pending_invitation boolean, p_raw jsonb default null) returns uuid
language plpgsql set search_path to 'public', 'pg_temp' as $$
declare cid uuid; tid uuid; cs text; nm text;
begin
  select team_id, connection_status::text, coalesce(first_name,'') || ' ' || coalesce(last_name,'') into tid, cs, nm
    from public.contacts where id = p_contact;
  if tid is null then raise exception 'contact % not found', p_contact; end if;
  insert into public.contact_profile_observations (team_id, contact_id, observed_at, source, has_disabled_inmail, connection_degree,
    out_of_network, is_open_link, is_premium, has_pending_invitation, raw)
  values (tid, p_contact, coalesce(p_observed_at, now()), p_source, p_has_disabled_inmail, p_connection_degree, p_out_of_network,
    p_is_open_link, p_is_premium, p_has_pending_invitation, p_raw)
  returning id into cid;
  -- F22B.2(h): a live profile says no invitation is pending on a contact we hold at "Request sent" -> ASK, never change.
  if p_has_pending_invitation = false and cs = 'Request sent' then
    insert into public.review_queue (team_id, kind, title, detail, contact_id, payload, dedupe_key, source)
    values (tid, 'cr_possibly_lapsed', 'Connection request may have lapsed: ' || nm,
      'A profile scrape on ' || to_char(coalesce(p_observed_at, now()), 'YYYY-MM-DD') || ' saw no pending invitation, but we hold this contact at Request sent. The request may have expired, been withdrawn or declined.',
      p_contact, jsonb_build_object('observation_id', cid, 'observed_at', coalesce(p_observed_at, now())),
      'cr_lapsed:' || p_contact::text || ':' || to_char(coalesce(p_observed_at, now()), 'YYYY-MM-DD'), p_source)
    on conflict (team_id, dedupe_key) do nothing;
  end if;
  return cid;
end $$;

create or replace view public.v_contact_channels with (security_invoker = true) as
with last_obs as (
  select distinct on (o.contact_id) o.* from public.contact_profile_observations o order by o.contact_id, o.observed_at desc)
select c.id as contact_id, c.team_id, lo.observed_at, (lo.observed_at < now() - interval '60 days') as observation_stale,
       case when lo.id is null or lo.has_disabled_inmail is null then 'never_checked'
            when lo.has_disabled_inmail then 'closed' else 'open' end as inmail_state,
       case when lo.id is null or lo.has_disabled_inmail is null then null
            when lo.has_disabled_inmail then 'InMail disabled on the profile' end as inmail_reason,
       case when c.connection_status::text in ('Accepted','Already connected') then 'open'
            when lo.id is null then 'never_checked' else 'closed' end as dm_state,
       case when c.connection_status::text in ('Accepted','Already connected') then 'connected'
            when lo.id is not null then 'not connected on the last observation' end as dm_reason,
       lo.is_open_link, lo.is_premium, lo.has_pending_invitation, lo.connection_degree, lo.out_of_network, lo.source
  from public.contacts c left join last_obs lo on lo.contact_id = c.id;
grant select on public.v_contact_channels to authenticated;

-- (d)
alter table public.contact_guidance_notes add column if not exists applies_to_touch_type text;
alter table public.contacts add column if not exists chaser_interval_days int check (chaser_interval_days between 1 and 60);

-- (e)
alter table public.outreach_log add column if not exists proofread_flags jsonb;
alter table public.outreach_log add column if not exists proofread_at timestamptz;
alter table public.outreach_log add column if not exists proofread_model text;

-- (g) P701
do $$ declare r record; newbody text; begin
  select o.id, o.message_body into r from public.outreach_log o join public.contacts c on c.id = o.contact_id
   where c.contact_id = 'P701' and o.draft_status::text = 'pending_review' and o.channel::text = 'LinkedIn inMail'
     and o.message_body ~ '\n\s*Oliver\s*\n\s*Oliver\s*$';
  if r.id is null then raise exception 'P701 doubled sign-off not found'; end if;
  newbody := regexp_replace(r.message_body, '(\s*\n\s*Oliver)+\s*$', '');
  insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
  values ('f22b-2026-09-23', 'f22b_9g', 'outreach_log', r.id::text, 'strip_doubled_inmail_signoff', r.id,
          jsonb_build_object('before_tail', right(r.message_body, 120), 'after_tail', right(newbody, 120), 'before_md5', md5(r.message_body)));
  update public.outreach_log set message_body = newbody where id = r.id and md5(message_body) = md5(r.message_body);
end $$;
