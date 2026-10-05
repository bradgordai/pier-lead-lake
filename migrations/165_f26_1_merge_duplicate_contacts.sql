-- 165 F26 Task 1: normalised LinkedIn URL key, duplicate guard on it, merge the colliding groups.
-- Nothing is deleted. Losers are archived with merged_into_contact_id + archive_reason naming the survivor.
-- Survivor = most outreach_log rows, then oldest created_at (then id, for determinism).
-- Consent and fact flags are carried onto the survivor, strictest wins:
--   promise_of_quiet, is_blocked, do_not_contact, outreach_status Do not contact / Opted out,
--   cooldown_until and cr_blocked_until (latest), connection_status Accepted / Already connected
--   (a fact the sent-request extractor cannot see, so dropping it would let Task 2 overwrite it).
-- Identity fields the survivor lacks (email, phone, Sales Nav URL, slug, URN) are filled from the loser.
-- Every merge is logged to migration_audit phase f26_1.

-- 1. key function + maintained column (a trigger, not GENERATED: a client that writes back a whole
--    row object would be refused by a generated column; here any written value is simply overwritten)
create or replace function public.fn_linkedin_url_key(p_url text)
returns text language sql immutable parallel safe set search_path = pg_catalog as $$
  select nullif(lower(regexp_replace(regexp_replace(coalesce(p_url, ''), '^https?://(www\.)?', ''), '/+$', '')), '')
$$;

alter table public.contacts add column if not exists linkedin_url_key text;
alter table public.contacts add column if not exists merged_into_contact_id uuid references public.contacts(id);
comment on column public.contacts.linkedin_url_key is
  'F26.1: lower(linkedin_url) without scheme, www. and trailing slash. Maintained by trg_contacts_url_key; the match key for duplicates and for the sent-request extractor.';
comment on column public.contacts.merged_into_contact_id is
  'F26.1: set on a merge loser (archived) to the survivor contact uuid. A merge loser never re-enters any queue.';

create or replace function public.fn_contacts_url_key()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.linkedin_url_key := public.fn_linkedin_url_key(new.linkedin_url);
  return new;
end $$;
revoke execute on function public.fn_contacts_url_key() from public, anon, authenticated;

drop trigger if exists trg_contacts_url_key on public.contacts;
create trigger trg_contacts_url_key before insert or update on public.contacts
  for each row execute function public.fn_contacts_url_key();

update public.contacts set linkedin_url_key = public.fn_linkedin_url_key(linkedin_url)
 where linkedin_url_key is distinct from public.fn_linkedin_url_key(linkedin_url);

create index if not exists contacts_team_linkedin_url_key_idx on public.contacts (team_id, linkedin_url_key)
  where linkedin_url_key is not null;

-- 2. guard: URL-key rung first; also guards an UPDATE that changes linkedin_url onto another live contact's key
create or replace function public.fn_contact_duplicate_guard()
 returns trigger
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
declare hit record; why text; k text := public.fn_contact_name_key(new.first_name, new.last_name);
        uk text := public.fn_linkedin_url_key(new.linkedin_url);
