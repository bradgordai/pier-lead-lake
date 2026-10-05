-- 167 F26 Task 2: LinkedIn's pending-invitation list (PhantomBuster Sent Request Extractor 7326870632604661)
-- becomes the source of truth for connection_status = 'Request sent'.
--
-- No source gives an invitation DATE. sentDate is relative text ("Sent 2 weeks ago"). It is parsed to a MINIMUM
-- age in days at the moment of extraction and stored with that moment (cr_pending_label_at), so the age today is
-- cr_pending_min_age_days + whole days since cr_pending_label_at. Never a derived date.
--
-- Called by Edge Function ingest-sent-requests (one POST per extractor run, whole array). The logic lives here so
-- it can be dry-run in a rolled-back transaction and so a future caller cannot skip a guard.

-- 0. the match key, hardened against the extractor's real output (2 Oct container, 184 rows):
--    percent-encoded umlauts ('sch%C3%BChly') while 12 contacts store them raw ('kügel') and 68 encoded, and a
--    trailing locale segment ('/in/patrick-steiner-01aa7589/en/'). Decode, lowercase, strip scheme, www.,
--    locale and trailing slashes. Contacts' keys are recomputed: 68 change, exposing 5 more duplicate pairs
--    (encoded vs raw umlaut of one person), merged below by the same rules as 165.
create or replace function public.fn_url_percent_decode(p text)
returns text language plpgsql immutable parallel safe set search_path = pg_catalog as $$
declare r text;
begin
  if p is null or position('%' in p) = 0 then return p; end if;
  select string_agg(case when m.g[1] is not null then convert_from(decode(replace(m.g[1], '%', ''), 'hex'), 'UTF8') else m.g[2] end, '' order by m.n)
    into r
    from regexp_matches(p, '((?:%[0-9A-Fa-f]{2})+)|([^%]+|%)', 'g') with ordinality as m(g, n);
  return r;
exception when others then
  return p;                                   -- malformed encoding: keep the raw text rather than fail an ingest
end $$;

create or replace function public.fn_linkedin_url_key(p_url text)
returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           lower(public.fn_url_percent_decode(btrim(coalesce(p_url, '')))),
           '^https?://(www\.)?', ''),
           '[?#].*$', ''),
           '^(linkedin\.com/in/[^/?#]+)/[a-z]{2}(/|$)', '\1'),
           '[/?#]+$', ''), '')
$$;

update public.contacts set linkedin_url_key = public.fn_linkedin_url_key(linkedin_url)
 where linkedin_url_key is distinct from public.fn_linkedin_url_key(linkedin_url);

-- 0b. the Task 1 merge as a reusable function (same rules as 165: survivor = most outreach_log rows then oldest;
--     strictest consent carried; children repointed; loser archived with merged_into_contact_id; F17 open-draft rule).
--     Refuses (raises) if any colliding group disagrees on promise_of_quiet / is_blocked / do_not_contact / Do not contact
--     where the SURVIVOR would hold the weaker value, so a consent flag can never be lost silently.
create or replace function public.fn_merge_contact_duplicates(p_run_id text, p_phase text)
returns integer language plpgsql set search_path = public, pg_temp as $fn$
declare t record; v_n int; v_bad text;
begin
drop table if exists _f26_merge, _f26_carry, _f26_moved, _f26_sup;
-- 3. merge plan
create temp table _f26_merge on commit drop as
with oc as (select contact_id, count(*) n from public.outreach_log group by 1),
r as (
  select c.id, c.team_id, c.linkedin_url_key key, c.created_at, coalesce(oc.n, 0) n_ol,
         row_number() over (partition by c.team_id, c.linkedin_url_key order by c.archived_at is not null, coalesce(oc.n, 0) desc, c.created_at, c.id) rn,
         count(*) over (partition by c.team_id, c.linkedin_url_key) grp
    from public.contacts c left join oc on oc.contact_id = c.id
   where c.linkedin_url_key is not null and c.merged_into_contact_id is null
)
select s.id sid, l.id lid from r s join r l on l.team_id = s.team_id and l.key = s.key and l.rn > 1
 where s.rn = 1 and s.grp > 1;

