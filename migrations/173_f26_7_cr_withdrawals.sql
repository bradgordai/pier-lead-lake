-- 173 F26 Task 7: the withdrawal engine. Built, NOT run. Brad launches PhantomBuster 6265338156423893 himself.
--
-- Age today = cr_pending_min_age_days (minimum age at extraction, from the label) + whole days since
-- cr_pending_label_at. Never a derived date. Due at 14 or more ("2 weeks ago" qualifies, "1 week ago" does not).
--
-- v_cr_withdrawal_due              pending (Request sent) with a derivable age >= 14, oldest first. Only these may be
--                                   withdrawn automatically.
-- v_cr_withdrawal_unknown_age      Request sent with no derivable age (no extractor label yet): the Reconciliation
--                                   tab, with a batch action, never automatic.
-- v_cr_withdrawal_next_launch      how many the next withdrawer launch may take: 20 on the first automatic run
--                                   (no confirmed withdrawal ingested yet), never more than 50 (PhantomBuster's cap).
-- fn_ingest_cr_withdrawals         the withdrawer's CONFIRMED output {linkedinProfile, name, title, invitationDate,
--                                   timestamp}: Withdrawn, connection_status_at, the invitationDate label as evidence,
--                                   cr_blocked_until = current_date + 180. Accepted / Already connected never touched.
-- fn_mark_cr_withdrawn             the Reconciliation tab's batch action: Oliver confirms he withdrew these on LinkedIn.

create or replace view public.v_cr_withdrawal_due with (security_invoker = true) as
select c.team_id, c.id as contact_id, c.contact_id as contact_ref,
       trim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')) as contact_name,
       co.company_name, c.linkedin_url, c.connection_status::text as connection_status,
       c.connection_status_evidence as pending_label, c.cr_pending_min_age_days as min_age_at_read, c.cr_pending_label_at as label_read_at,
       c.cr_pending_min_age_days + greatest(0, current_date - (c.cr_pending_label_at at time zone 'UTC')::date) as min_age_days_today
  from public.contacts c
  left join public.companies co on co.id = c.company_id
 where c.archived_at is null
   and c.connection_status::text = 'Request sent'
   and c.cr_pending_min_age_days is not null and c.cr_pending_label_at is not null
   and c.cr_pending_min_age_days + greatest(0, current_date - (c.cr_pending_label_at at time zone 'UTC')::date) >= 14;
comment on view public.v_cr_withdrawal_due is
  'F26.7: pending invitations whose minimum age (label + days since read) is 14 or more. Only Request sent rows; Accepted / Already connected can never appear. Order by min_age_days_today desc for oldest first.';
grant select on public.v_cr_withdrawal_due to authenticated;
revoke all on public.v_cr_withdrawal_due from anon;

create or replace view public.v_cr_withdrawal_unknown_age with (security_invoker = true) as
select c.team_id, c.id as contact_id, c.contact_id as contact_ref,
       trim(coalesce(c.first_name, '') || ' ' || coalesce(c.last_name, '')) as contact_name,
       co.company_name, c.linkedin_url, c.connection_status_source, c.connection_status_at, c.connection_status_evidence
  from public.contacts c
  left join public.companies co on co.id = c.company_id
 where c.archived_at is null
   and c.connection_status::text = 'Request sent'
   and (c.cr_pending_min_age_days is null or c.cr_pending_label_at is null);
comment on view public.v_cr_withdrawal_unknown_age is
  'F26.7: Request sent with no derivable age. Never withdrawn automatically; shown on the Reconciliation tab for a human batch action.';
grant select on public.v_cr_withdrawal_unknown_age to authenticated;
revoke all on public.v_cr_withdrawal_unknown_age from anon;

create or replace view public.v_cr_withdrawal_next_launch with (security_invoker = true) as
select t.id as team_id,
       (select count(*) from public.v_cr_withdrawal_due d where d.team_id = t.id) as due,
       exists (select 1 from public.connection_status_changes g where g.team_id = t.id and g.source = 'auto_invitation_withdrawer') as has_run_before,
       least((select count(*) from public.v_cr_withdrawal_due d where d.team_id = t.id),
             case when exists (select 1 from public.connection_status_changes g where g.team_id = t.id and g.source = 'auto_invitation_withdrawer')
                  then 50 else 20 end)::int as next_launch_size
  from public.teams t;
