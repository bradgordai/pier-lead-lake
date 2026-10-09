-- 178 F27A: admin write access for Cowork and Claude Code on three guarded SECURITY DEFINER functions.
--
-- The Supabase MCP connects as session_user = 'postgres' with no JWT (measured 9 Oct: auth.uid() null,
-- auth.role() null, current_user postgres, session_user postgres, claims null). Every PostgREST caller (anon,
-- authenticated, service_role via the API) logs in as 'authenticator', and SECURITY DEFINER changes current_user,
-- never session_user. Admin predicate (approved by Brad 9 Oct):
--     session_user = 'postgres'  OR  auth.role() = 'service_role'
-- Neither half depends on a null uid; both already imply full database access by other means.
--
-- Behaviour:
--   * signed-in caller: unchanged. p_reason is ignored; the original membership guard runs exactly as before.
--   * admin caller: p_team must be a real team; p_reason must be non-blank, else RAISE; one audit_log row
--     (source 'mcp_admin', actor_user_id null, reason in summary, real before/after values, and which half of the
--     predicate matched with session_user and auth.role() recorded in after_value.caller).
--   * anyone else: refused exactly as before.
-- fn_cr_queue_populate is deliberately NOT touched (it already works from the MCP; Brad, 9 Oct).
-- fn_set_cr_dispatch_enabled is deliberately NOT touched.
--
-- Mechanics: adding a parameter needs DROP + CREATE. Plain DROP (never CASCADE; nothing depends on these three,
-- measured). Owner postgres, SECURITY DEFINER and search_path = public, pg_temp are restated verbatim. Default
-- privileges in public grant anon EXECUTE, so each function gets REVOKE ALL FROM PUBLIC, anon and explicit grants.
-- All in one transaction (one apply). PostgREST schema cache reloaded at the end.
-- Bodies: captured with pg_get_functiondef on 9 Oct before this file was written; the only changes are the new
-- parameter, the admin branch and the audit row.

drop function public.fn_mark_cr_withdrawn(uuid, uuid[]);
drop function public.fn_set_auto_score_new_companies(uuid, boolean);
drop function public.fn_set_inmail_credits(uuid, integer, integer);

-- ---------------------------------------------------------------------------------------------------------------
create function public.fn_mark_cr_withdrawn(p_team uuid, p_contact_ids uuid[], p_reason text default null)
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_n int; v_admin text; v_before jsonb;
begin
  -- F27A: admin path (MCP as postgres, or service_role). Signed-in callers fall through to the original guard.
  v_admin := case when session_user = 'postgres' then 'session_user'
                  when coalesce(auth.role(), '') = 'service_role' then 'service_role' end;
  if v_admin is not null then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then
      raise exception 'admin call (%) needs a non-blank p_reason', v_admin;
    end if;
    if not exists (select 1 from public.teams where id = p_team) then raise exception 'no such team %', p_team; end if;
  elsif auth.uid() is null or p_team not in (select public.fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if coalesce(array_length(p_contact_ids, 1), 0) > 50 then raise exception 'at most 50 contacts per batch'; end if;
  if v_admin is not null then
    select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'contact_id', c.contact_id, 'connection_status', c.connection_status,
                    'cr_blocked_until', c.cr_blocked_until, 'cr_pending_min_age_days', c.cr_pending_min_age_days,
                    'cr_pending_label_at', c.cr_pending_label_at) order by c.contact_id), '[]'::jsonb)
      into v_before
      from public.contacts c
     where c.team_id = p_team and c.id = any(p_contact_ids) and c.connection_status::text = 'Request sent';
  end if;
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
  if v_admin is not null then
    insert into public.audit_log (team_id, actor_user_id, entity_type, entity_id, action, before_value, after_value, summary, source)
    select p_team, null, 'contacts', null, 'admin_mark_cr_withdrawn',
           jsonb_build_object('contacts', v_before),
           jsonb_build_object('withdrawn', v_n,
             'contacts', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'contact_id', c.contact_id, 'connection_status', c.connection_status,
                            'cr_blocked_until', c.cr_blocked_until, 'cr_pending_min_age_days', c.cr_pending_min_age_days,
                            'cr_pending_label_at', c.cr_pending_label_at) order by c.contact_id)
                          from public.contacts c where c.id in (select (e->>'id')::uuid from jsonb_array_elements(v_before) e)), '[]'::jsonb),
             'requested_ids', to_jsonb(p_contact_ids),
             'caller', jsonb_build_object('matched', v_admin, 'session_user', session_user::text, 'auth_role', auth.role())),
           btrim(p_reason), 'mcp_admin';
  end if;
  return v_n;
end $function$;
alter function public.fn_mark_cr_withdrawn(uuid, uuid[], text) owner to postgres;

