-- Migration 015: Security fixes for SECURITY DEFINER functions
--
-- The public schema has exactly one SECURITY DEFINER function: fn_user_teams(),
-- the RLS helper from migration 012 that returns the caller's team_ids. Because
-- it runs with the definer's privileges, it must be hardened:
--
--   1. SET search_path = public, pg_temp
--        Pins the search path so a malicious caller cannot shadow the objects
--        the function references (team_members, auth.uid) with same-named objects
--        in an attacker-controlled schema. (lint 0011 function_search_path_mutable)
--
--   2. REVOKE EXECUTE FROM PUBLIC, anon, service_role
--        Functions default-grant EXECUTE to PUBLIC. Additionally, Supabase sets
--        ALTER DEFAULT PRIVILEGES so every new function in `public` also gets an
--        EXPLICIT EXECUTE grant to anon, authenticated, and service_role. A bare
--        `REVOKE ... FROM PUBLIC` therefore does NOT remove anon's access — the
--        explicit per-role grant survives and anon can still call
--        /rest/v1/rpc/fn_user_teams. We must revoke the explicit grants too.
--        Revoking anon closes unauthenticated access (lint 0028 "Public Can
--        Execute SECURITY DEFINER Function"); revoking service_role enforces the
--        "only authenticated" rule (service_role bypasses RLS and never needs to
--        call this helper).
--
--   3. GRANT EXECUTE TO authenticated
--        The function is invoked inside the RLS policies of every team-scoped
--        table, evaluated as the calling role. Signed-in users therefore REQUIRE
--        EXECUTE or all queries against those tables fail with "permission denied
--        for function fn_user_teams".
--
-- Why it stays SECURITY DEFINER: the team_members SELECT policy itself calls
-- fn_user_teams(); running the function as INVOKER would re-enter that policy and
-- recurse infinitely. DEFINER breaks the recursion. Consequently lint 0029
-- ("Signed-In Users Can Execute SECURITY DEFINER Function") is expected to remain
-- and is the intended, safe end state.

CREATE OR REPLACE FUNCTION public.fn_user_teams()
RETURNS TABLE (team_id UUID)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT tm.team_id FROM public.team_members tm WHERE tm.user_id = (SELECT auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.fn_user_teams() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fn_user_teams() FROM anon;
REVOKE EXECUTE ON FUNCTION public.fn_user_teams() FROM service_role;
GRANT EXECUTE ON FUNCTION public.fn_user_teams() TO authenticated;