-- 3a. carry flags and identity onto the survivor (aggregated over all losers of the group)
create temp table _f26_carry on commit drop as
select m.sid,
       bool_or(coalesce(l.promise_of_quiet, false)) q,
       string_agg(l.promise_of_quiet_note, ' | ') filter (where l.promise_of_quiet) q_note,
       bool_or(coalesce(l.is_blocked, false)) b, min(l.blocked_at) b_at,
       bool_or(coalesce(l.do_not_contact, false)) dnc,
       (array_agg(l.outreach_status order by l.created_at) filter (where l.outreach_status::text in ('Do not contact','Opted out')))[1] dnc_os,
       max(l.cooldown_until) cool, max(l.cr_blocked_until) crb,
       (array_agg(l.connection_status order by l.connection_status_at desc nulls last) filter (where l.connection_status::text in ('Accepted','Already connected')))[1] conn,
       (array_agg(l.contact_id) filter (where l.connection_status::text in ('Accepted','Already connected')))[1] conn_from,
       min(l.cr_accepted_at) acc_at,
       (array_agg(l.email) filter (where l.email is not null))[1] email,
       (array_agg(l.phone) filter (where l.phone is not null))[1] phone,
       (array_agg(l.linkedin_sales_nav_url) filter (where l.linkedin_sales_nav_url is not null))[1] sn_url,
       (array_agg(l.linkedin_slug) filter (where l.linkedin_slug is not null))[1] slug,
       (array_agg(l.linkedin_urn) filter (where l.linkedin_urn is not null))[1] urn,
       array_agg(l.contact_id order by l.contact_id) refs
  from _f26_merge m join public.contacts l on l.id = m.lid group by m.sid;

insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select p_run_id, p_phase, 'contacts', s.contact_id, 'carry_to_survivor', s.id,
       jsonb_strip_nulls(jsonb_build_object(
         'promise_of_quiet', case when cr.q and not coalesce(s.promise_of_quiet,false) then true end,
         'is_blocked', case when cr.b and not coalesce(s.is_blocked,false) then true end,
         'do_not_contact', case when cr.dnc and not coalesce(s.do_not_contact,false) then true end,
         'outreach_status', case when cr.dnc_os is not null and s.outreach_status::text not in ('Do not contact','Opted out') then jsonb_build_array(s.outreach_status::text, cr.dnc_os::text) end,
         'connection_status', case when cr.conn is not null and s.connection_status::text not in ('Accepted','Already connected') then jsonb_build_array(s.connection_status::text, cr.conn::text, cr.conn_from) end,
         'cooldown_until', case when cr.cool > coalesce(s.cooldown_until, '-infinity'::date) then cr.cool end,
         'cr_blocked_until', case when cr.crb > coalesce(s.cr_blocked_until, '-infinity'::date) then cr.crb end,
         'filled', nullif(concat_ws(',', case when s.email is null and cr.email is not null then 'email' end,
                                         case when s.phone is null and cr.phone is not null then 'phone' end,
                                         case when s.linkedin_sales_nav_url is null and cr.sn_url is not null then 'linkedin_sales_nav_url' end,
                                         case when s.linkedin_slug is null and cr.slug is not null then 'linkedin_slug' end,
                                         case when s.linkedin_urn is null and cr.urn is not null then 'linkedin_urn' end), '')))
  from _f26_carry cr join public.contacts s on s.id = cr.sid;

