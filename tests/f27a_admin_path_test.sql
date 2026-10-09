-- F27A regression test (migration 178): admin path on fn_mark_cr_withdrawn, fn_set_auto_score_new_companies and
-- fn_set_inmail_credits. Executable .sql in the style of tests/company_research_write_test.sql; always rolls back by
-- ending in raise 'TEST PASS …'. Any 'TEST FAIL …' (or any other error) is a failure.
-- Run as the database owner: psql "$DB_URL" -f tests/f27a_admin_path_test.sql  (or the Supabase MCP execute_sql).
-- Expected output: ERROR:  TEST PASS: F27A admin path (… checks, rolled back)
--
-- What this CAN and CANNOT prove from a direct database session:
--   * session_user stays 'postgres' even after SET ROLE, so a "signed-in member" or "non-member" cannot be simulated
--     here: any call in this session takes the admin branch. Check 6 asserts exactly that (so the test fails if the
--     predicate ever stops keying on session_user), and check 5 asserts statically that the member guard is intact.
--   * The live non-member path was proven separately over PostgREST (anon key → 401 permission denied for all three,
--     9 Oct, F27A report). A signed-in member call cannot be executed from a build session (no user JWT); not claimed.
do $$
declare
  f record; n int := 0; msg text; cid uuid; ret int; a int;
  expected_acl constant text := '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}';
begin
  -- 1-4. ACL exact, anon has no EXECUTE, owner postgres, SECURITY DEFINER, search_path intact.
  for f in select p.oid, p.proname, p.proacl::text acl, pg_get_userbyid(p.proowner) owner, p.prosecdef, p.proconfig
             from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public'
              and p.oid in ('public.fn_mark_cr_withdrawn(uuid, uuid[], text)'::regprocedure,
                            'public.fn_set_auto_score_new_companies(uuid, boolean, text)'::regprocedure,
                            'public.fn_set_inmail_credits(uuid, integer, integer, text)'::regprocedure)
  loop
    n := n + 1;
    if f.acl is distinct from expected_acl then raise exception 'TEST FAIL: % ACL is %', f.proname, f.acl; end if;
    if has_function_privilege('anon', f.oid, 'EXECUTE') then raise exception 'TEST FAIL: anon can execute %', f.proname; end if;
    if f.owner <> 'postgres' then raise exception 'TEST FAIL: % owner is %', f.proname, f.owner; end if;
    if not f.prosecdef then raise exception 'TEST FAIL: % is not SECURITY DEFINER', f.proname; end if;
    if f.proconfig is distinct from array['search_path=public, pg_temp'] then raise exception 'TEST FAIL: % proconfig is %', f.proname, f.proconfig; end if;
    -- 5. the original membership guard survives as the non-admin branch
    if pg_get_functiondef(f.oid) !~ 'elsif auth\.uid\(\) is null or p_team not in \(select (public\.)?fn_user_teams\(\)\) then raise exception ''not a member of this team''' then
      raise exception 'TEST FAIL: % lost the member guard', f.proname;
    end if;
  end loop;
  if n <> 3 then raise exception 'TEST FAIL: expected 3 functions with the p_reason signature, found %', n; end if;
  -- the old signatures must be gone (no anon-callable leftovers)
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public'
              and p.proname in ('fn_mark_cr_withdrawn','fn_set_auto_score_new_companies','fn_set_inmail_credits')
              and pg_get_function_identity_arguments(p.oid) not like '%p_reason text') then
    raise exception 'TEST FAIL: an old signature still exists';
  end if;
  -- fn_cr_queue_populate deliberately untouched: no authenticated, no anon
  if has_function_privilege('authenticated', 'public.fn_cr_queue_populate(uuid, boolean, integer)'::regprocedure, 'EXECUTE')
     or has_function_privilege('anon', 'public.fn_cr_queue_populate(uuid, boolean, integer)'::regprocedure, 'EXECUTE') then
    raise exception 'TEST FAIL: fn_cr_queue_populate ACL widened';
  end if;

  -- 6. an admin call with no reason, a blank reason, or under SET ROLE authenticated with a non-member JWT and no reason, RAISES.
  begin perform public.fn_set_auto_score_new_companies('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', false); msg := null;
  exception when others then msg := sqlerrm; end;
  if msg is null or msg not like 'admin call (session_user) needs a non-blank p_reason%' then raise exception 'TEST FAIL: no-reason admin call gave %', msg; end if;
  begin perform public.fn_set_inmail_credits('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', 1, null, '   '); msg := null;
  exception when others then msg := sqlerrm; end;
  if msg is null or msg not like 'admin call (session_user) needs a non-blank p_reason%' then raise exception 'TEST FAIL: blank-reason admin call gave %', msg; end if;
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000f27a","role":"authenticated"}', true);
  begin perform public.fn_mark_cr_withdrawn('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', array[]::uuid[]); msg := null;
  exception when others then msg := sqlerrm; end;
  reset role;
  perform set_config('request.jwt.claims', '', true);   -- clear the fake JWT, else later audit triggers record its sub
  if msg is null then raise exception 'TEST FAIL: non-member, no-reason call under SET ROLE authenticated did not raise'; end if;

  -- 7. an admin call WITH a reason writes exactly one mcp_admin audit row naming the matched half (rolled back).
  select id into cid from public.contacts where connection_status::text = 'Request sent' and archived_at is null order by contact_id limit 1;
  select count(*) into a from public.audit_log where source = 'mcp_admin';
  ret := public.fn_mark_cr_withdrawn('ef73c15e-4d6f-4159-bcfa-cc76b5ae4972', array[cid], 'F27A regression test (rolled back)');
  if ret <> 1 then raise exception 'TEST FAIL: admin withdraw returned %', ret; end if;
  if (select count(*) from public.audit_log where source = 'mcp_admin') <> a + 1 then raise exception 'TEST FAIL: no mcp_admin audit row'; end if;
  if not exists (select 1 from public.audit_log where source = 'mcp_admin' and summary = 'F27A regression test (rolled back)'
                   and actor_user_id is null and after_value->'caller'->>'matched' = 'session_user'
                   and after_value->'caller'->>'session_user' = 'postgres' and jsonb_array_length(before_value->'contacts') = 1) then
    raise exception 'TEST FAIL: audit row missing reason, caller or before values';
  end if;

  raise exception 'TEST PASS: F27A admin path (ACL, owner, search_path, guard, anon, reason, audit; rolled back)';
end $$;