-- ---------------------------------------------------------------------------------------------------------------
create function public.fn_set_auto_score_new_companies(p_team uuid, p_on boolean, p_reason text default null)
 returns boolean
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_admin text; v_before boolean;
begin
  -- F27A: admin path (MCP as postgres, or service_role). Signed-in callers fall through to the original guard.
  v_admin := case when session_user = 'postgres' then 'session_user'
                  when coalesce(auth.role(), '') = 'service_role' then 'service_role' end;
  if v_admin is not null then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then
      raise exception 'admin call (%) needs a non-blank p_reason', v_admin;
    end if;
    if not exists (select 1 from public.teams where id = p_team) then raise exception 'no such team %', p_team; end if;
  elsif auth.uid() is null or p_team not in (select fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if p_on is null then raise exception 'p_on must be true or false'; end if;
  select auto_score_new_companies into v_before from public.team_settings where team_id = p_team;
  update public.team_settings set auto_score_new_companies = p_on, updated_at = now() where team_id = p_team;
  if not found then raise exception 'no settings row for team %', p_team; end if;
  if v_admin is not null then
    insert into public.audit_log (team_id, actor_user_id, entity_type, entity_id, action, before_value, after_value, summary, source)
    values (p_team, null, 'team_settings', p_team, 'admin_set_auto_score_new_companies',
            jsonb_build_object('auto_score_new_companies', v_before),
            jsonb_build_object('auto_score_new_companies', p_on,
              'caller', jsonb_build_object('matched', v_admin, 'session_user', session_user::text, 'auth_role', auth.role())),
            btrim(p_reason), 'mcp_admin');
  end if;
  return p_on;
end $function$;
alter function public.fn_set_auto_score_new_companies(uuid, boolean, text) owner to postgres;

-- ---------------------------------------------------------------------------------------------------------------
create function public.fn_set_inmail_credits(p_team uuid, p_balance integer, p_low_at integer default null::integer, p_reason text default null)
 returns v_inmail_credits
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r public.v_inmail_credits; v_admin text; v_before jsonb;
begin
  -- F27A: admin path (MCP as postgres, or service_role). Signed-in callers fall through to the original guard.
  v_admin := case when session_user = 'postgres' then 'session_user'
                  when coalesce(auth.role(), '') = 'service_role' then 'service_role' end;
  if v_admin is not null then
    if nullif(btrim(coalesce(p_reason, '')), '') is null then
      raise exception 'admin call (%) needs a non-blank p_reason', v_admin;
    end if;
    if not exists (select 1 from public.teams where id = p_team) then raise exception 'no such team %', p_team; end if;
  elsif auth.uid() is null or p_team not in (select fn_user_teams()) then raise exception 'not a member of this team'; end if;
  if p_balance is null or p_balance < 0 or p_balance > 100000 then raise exception 'balance must be a whole number from 0'; end if;
  select jsonb_build_object('inmail_credits_balance', inmail_credits_balance, 'inmail_credits_low_at', inmail_credits_low_at,
                            'inmail_credits_updated_at', inmail_credits_updated_at, 'inmail_credits_updated_by', inmail_credits_updated_by)
    into v_before from public.team_settings where team_id = p_team;
  update public.team_settings set inmail_credits_balance = p_balance,
         inmail_credits_low_at = coalesce(p_low_at, inmail_credits_low_at)
   where team_id = p_team;
  if not found then raise exception 'no settings row for team %', p_team; end if;
  select * into r from public.v_inmail_credits where team_id = p_team;
  if v_admin is not null then
    insert into public.audit_log (team_id, actor_user_id, entity_type, entity_id, action, before_value, after_value, summary, source)
    select p_team, null, 'team_settings', p_team, 'admin_set_inmail_credits', v_before,
           jsonb_build_object('inmail_credits_balance', ts.inmail_credits_balance, 'inmail_credits_low_at', ts.inmail_credits_low_at,
                              'inmail_credits_updated_at', ts.inmail_credits_updated_at, 'inmail_credits_updated_by', ts.inmail_credits_updated_by,
                              'caller', jsonb_build_object('matched', v_admin, 'session_user', session_user::text, 'auth_role', auth.role())),
           btrim(p_reason), 'mcp_admin'
      from public.team_settings ts where ts.team_id = p_team;
  end if;
  return r;
end $function$;
alter function public.fn_set_inmail_credits(uuid, integer, integer, text) owner to postgres;

-- ---------------------------------------------------------------------------------------------------------------
-- ACL: exactly postgres, authenticated, service_role. Never anon, never PUBLIC (default privileges would add anon).
revoke all on function public.fn_mark_cr_withdrawn(uuid, uuid[], text) from public, anon;
revoke all on function public.fn_set_auto_score_new_companies(uuid, boolean, text) from public, anon;
revoke all on function public.fn_set_inmail_credits(uuid, integer, integer, text) from public, anon;
grant execute on function public.fn_mark_cr_withdrawn(uuid, uuid[], text) to postgres, authenticated, service_role;
grant execute on function public.fn_set_auto_score_new_companies(uuid, boolean, text) to postgres, authenticated, service_role;
grant execute on function public.fn_set_inmail_credits(uuid, integer, integer, text) to postgres, authenticated, service_role;

notify pgrst, 'reload schema';