begin
  -- 155: initialise the record, else the name rung reads hit.id on an unassigned record (SQLSTATE 55000)
  select null::uuid as id, null::text as ref, null::text as nm, null::timestamptz as archived_at into hit;
  if tg_op = 'UPDATE' then
    -- 165: only a changed URL key is checked on update, and only against other LIVE contacts
    -- (a merge loser keeps its URL; the survivor must stay editable).
    if uk is not null and uk is distinct from public.fn_linkedin_url_key(old.linkedin_url) then
      select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
        into hit from public.contacts c
       where c.team_id = new.team_id and c.linkedin_url_key = uk and c.id <> new.id and c.archived_at is null
       order by c.created_at limit 1;
      why := 'LinkedIn URL';
    end if;
  else
    -- 165: normalised URL (scheme, www., trailing slash, case) before slug and name
    if uk is not null then
      select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
        into hit from public.contacts c
       where c.team_id = new.team_id and c.linkedin_url_key = uk
       order by c.archived_at nulls first, c.created_at limit 1;
      why := 'LinkedIn URL';
    end if;
    if hit.id is null and nullif(btrim(new.linkedin_slug), '') is not null then
      select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
        into hit from public.contacts c
       where c.team_id = new.team_id and c.linkedin_slug = new.linkedin_slug
       order by c.archived_at nulls first, c.created_at limit 1;
      why := 'LinkedIn slug';
    end if;
    if hit.id is null and k is not null and new.company_id is not null then
      select c.id, c.contact_id as ref, trim(coalesce(c.first_name,'') || ' ' || coalesce(c.last_name,'')) as nm, c.archived_at
        into hit from public.contacts c
       where c.team_id = new.team_id and c.company_id = new.company_id
         and public.fn_contact_name_key(c.first_name, c.last_name) = k
       order by c.archived_at nulls first, c.created_at limit 1;
      why := 'name at the same company';
    end if;
  end if;
  if hit.id is not null then
    raise exception using errcode = '23505',
      message = format('duplicate_contact: "%s %s" matches existing %s %s%s by %s. Use the existing contact instead of creating a second.',
                       coalesce(new.first_name, ''), coalesce(new.last_name, ''), hit.ref, hit.nm,
                       case when hit.archived_at is not null then ' (archived)' else '' end, why),
      detail = format('existing_contact_uuid=%s', hit.id);
  end if;
  return new;
end $function$;

drop trigger if exists trg_contact_duplicate_guard on public.contacts;
create trigger trg_contact_duplicate_guard before insert or update of linkedin_url on public.contacts
  for each row execute function public.fn_contact_duplicate_guard();

-- 3. merge plan
create temp table _f26_merge on commit drop as
with oc as (select contact_id, count(*) n from public.outreach_log group by 1),
r as (
  select c.id, c.team_id, c.linkedin_url_key key, c.created_at, coalesce(oc.n, 0) n_ol,
         row_number() over (partition by c.team_id, c.linkedin_url_key order by coalesce(oc.n, 0) desc, c.created_at, c.id) rn,
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
select 'f26_1_2026-10-05', 'f26_1', 'contacts', s.contact_id, 'carry_to_survivor', s.id,
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
do $repoint$
declare t record; n int;
begin
  for t in select * from (values ('outreach_log','contact_id'), ('refusals','contact_id'), ('draft_feedback','contact_id'),
      ('contact_guidance_notes','contact_id'), ('linkedin_threads','contact_id'), ('today_item_state','contact_id'),
      ('contact_profile_observations','contact_id'), ('review_queue','contact_id'), ('unmatched_replies','assigned_contact_id'),
      ('improvements','linked_contact_id'), ('contact_referrals','from_contact_id'), ('contact_referrals','sourced_contact_id')) v(tbl, col)
  loop
    execute format('insert into _f26_moved select m.lid, %L, count(*) from _f26_merge m join public.%I x on x.%I = m.lid group by m.lid', t.tbl || '.' || t.col, t.tbl, t.col);
    execute format('update public.%I x set %I = m.sid from _f26_merge m where x.%I = m.lid', t.tbl, t.col, t.col);
  end loop;
end $repoint$;

-- 3c. archive the losers (an already-archived loser keeps its original archived_at)
update public.contacts l set
  archived_at = coalesce(l.archived_at, now()),
  merged_into_contact_id = m.sid,
  archive_reason = concat_ws(' | ', l.archive_reason, format('F26 merge 2026-10-05: duplicate of %s (same LinkedIn URL); history moved there', s.contact_id))
from _f26_merge m join public.contacts s on s.id = m.sid
where l.id = m.lid;

insert into public.migration_audit (run_id, phase, entity, source_ref, action, target_id, detail)
select 'f26_1_2026-10-05', 'f26_1', 'contacts', l.contact_id, 'merged_into', s.id,
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
       'F26.1: duplicate contacts merged; F17 one open draft per contact per touch type'
  from _f26_sup s join public.outreach_log o on o.id = s.id;

update public.outreach_log o set draft_status = 'superseded',
       rejection_feedback = jsonb_build_object('reason','superseded_by_newer_draft','detail','F26.1: this contact''s duplicate was merged and a newer open draft of the same touch type exists.','superseded_by', s.keep_id)
  from _f26_sup s where o.id = s.id;