update public.contacts s set
  promise_of_quiet = coalesce(s.promise_of_quiet, false) or cr.q,
  promise_of_quiet_note = case when cr.q and not coalesce(s.promise_of_quiet, false) then cr.q_note else s.promise_of_quiet_note end,
  is_blocked = coalesce(s.is_blocked, false) or cr.b,
  blocked_at = coalesce(s.blocked_at, case when cr.b then cr.b_at end),
  do_not_contact = coalesce(s.do_not_contact, false) or cr.dnc,
  outreach_status = case when cr.dnc_os is not null and s.outreach_status::text not in ('Do not contact','Opted out') then cr.dnc_os else s.outreach_status end,
  cooldown_until = greatest(s.cooldown_until, cr.cool),
  cr_blocked_until = greatest(s.cr_blocked_until, cr.crb),
  connection_status = case when cr.conn is not null and s.connection_status::text not in ('Accepted','Already connected') then cr.conn else s.connection_status end,
  connection_status_source = case when cr.conn is not null and s.connection_status::text not in ('Accepted','Already connected') then 'f26_merge' else s.connection_status_source end,
  connection_status_evidence = case when cr.conn is not null and s.connection_status::text not in ('Accepted','Already connected') then 'carried from merged duplicate ' || cr.conn_from else s.connection_status_evidence end,
  cr_accepted_at = coalesce(s.cr_accepted_at, cr.acc_at),
  email = coalesce(s.email, cr.email),
  phone = coalesce(s.phone, cr.phone),
  linkedin_sales_nav_url = coalesce(s.linkedin_sales_nav_url, cr.sn_url),
  linkedin_slug = coalesce(s.linkedin_slug, cr.slug),
  linkedin_urn = coalesce(s.linkedin_urn, cr.urn),
  merged_from_refs = (select array_agg(distinct x order by x) from unnest(coalesce(s.merged_from_refs, '{}'::text[]) || cr.refs) x)
from _f26_carry cr where s.id = cr.sid;

-- 3b. repoint every child table at the survivor, logging counts per loser
create temp table _f26_moved (lid uuid, tbl text, n int) on commit drop;
for t in select * from (values ('outreach_log','contact_id'), ('refusals','contact_id'), ('draft_feedback','contact_id'),
      ('contact_guidance_notes','contact_id'), ('linkedin_threads','contact_id'), ('today_item_state','contact_id'),
      ('contact_profile_observations','contact_id'), ('review_queue','contact_id'), ('unmatched_replies','assigned_contact_id'),
      ('improvements','linked_contact_id'), ('contact_referrals','from_contact_id'), ('contact_referrals','sourced_contact_id')) v(tbl, col)
  loop
    execute format('insert into _f26_moved select m.lid, %L, count(*) from _f26_merge m join public.%I x on x.%I = m.lid group by m.lid', t.tbl || '.' || t.col, t.tbl, t.col);
    execute format('update public.%I x set %I = m.sid from _f26_merge m where x.%I = m.lid', t.tbl, t.col, t.col);
  end loop;

-- 3c. archive the losers (an already-archived loser keeps its original archived_at)
update public.contacts l set
  archived_at = coalesce(l.archived_at, now()),
  merged_into_contact_id = m.sid,
  archive_reason = concat_ws(' | ', l.archive_reason, format('F26 merge %s: duplicate of %s (same LinkedIn URL); history moved there', p_run_id, s.contact_id))
from _f26_merge m join public.contacts s on s.id = m.sid
where l.id = m.lid;

insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select p_run_id, p_phase, 'contacts', l.contact_id, 'merged_into', s.id,
       jsonb_build_object('survivor', s.contact_id, 'name', trim(coalesce(l.first_name,'') || ' ' || coalesce(l.last_name,'')),
                          'rows_repointed', coalesce((select jsonb_object_agg(tbl, n) from _f26_moved mv where mv.lid = m.lid and mv.n > 0), '{}'::jsonb),
                          'loser_connection_status', l.connection_status::text, 'loser_outreach_status', l.outreach_status::text)
  from _f26_merge m join public.contacts l on l.id = m.lid join public.contacts s on s.id = m.sid;

-- 3d. the F17 rule (fn_supersede_older_open_drafts) fires on INSERT only, so a merge can leave a survivor with two
--     open drafts of one touch type (6 people measured: two pending Initial messages each). Apply the same rule:
--     newest kept, older superseded, logged to touch_merge_log. pending_review only; an approved draft is never touched.
create temp table _f26_sup on commit drop as
select o.id, o.team_id, x.keep_id
  from public.outreach_log o
  join (select distinct sid from _f26_merge) m on m.sid = o.contact_id
  join lateral (select o2.id keep_id from public.outreach_log o2
                 where o2.contact_id = o.contact_id and o2.touch_type = o.touch_type
                   and o2.send_status::text in ('Draft','Ready') and o2.draft_status::text = 'pending_review'
                 order by o2.created_at desc, o2.id desc limit 1) x on x.keep_id <> o.id
 where o.send_status::text in ('Draft','Ready') and o.draft_status::text = 'pending_review';