grant select on public.v_cr_withdrawal_next_launch to authenticated;
revoke all on public.v_cr_withdrawal_next_launch from anon;

-- Confirmed withdrawals from the withdrawer's output. One call per run, whole array.
create or replace function public.fn_ingest_cr_withdrawals(p_team_id uuid, p_rows jsonb)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare v_n int := 0; v_unmatched jsonb; v_skipped jsonb;
begin
  if jsonb_typeof(p_rows) is distinct from 'array' then
    raise exception 'fn_ingest_cr_withdrawals: p_rows must be a JSON array of withdrawer rows';
  end if;
  drop table if exists _wd;
  create temp table _wd on commit drop as
  select distinct on (k) k url_key, r->>'linkedinProfile' profile_url, nullif(btrim(r->>'invitationDate'), '') label, r raw, c.id contact_id,
         c.connection_status::text old_status
    from jsonb_array_elements(p_rows) r
    cross join lateral (select public.fn_linkedin_url_key(r->>'linkedinProfile') k) kk
    left join public.contacts c on c.team_id = p_team_id and c.linkedin_url_key = kk.k and c.archived_at is null
   where k is not null and k ~ '^linkedin\.com/in/';

  insert into public.connection_status_changes (team_id, contact_id, old_status, new_status, source, evidence)
  select p_team_id, contact_id, old_status, 'Withdrawn', 'auto_invitation_withdrawer', coalesce(label, 'withdrawn by Auto Invitation Withdrawer')
    from _wd where contact_id is not null and old_status not in ('Accepted', 'Already connected');

  update public.contacts c set
    connection_status = 'Withdrawn',
    connection_status_source = 'auto_invitation_withdrawer',
    connection_status_evidence = coalesce(w.label, 'withdrawn by Auto Invitation Withdrawer'),
    connection_status_at = now(),
    cr_blocked_until = current_date + 180,
    cr_pending_min_age_days = null,
    cr_pending_label_at = null
  from _wd w
  where c.id = w.contact_id and w.old_status not in ('Accepted', 'Already connected');
  get diagnostics v_n = row_count;

  select coalesce(jsonb_agg(profile_url), '[]') into v_unmatched from _wd where contact_id is null;
  select coalesce(jsonb_agg(jsonb_build_object('contact_id', contact_id, 'status', old_status)), '[]') into v_skipped
    from _wd where contact_id is not null and old_status in ('Accepted', 'Already connected');
  return jsonb_build_object('rows', (select count(*) from _wd), 'withdrawn', v_n, 'unmatched', v_unmatched, 'skipped_connected', v_skipped);
end $$;
revoke execute on function public.fn_ingest_cr_withdrawals(uuid, jsonb) from public, anon, authenticated;

-- The Reconciliation tab's batch action: Oliver confirms these invitations were withdrawn on LinkedIn.
create or replace function public.fn_mark_cr_withdrawn(p_team uuid, p_contact_ids uuid[])
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  if auth.uid() is null or p_team not in (select public.fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if coalesce(array_length(p_contact_ids, 1), 0) > 50 then raise exception 'at most 50 contacts per batch'; end if;
  insert into public.connection_status_changes (team_id, contact_id, old_status, new_status, source, evidence)
  select p_team, c.id, c.connection_status::text, 'Withdrawn', 'reconciliation_manual', 'marked withdrawn on the Reconciliation tab'
    from public.contacts c
   where c.team_id = p_team and c.id = any(p_contact_ids) and c.connection_status::text = 'Request sent';
  update public.contacts c set
    connection_status = 'Withdrawn', connection_status_source = 'reconciliation_manual',
    connection_status_evidence = 'marked withdrawn on the Reconciliation tab', connection_status_at = now(),
    cr_blocked_until = current_date + 180, cr_pending_min_age_days = null, cr_pending_label_at = null
   where c.team_id = p_team and c.id = any(p_contact_ids) and c.connection_status::text = 'Request sent';
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke execute on function public.fn_mark_cr_withdrawn(uuid, uuid[]) from public, anon;
grant execute on function public.fn_mark_cr_withdrawn(uuid, uuid[]) to authenticated;