insert into public.touch_merge_log (team_id, outreach_log_id, action, before, after, reason)
select o.team_id, o.id, 'superseded_by_newer_open_draft', to_jsonb(o), jsonb_build_object('draft_status','superseded','superseded_by', s.keep_id),
       p_phase || ': duplicate contacts merged; F17 one open draft per contact per touch type'
  from _f26_sup s join public.outreach_log o on o.id = s.id;

update public.outreach_log o set draft_status = 'superseded',
       rejection_feedback = jsonb_build_object('reason','superseded_by_newer_draft','detail',p_phase || ': this contact''s duplicate was merged and a newer open draft of the same touch type exists.','superseded_by', s.keep_id)
  from _f26_sup s where o.id = s.id;

select string_agg(s.contact_id, ', ') into v_bad
  from _f26_carry cr join public.contacts s on s.id = cr.sid
 where (cr.q and not s.promise_of_quiet) or (cr.b and not s.is_blocked) or (cr.dnc and not s.do_not_contact);
if v_bad is not null then raise exception 'fn_merge_contact_duplicates: consent carry failed on %', v_bad; end if;
select count(*) into v_n from _f26_merge;
return v_n;
end $fn$;
revoke execute on function public.fn_merge_contact_duplicates(text, text) from public, anon, authenticated;

select public.fn_merge_contact_duplicates('2026-10-05 (167 key decode)', 'f26_2_merge') as merged_after_key_decode;

-- 1. label parser
create or replace function public.fn_sent_label_min_age_days(p_label text)
returns integer language sql immutable parallel safe set search_path = pg_catalog as $$
  select case
    when l is null or l = '' then null
    when l ~ '(minute|hour|second)s? ago' or l ~ '\mjust now\M' or l ~ '\mtoday\M' then 0
    when l ~ '\myesterday\M' then 1
    when l ~ '(\d+) days? ago'   then (substring(l from '(\d+) days? ago'))::int
    when l ~ '(\d+) weeks? ago'  then (substring(l from '(\d+) weeks? ago'))::int * 7
    when l ~ '(\d+) months? ago' then (substring(l from '(\d+) months? ago'))::int * 30
    when l ~ '(\d+) years? ago'  then (substring(l from '(\d+) years? ago'))::int * 365
    when l ~ '\ma (day|week|month|year) ago' then case substring(l from '\ma (day|week|month|year) ago')
                                                   when 'day' then 1 when 'week' then 7 when 'month' then 30 else 365 end
    else null end
  from (select lower(btrim(p_label)) l) x
$$;
comment on function public.fn_sent_label_min_age_days(text) is
  'F26.2: LinkedIn relative label -> MINIMUM age in days (minutes/hours 0, yesterday 1, N days N, N weeks 7N, N months 30N). NULL when unparseable. Never derive a date from it.';

-- 2. contact columns
alter table public.contacts add column if not exists cr_pending_min_age_days integer;
alter table public.contacts add column if not exists cr_pending_label_at timestamptz;
comment on column public.contacts.cr_pending_min_age_days is
  'F26.2: minimum age in days of the pending invitation, parsed from the extractor label at cr_pending_label_at. Age today = this + days since cr_pending_label_at. NULL = not pending, or label unparseable.';
comment on column public.contacts.cr_pending_label_at is
  'F26.2: when the extractor read the label behind cr_pending_min_age_days (the row timestamp).';

-- 3. extractor runs and rows (the daily counter in Task 5 reads these, not our own queue)
create table if not exists public.cr_extractor_runs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  received_at timestamptz not null default now(),
  extracted_at timestamptz,
  source text not null default 'ingest-sent-requests',
  row_count integer not null default 0,
  matched integer not null default 0,
  unmatched integer not null default 0,
  set_request_sent integer not null default 0,
  demoted integer not null default 0,
  absent_sweep text not null default 'applied' check (absent_sweep in ('applied','skipped_guard','skipped_empty')),
  conflicts integer not null default 0,
  summary jsonb
);
create table if not exists public.cr_extractor_rows (
  id bigint generated always as identity primary key,
  run_id uuid not null references public.cr_extractor_runs(id) on delete cascade,
  team_id uuid not null,
  profile_url text not null,
  url_key text not null,
  contact_id uuid references public.contacts(id),
  sent_label text,
  min_age_days integer,
  row_timestamp timestamptz,
  raw jsonb
);
create index if not exists cr_extractor_rows_run_idx on public.cr_extractor_rows (run_id);
create index if not exists cr_extractor_rows_contact_idx on public.cr_extractor_rows (contact_id);

-- 4. pending invitations with no contact row (Oliver creates the contact from the Reconciliation tab)
create table if not exists public.unmatched_sent_requests (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id),
  url_key text not null,
  profile_url text not null,
  sent_label text,
  min_age_days integer,
  label_at timestamptz,
  raw jsonb,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  last_run_id uuid references public.cr_extractor_runs(id),
  still_pending boolean not null default true,
  resolved_contact_id uuid references public.contacts(id),
  resolved_at timestamptz,
  unique (team_id, url_key)
);

-- 5. every status change this path makes, with the evidence (the Reconciliation tab's "what changed and why")
create table if not exists public.connection_status_changes (
  id bigint generated always as identity primary key,
  team_id uuid not null,
  run_id uuid references public.cr_extractor_runs(id),
  contact_id uuid not null references public.contacts(id),
  old_status text,
  new_status text not null,
  source text not null,
  evidence text,
  changed_at timestamptz not null default now()
);
create index if not exists connection_status_changes_contact_idx on public.connection_status_changes (contact_id, changed_at desc);

alter table public.cr_extractor_runs enable row level security;
alter table public.cr_extractor_rows enable row level security;
alter table public.unmatched_sent_requests enable row level security;
alter table public.connection_status_changes enable row level security;
do $p$ declare t text; begin
  foreach t in array array['cr_extractor_runs','cr_extractor_rows','unmatched_sent_requests','connection_status_changes'] loop
    execute format('drop policy if exists %I on public.%I', t || '_team_read', t);
    execute format('create policy %I on public.%I for select to authenticated using (team_id in (select public.fn_user_teams()))', t || '_team_read', t);
  end loop;
end $p$;
-- Oliver resolves an unmatched row (links the contact he created). Nothing else is client-writable.
drop policy if exists unmatched_sent_requests_team_update on public.unmatched_sent_requests;
create policy unmatched_sent_requests_team_update on public.unmatched_sent_requests for update to authenticated
  using (team_id in (select public.fn_user_teams())) with check (team_id in (select public.fn_user_teams()));
revoke insert, delete on public.unmatched_sent_requests from anon, authenticated;
revoke insert, update, delete on public.cr_extractor_runs, public.cr_extractor_rows, public.connection_status_changes from anon, authenticated;
revoke all on public.cr_extractor_runs, public.cr_extractor_rows, public.unmatched_sent_requests, public.connection_status_changes from anon;

-- 5b. fn_contacts_degree_guard (138) refuses Request sent without connection_level, so nobody records a CR we sent
--     without knowing the degree. The extractor is not us sending: it is LinkedIn reporting an invitation as pending,
--     and refusing it leaves connection_status wrong (measured: P425, P732, P747, P364 have no degree and are pending).
--     The extractor path alone may record the fact without a degree; every other path is still refused.
create or replace function public.fn_contacts_degree_guard()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if new.connection_level::text = 'Not connected'
     and (tg_op = 'INSERT' or new.connection_level is distinct from old.connection_level) then
    raise exception 'connection_level holds network distance (1st/2nd/3rd degree, Out of network). "Not connected" is an invitation state and belongs in connection_status (contact %).',
      coalesce(new.contact_id, new.id::text) using errcode = 'check_violation';
  end if;
  if new.connection_status::text in ('Accepted','Already connected') and new.connection_level is null then
    new.connection_level := '1st degree';
  end if;
  if new.connection_status::text = 'Request sent' and new.connection_level is null
     and coalesce(new.connection_status_source, '') <> 'sent_request_extractor'   -- 167: LinkedIn-observed fact
     and (tg_op = 'INSERT' or new.connection_status is distinct from old.connection_status or new.connection_level is distinct from old.connection_level) then
    raise exception 'connection_level is required when connection_status is Request sent (contact %). Source the degree from Sales Nav before recording the request.', coalesce(new.contact_id, new.id::text) using errcode = 'check_violation';
  end if;
  return new;
end $function$;

-- 6. the ingest
create or replace function public.fn_ingest_sent_requests(p_team_id uuid, p_rows jsonb, p_dry_run boolean default false, p_force_sweep boolean default false)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare
  v_run uuid; v_extracted timestamptz; v_rows int; v_matched int; v_unmatched int; v_set int := 0; v_demote int := 0;
  v_rs_before int; v_would_demote int; v_sweep text := 'applied'; v_conflicts int; v_first jsonb; v_summary jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_ingest_sent_requests: p_rows must be a JSON array of extractor rows';
  end if;

  drop table if exists _sr, _m, _chg, _abs;
  create temp table _sr on commit drop as
  select distinct on (k) k url_key, r->>'profileUrl' profile_url, nullif(btrim(r->>'sentDate'), '') sent_label,
         public.fn_sent_label_min_age_days(r->>'sentDate') min_age,
         coalesce(nullif(r->>'timestamp','')::timestamptz, now()) ts, r raw
    from jsonb_array_elements(p_rows) r
    cross join lateral (select public.fn_linkedin_url_key(r->>'profileUrl') k) kk
   where k is not null and k ~ '^linkedin\.com/in/'          -- drops the invitation-manager junk row
   order by k, coalesce(nullif(r->>'timestamp','')::timestamptz, now()) desc;

  select count(*), min(ts) into v_rows, v_extracted from _sr;

  insert into public.cr_extractor_runs (team_id, extracted_at, row_count)
  values (p_team_id, v_extracted, v_rows) returning id into v_run;

  create temp table _m on commit drop as
  select s.*, c.id contact_id, c.connection_status::text old_status
    from _sr s left join public.contacts c
      on c.team_id = p_team_id and c.linkedin_url_key = s.url_key and c.archived_at is null;

  insert into public.cr_extractor_rows (run_id, team_id, profile_url, url_key, contact_id, sent_label, min_age_days, row_timestamp, raw)
  select v_run, p_team_id, profile_url, url_key, contact_id, sent_label, min_age, ts, raw from _m;

  select count(*) filter (where contact_id is not null), count(*) filter (where contact_id is null),
         count(*) filter (where old_status in ('Accepted','Already connected'))
    into v_matched, v_unmatched, v_conflicts from _m;

  -- matched: pending on LinkedIn. Accepted / Already connected are never downgraded by this path; they are
  -- counted as conflicts for a human to look at.
  create temp table _chg (contact_id uuid, old_status text, new_status text, source text, evidence text) on commit drop;
  insert into _chg
  select contact_id, old_status, 'Request sent', 'sent_request_extractor', sent_label
    from _m where contact_id is not null and old_status not in ('Accepted','Already connected') and old_status <> 'Request sent';

  update public.contacts c set
    connection_status = 'Request sent',
    connection_status_source = 'sent_request_extractor',
    connection_status_evidence = m.sent_label,
    cr_pending_min_age_days = m.min_age,
    cr_pending_label_at = m.ts
  from _m m
  where c.id = m.contact_id and m.old_status not in ('Accepted','Already connected');
  get diagnostics v_set = row_count;

  -- absent: Request sent here but not pending on LinkedIn. Only a status we set BEFORE the extraction can be
  -- judged by it; a request logged after the extractor ran cannot be in its list.
  select count(*) into v_rs_before from public.contacts where team_id = p_team_id and archived_at is null and connection_status::text = 'Request sent';
  create temp table _abs on commit drop as
  select c.id contact_id
    from public.contacts c
   where c.team_id = p_team_id and c.archived_at is null and c.connection_status::text = 'Request sent'
     and not exists (select 1 from _m where _m.contact_id = c.id)
     and (c.connection_status_at is null or c.connection_status_at < v_extracted)
     and not exists (select 1 from public.outreach_log o where o.contact_id = c.id and o.touch_type::text = 'Connection request'
                      and o.send_status::text = 'Sent'
                      and coalesce(o.sent_at_actual, o.touch_date::timestamptz + interval '1 day' - interval '1 second', o.updated_at) >= v_extracted);
  select count(*) into v_would_demote from _abs;

  if v_rows = 0 then
    v_sweep := 'skipped_empty';           -- an empty or failed run never clears the field
  elsif v_would_demote > greatest(10, (v_rs_before * 0.6)::int) and not p_force_sweep then
    v_sweep := 'skipped_guard';           -- a truncated run would otherwise wipe real pending invitations
  else
    insert into _chg
    select a.contact_id, 'Request sent', 'Not connected', 'sent_request_extractor_absent',
           format('absent from the LinkedIn pending list read at %s', to_char(v_extracted at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"'))
      from _abs a;
    update public.contacts c set
      connection_status = 'Not connected',
      connection_status_source = 'sent_request_extractor_absent',
      connection_status_evidence = format('absent from the LinkedIn pending list read at %s', to_char(v_extracted at time zone 'UTC', 'YYYY-MM-DD HH24:MI "UTC"')),
      cr_pending_min_age_days = null,
      cr_pending_label_at = null
    from _abs a where c.id = a.contact_id;
    get diagnostics v_demote = row_count;
  end if;

  insert into public.connection_status_changes (team_id, run_id, contact_id, old_status, new_status, source, evidence)
  select p_team_id, v_run, contact_id, old_status, new_status, source, evidence from _chg;

  -- unmatched
  insert into public.unmatched_sent_requests as u (team_id, url_key, profile_url, sent_label, min_age_days, label_at, raw, last_run_id)
  select p_team_id, url_key, profile_url, sent_label, min_age, ts, raw, v_run from _m where contact_id is null
  on conflict (team_id, url_key) do update set
    profile_url = excluded.profile_url, sent_label = excluded.sent_label, min_age_days = excluded.min_age_days,
    label_at = excluded.label_at, raw = excluded.raw, last_seen_at = now(), last_run_id = excluded.last_run_id, still_pending = true;
  if v_rows > 0 then
    update public.unmatched_sent_requests u set still_pending = false
     where u.team_id = p_team_id and u.still_pending and u.last_run_id is distinct from v_run;
  end if;

  select coalesce(jsonb_agg(x), '[]'::jsonb) into v_first from (
    select c.contact_id ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) name, g.old_status, g.new_status, g.evidence
      from _chg g join public.contacts c on c.id = g.contact_id
     order by g.new_status desc, c.contact_id limit 20) x;

  v_summary := jsonb_build_object('run_id', v_run, 'dry_run', p_dry_run, 'extracted_at', v_extracted, 'rows', v_rows,
    'matched', v_matched, 'unmatched', v_unmatched, 'set_request_sent', (select count(*) from _chg where new_status = 'Request sent'),
    'refreshed_age_only', v_set - (select count(*) from _chg where new_status = 'Request sent'),
    'request_sent_before', v_rs_before, 'absent_candidates', v_would_demote, 'demoted', v_demote, 'absent_sweep', v_sweep,
    'conflicts_accepted_but_pending', v_conflicts, 'unparseable_labels', (select count(*) from _m where min_age is null),
    'first_20_changes', v_first);

  update public.cr_extractor_runs set matched = v_matched, unmatched = v_unmatched,
         set_request_sent = (select count(*) from _chg where new_status = 'Request sent'), demoted = v_demote,
         absent_sweep = v_sweep, conflicts = v_conflicts, summary = v_summary
   where id = v_run;

  if p_dry_run then
    raise exception using errcode = 'P0001', message = 'DRY_RUN_ROLLBACK', detail = v_summary::text;
  end if;
  return v_summary;
end $$;
revoke execute on function public.fn_ingest_sent_requests(uuid, jsonb, boolean, boolean) from public, anon, authenticated;
comment on function public.fn_ingest_sent_requests(uuid, jsonb, boolean, boolean) is
  'F26.2: one extractor run in, whole array. Matched -> Request sent + label + min age; absent Request sent -> Not connected (never Accepted / Already connected; never a status set after the extraction; skipped if it would demote >60% of Request sent unless p_force_sweep); unmatched -> unmatched_sent_requests. p_dry_run raises DRY_RUN_ROLLBACK with the summary in DETAIL so nothing persists.';
